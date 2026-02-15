import uuid
from datetime import datetime

from pydantic import BaseModel

from app.models.command import CommandStatus, CommandType


class CommandCreate(BaseModel):
    command_type: CommandType
    payload: dict | None = None
    reason: str | None = None


class CommandResponse(BaseModel):
    id: uuid.UUID
    instance_id: uuid.UUID
    command_type: CommandType
    payload: dict | None
    status: CommandStatus
    reason: str | None
    result_message: str | None
    created_at: datetime
    acknowledged_at: datetime | None
    completed_at: datetime | None

    model_config = {"from_attributes": True}


class CommandAcknowledge(BaseModel):
    status: CommandStatus  # acknowledged, completed, or failed
    result_message: str | None = None


class PendingCommandsResponse(BaseModel):
    commands: list[CommandResponse]
