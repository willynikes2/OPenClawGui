import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.event import Event
from app.models.instance import Instance, InstanceMode
from app.schemas.event import EventIngest, EventResponse
from app.security.encryption import encryption_service
from app.security.hmac_verify import verify_hmac
from app.security.pii_scrubber import scrub_dict, scrub_text

router = APIRouter()


@router.post("/ingest", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
async def ingest_event(
    request: Request,
    x_signature: str = Header(...),
    x_timestamp: str = Header(...),
    x_instance_id: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    # Look up instance
    result = await db.execute(select(Instance).where(Instance.id == x_instance_id))
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")

    # Check if instance is paused/safe mode (reject ingest)
    if instance.mode != InstanceMode.active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Instance is in {instance.mode.value} mode, ingest rejected",
        )

    # Read raw body for HMAC verification
    raw_body = await request.body()
    payload_str = raw_body.decode("utf-8")

    # Verify HMAC
    if not verify_hmac(instance.shared_secret, x_timestamp, payload_str, x_signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature")

    # Parse body
    body = EventIngest.model_validate_json(raw_body)

    # PII scrubbing
    pii_redacted = False

    scrubbed_title, title_redacted = scrub_text(body.title)
    pii_redacted = pii_redacted or title_redacted

    encrypted_body_raw = None
    if body.body_raw:
        scrubbed_raw, raw_redacted = scrub_text(body.body_raw)
        pii_redacted = pii_redacted or raw_redacted
        encrypted_body_raw = encryption_service.encrypt(scrubbed_raw)

    scrubbed_structured = body.body_structured_json
    if body.body_structured_json:
        scrubbed_structured, struct_redacted = scrub_dict(body.body_structured_json)
        pii_redacted = pii_redacted or struct_redacted

    # Store event
    event = Event(
        user_id=instance.user_id,
        instance_id=instance.id,
        source_type=body.source_type,
        agent_name=body.agent_name,
        skill_name=body.skill_name,
        timestamp=body.timestamp,
        title=scrubbed_title,
        body_raw=encrypted_body_raw,
        body_structured_json=scrubbed_structured,
        tags=body.tags,
        severity=body.severity,
        pii_redacted=pii_redacted,
        hmac_signature=x_signature,
    )
    db.add(event)
    await db.flush()
    await db.refresh(event)

    # Update instance last_seen
    instance.last_seen = datetime.now(timezone.utc)
    instance.health = "ok"

    return event
