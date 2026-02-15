"""Alerts API — list, detail, risk summary, and containment endpoints."""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.alert import Alert
from app.models.event import Severity
from app.models.instance import Instance, InstanceMode, IntegrationToken
from app.models.skill import Skill, TrustStatus
from app.models.user import User
from app.schemas.alert import (
    AlertListResponse,
    AlertResponse,
    ContainmentRequest,
    ContainmentResponse,
    RiskSummaryResponse,
    SkillResponse,
    SkillTrustUpdateRequest,
)

router = APIRouter()


# ---------------------------------------------------------------------------
# Helper: verify instance belongs to user
# ---------------------------------------------------------------------------

async def _get_user_instance(
    instance_id: uuid.UUID,
    user: User,
    db: AsyncSession,
) -> Instance:
    result = await db.execute(
        select(Instance).where(Instance.id == instance_id, Instance.user_id == user.id)
    )
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")
    return instance


# ===================================================================
# Alerts CRUD
# ===================================================================

@router.get(
    "/instances/{instance_id}/alerts",
    response_model=AlertListResponse,
)
async def list_alerts(
    instance_id: uuid.UUID = Path(...),
    severity: Severity | None = Query(None),
    detector: str | None = Query(None),
    limit: int = Query(20, ge=1, le=100),
    cursor: str | None = Query(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List alerts for an instance with optional severity/detector filters."""
    await _get_user_instance(instance_id, user, db)

    query = select(Alert).where(Alert.instance_id == instance_id)

    if severity:
        query = query.where(Alert.severity == severity)
    if detector:
        query = query.where(Alert.detector_name == detector)
    if cursor:
        try:
            cursor_dt = datetime.fromisoformat(cursor)
            query = query.where(Alert.created_at < cursor_dt)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid cursor format")

    query = query.order_by(Alert.created_at.desc()).limit(limit + 1)
    result = await db.execute(query)
    alerts = list(result.scalars().all())

    next_cursor = None
    if len(alerts) > limit:
        alerts = alerts[:limit]
        next_cursor = alerts[-1].created_at.isoformat()

    return AlertListResponse(
        alerts=[AlertResponse.model_validate(a) for a in alerts],
        next_cursor=next_cursor,
    )


@router.get(
    "/alerts/{alert_id}",
    response_model=AlertResponse,
)
async def get_alert(
    alert_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a single alert by ID."""
    result = await db.execute(
        select(Alert).where(Alert.id == alert_id, Alert.user_id == user.id)
    )
    alert = result.scalar_one_or_none()
    if not alert:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found")
    return alert


# ===================================================================
# Risk Summary
# ===================================================================

@router.get(
    "/instances/{instance_id}/risk-summary",
    response_model=RiskSummaryResponse,
)
async def risk_summary(
    instance_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get today's risk summary for an instance."""
    await _get_user_instance(instance_id, user, db)

    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    # Total alerts today
    count_result = await db.execute(
        select(func.count(Alert.id)).where(
            Alert.instance_id == instance_id,
            Alert.created_at >= today_start,
        )
    )
    total_today = count_result.scalar() or 0

    # Most common detector today
    detector_result = await db.execute(
        select(Alert.detector_name, func.count(Alert.id).label("cnt"))
        .where(Alert.instance_id == instance_id, Alert.created_at >= today_start)
        .group_by(Alert.detector_name)
        .order_by(func.count(Alert.id).desc())
        .limit(1)
    )
    top_detector_row = detector_result.first()
    most_common = top_detector_row[0] if top_detector_row else None

    # Last critical timestamp
    critical_result = await db.execute(
        select(Alert.created_at)
        .where(
            Alert.instance_id == instance_id,
            Alert.severity == Severity.critical,
        )
        .order_by(Alert.created_at.desc())
        .limit(1)
    )
    last_critical = critical_result.scalar_one_or_none()

    # Status determination
    critical_today_result = await db.execute(
        select(func.count(Alert.id)).where(
            Alert.instance_id == instance_id,
            Alert.severity == Severity.critical,
            Alert.created_at >= today_start,
        )
    )
    critical_count = critical_today_result.scalar() or 0

    if critical_count > 0:
        risk_status = "critical"
    elif total_today > 5:
        risk_status = "degraded"
    else:
        risk_status = "ok"

    return RiskSummaryResponse(
        total_alerts_today=total_today,
        most_common_detector=most_common,
        last_critical_timestamp=last_critical,
        status=risk_status,
    )


# ===================================================================
# Containment Endpoints
# ===================================================================

@router.post(
    "/instances/{instance_id}/pause",
    response_model=ContainmentResponse,
)
async def pause_instance(
    body: ContainmentRequest,
    instance_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Pause an instance — all ingest is rejected."""
    instance = await _get_user_instance(instance_id, user, db)
    instance.mode = InstanceMode.paused
    await db.flush()

    return ContainmentResponse(
        status="paused",
        instance_id=instance.id,
        timestamp=datetime.now(timezone.utc),
    )


@router.post(
    "/instances/{instance_id}/resume",
    response_model=ContainmentResponse,
)
async def resume_instance(
    instance_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Resume a paused instance."""
    instance = await _get_user_instance(instance_id, user, db)
    instance.mode = InstanceMode.active
    await db.flush()

    return ContainmentResponse(
        status="active",
        instance_id=instance.id,
        timestamp=datetime.now(timezone.utc),
    )


@router.post(
    "/instances/{instance_id}/kill-switch",
    response_model=ContainmentResponse,
)
async def kill_switch(
    body: ContainmentRequest,
    instance_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kill switch — instance goes safe mode, all tokens revoked."""
    instance = await _get_user_instance(instance_id, user, db)
    instance.mode = InstanceMode.safe

    # Revoke all integration tokens
    tokens_result = await db.execute(
        select(IntegrationToken).where(
            IntegrationToken.instance_id == instance_id,
            IntegrationToken.is_revoked == False,
        )
    )
    tokens = tokens_result.scalars().all()
    for token in tokens:
        token.is_revoked = True
        token.revoked_at = datetime.now(timezone.utc)

    await db.flush()

    return ContainmentResponse(
        status="killed",
        instance_id=instance.id,
        token_revoked=True,
        timestamp=datetime.now(timezone.utc),
    )


# ===================================================================
# Skill Management
# ===================================================================

@router.get(
    "/instances/{instance_id}/skills",
    response_model=list[SkillResponse],
)
async def list_skills(
    instance_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List skills for an instance with observed detector behaviors."""
    await _get_user_instance(instance_id, user, db)

    result = await db.execute(
        select(Skill).where(Skill.instance_id == instance_id).order_by(Skill.name)
    )
    skills = result.scalars().all()

    responses = []
    for skill in skills:
        # Get distinct detectors that have fired for this skill
        det_result = await db.execute(
            select(Alert.detector_name)
            .where(
                Alert.instance_id == instance_id,
                Alert.skill_name == skill.name,
            )
            .distinct()
        )
        behaviors = [row[0] for row in det_result.all()]

        resp = SkillResponse.model_validate(skill)
        resp.observed_behaviors = behaviors
        responses.append(resp)

    return responses


@router.put(
    "/instances/{instance_id}/skills/{skill_name}/trust",
    response_model=SkillResponse,
)
async def update_skill_trust(
    body: SkillTrustUpdateRequest,
    instance_id: uuid.UUID = Path(...),
    skill_name: str = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update the trust status of a skill."""
    await _get_user_instance(instance_id, user, db)

    try:
        new_status = TrustStatus(body.trust_status)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid trust_status: {body.trust_status}")

    result = await db.execute(
        select(Skill).where(Skill.instance_id == instance_id, Skill.name == skill_name)
    )
    skill = result.scalar_one_or_none()
    if not skill:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Skill not found")

    skill.trust_status = new_status
    await db.flush()
    await db.refresh(skill)

    # Get observed behaviors
    det_result = await db.execute(
        select(Alert.detector_name)
        .where(Alert.instance_id == instance_id, Alert.skill_name == skill_name)
        .distinct()
    )
    behaviors = [row[0] for row in det_result.all()]

    resp = SkillResponse.model_validate(skill)
    resp.observed_behaviors = behaviors
    return resp


@router.post(
    "/instances/{instance_id}/skills/{skill_name}/disable",
    response_model=ContainmentResponse,
)
async def disable_skill(
    body: ContainmentRequest,
    instance_id: uuid.UUID = Path(...),
    skill_name: str = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Disable (untrust) a skill — events from it will be flagged."""
    await _get_user_instance(instance_id, user, db)

    result = await db.execute(
        select(Skill).where(Skill.instance_id == instance_id, Skill.name == skill_name)
    )
    skill = result.scalar_one_or_none()
    if not skill:
        # Auto-create skill record as untrusted
        skill = Skill(
            instance_id=instance_id,
            name=skill_name,
            trust_status=TrustStatus.untrusted,
        )
        db.add(skill)
    else:
        skill.trust_status = TrustStatus.untrusted

    await db.flush()

    return ContainmentResponse(
        status="disabled",
        instance_id=instance_id,
        skill_name=skill_name,
        timestamp=datetime.now(timezone.utc),
    )
