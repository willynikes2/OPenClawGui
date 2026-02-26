"""Approvals API — Human-in-the-Loop approval endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Path, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.approval import ApprovalStatus
from app.models.instance import Instance
from app.models.user import User
from app.schemas.approval import (
    ApprovalCreateRequest,
    ApprovalDecideRequest,
    ApprovalResponse,
)
from app.security.hmac_verify import verify_hmac
from app.services.approval import ApprovalService

router = APIRouter()


# ===================================================================
# POST /approvals — bridge skill creates an approval request (HMAC auth)
# ===================================================================

@router.post("/approvals", response_model=ApprovalResponse, status_code=status.HTTP_201_CREATED)
async def create_approval(
    body: ApprovalCreateRequest,
    x_signature: str = Header(...),
    x_timestamp: str = Header(...),
    x_instance_id: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Bridge skill creates an approval request for a sensitive action.

    HMAC-authenticated using the instance shared secret.
    """
    try:
        instance_id = uuid.UUID(x_instance_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid instance ID")

    result = await db.execute(select(Instance).where(Instance.id == instance_id))
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")

    if not verify_hmac(instance.shared_secret, x_timestamp, "", x_signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature")

    svc = ApprovalService(db)
    approval = await svc.create_approval(
        instance_id=instance_id,
        skill_name=body.skill_name,
        action=body.action,
        summary=body.summary,
        risk_level=body.risk_level,
        evidence=body.evidence,
        thread_id=body.thread_id,
        expires_in_seconds=body.expires_in_seconds,
    )

    return ApprovalResponse.model_validate(approval)


# ===================================================================
# POST /approvals/{id}/decide — user approves or denies (JWT auth)
# ===================================================================

@router.post("/approvals/{approval_id}/decide", response_model=ApprovalResponse)
async def decide_approval(
    body: ApprovalDecideRequest,
    approval_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """User decides on an approval request: allow_once, allow_always, or deny.

    Creates an approve_action command for the bridge skill.
    Decision is audited with user ID and timestamp.
    """
    if body.decision not in ("allow_once", "allow_always", "deny"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Decision must be one of: allow_once, allow_always, deny",
        )

    svc = ApprovalService(db)
    approval = await svc.decide_approval(
        approval_id=approval_id,
        user_id=user.id,
        decision=body.decision,
    )

    if not approval:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Approval not found, already decided, or expired",
        )

    return ApprovalResponse.model_validate(approval)


# ===================================================================
# GET /approvals — list approvals for an instance (JWT auth)
# ===================================================================

@router.get("/approvals", response_model=list[ApprovalResponse])
async def list_approvals(
    instance_id: uuid.UUID = Query(...),
    approval_status: str | None = Query(None, alias="status"),
    limit: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List approval requests for an instance, optionally filtered by status."""
    # Verify user owns the instance
    result = await db.execute(
        select(Instance).where(Instance.id == instance_id, Instance.user_id == user.id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")

    svc = ApprovalService(db)

    # Expire stale approvals before listing
    await svc.expire_stale_approvals(instance_id)

    approvals = await svc.list_approvals(
        instance_id=instance_id,
        status=approval_status,
        limit=limit,
    )

    return [ApprovalResponse.model_validate(a) for a in approvals]
