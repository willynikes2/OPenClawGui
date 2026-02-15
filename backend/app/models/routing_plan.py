"""Routing plan model — records how a user message was routed to agents/skills."""

import uuid
from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class RoutingIntent(str, PyEnum):
    daily_brief = "daily_brief"
    business_summary = "business_summary"
    explain_alert = "explain_alert"
    general_qna = "general_qna"
    control_action = "control_action"
    security_inquiry = "security_inquiry"


class SafetyPolicy(str, PyEnum):
    default = "default"
    restricted = "restricted"
    safe_mode = "safe_mode"


class RoutingPlan(Base):
    __tablename__ = "routing_plans"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("threads.id"), nullable=False, index=True
    )
    instance_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("instances.id"), nullable=False
    )
    intent: Mapped[RoutingIntent] = mapped_column(Enum(RoutingIntent), nullable=False)
    targets: Mapped[list | None] = mapped_column(JSONB)
    requires_approval: Mapped[bool] = mapped_column(Boolean, default=False)
    safety_policy: Mapped[SafetyPolicy] = mapped_column(
        Enum(SafetyPolicy), default=SafetyPolicy.default
    )
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    thread: Mapped["Thread"] = relationship(back_populates="routing_plans")
