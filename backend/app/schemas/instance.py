import uuid
from datetime import datetime

from pydantic import BaseModel

from app.models.instance import HealthStatus, InstanceMode


class InstanceCreate(BaseModel):
    name: str


class InstanceResponse(BaseModel):
    id: uuid.UUID
    name: str
    mode: InstanceMode
    health: HealthStatus
    last_seen: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}


class InstanceWithSecret(InstanceResponse):
    shared_secret: str


class IntegrationTokenCreate(BaseModel):
    label: str = "default"
    scope: str | None = None


class IntegrationTokenResponse(BaseModel):
    id: uuid.UUID
    instance_id: uuid.UUID
    label: str
    scope: str | None
    is_revoked: bool
    created_at: datetime
    # Only returned on creation
    raw_token: str | None = None

    model_config = {"from_attributes": True}
