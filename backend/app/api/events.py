import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.event import Event, Severity, SourceType
from app.models.user import User
from app.schemas.event import EventDetailResponse, EventListResponse, EventResponse
from app.security.encryption import encryption_service

router = APIRouter()


@router.get("", response_model=EventListResponse)
async def list_events(
    instance_id: uuid.UUID | None = Query(None),
    severity: Severity | None = Query(None),
    source_type: SourceType | None = Query(None),
    agent_name: str | None = Query(None),
    skill_name: str | None = Query(None),
    cursor: str | None = Query(None, description="ISO 8601 timestamp cursor for pagination"),
    limit: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = select(Event).where(Event.user_id == user.id)

    if instance_id:
        query = query.where(Event.instance_id == instance_id)
    if severity:
        query = query.where(Event.severity == severity)
    if source_type:
        query = query.where(Event.source_type == source_type)
    if agent_name:
        query = query.where(Event.agent_name == agent_name)
    if skill_name:
        query = query.where(Event.skill_name == skill_name)
    if cursor:
        cursor_dt = datetime.fromisoformat(cursor)
        query = query.where(Event.created_at < cursor_dt)

    query = query.order_by(Event.created_at.desc()).limit(limit + 1)

    result = await db.execute(query)
    events = list(result.scalars().all())

    next_cursor = None
    if len(events) > limit:
        events = events[:limit]
        next_cursor = events[-1].created_at.isoformat()

    return EventListResponse(events=events, next_cursor=next_cursor)


@router.get("/{event_id}", response_model=EventDetailResponse)
async def get_event(
    event_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Event).where(Event.id == event_id, Event.user_id == user.id)
    )
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    # Decrypt body_raw for detail view
    decrypted_raw = None
    if event.body_raw:
        try:
            decrypted_raw = encryption_service.decrypt(event.body_raw)
        except Exception:
            decrypted_raw = "[Decryption failed]"

    resp = EventDetailResponse.model_validate(event)
    resp.body_raw = decrypted_raw
    return resp
