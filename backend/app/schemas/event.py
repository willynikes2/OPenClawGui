import uuid
from datetime import datetime

from pydantic import BaseModel

from app.models.event import Severity, SourceType


class EventIngest(BaseModel):
    source_type: SourceType
    agent_name: str
    skill_name: str
    timestamp: datetime
    title: str
    body_raw: str | None = None
    body_structured_json: dict | None = None
    tags: list[str] | None = None
    severity: Severity = Severity.info


class EventResponse(BaseModel):
    id: uuid.UUID
    instance_id: uuid.UUID
    source_type: SourceType
    agent_name: str
    skill_name: str
    timestamp: datetime
    title: str
    body_structured_json: dict | None
    tags: list[str] | None
    severity: Severity
    pii_redacted: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class EventDetailResponse(EventResponse):
    body_raw: str | None


class EventListResponse(BaseModel):
    events: list[EventResponse]
    next_cursor: str | None
