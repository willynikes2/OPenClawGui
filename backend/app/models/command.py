import uuid
from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import DateTime, Enum, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class CommandType(str, PyEnum):
    pause = "pause"
    resume = "resume"
    disable_skill = "disable_skill"
    stop_run = "stop_run"
    test_run = "test_run"


class CommandStatus(str, PyEnum):
    pending = "pending"
    acknowledged = "acknowledged"
    completed = "completed"
    failed = "failed"


class Command(Base):
    __tablename__ = "commands"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instance_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("instances.id"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    command_type: Mapped[CommandType] = mapped_column(Enum(CommandType), nullable=False)
    payload: Mapped[dict | None] = mapped_column(JSONB)
    status: Mapped[CommandStatus] = mapped_column(Enum(CommandStatus), default=CommandStatus.pending, index=True)
    reason: Mapped[str | None] = mapped_column(String(255))
    result_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
