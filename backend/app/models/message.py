"""Chat message model — individual messages within a thread."""

import uuid
from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import DateTime, Enum, ForeignKey, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class MessageType(str, PyEnum):
    user_message = "user_message"
    assistant_message = "assistant_message"
    agent_message = "agent_message"
    structured_card_message = "structured_card_message"
    system_message = "system_message"
    approval_request = "approval_request"


class SenderType(str, PyEnum):
    user = "user"
    assistant = "assistant"
    agent = "agent"
    system = "system"


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("threads.id"), nullable=False, index=True
    )
    message_type: Mapped[MessageType] = mapped_column(Enum(MessageType), nullable=False)
    sender_type: Mapped[SenderType] = mapped_column(Enum(SenderType), nullable=False)
    content: Mapped[str | None] = mapped_column(Text)
    structured_json: Mapped[dict | None] = mapped_column(JSONB)
    routing_plan_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("routing_plans.id")
    )
    correlation_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    event_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("events.id")
    )
    alert_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("alerts.id")
    )
    tool_usage: Mapped[dict | None] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

    thread: Mapped["Thread"] = relationship(back_populates="messages")
