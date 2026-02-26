"""ApprovalRequest model — human-in-the-loop approval for sensitive agent actions."""

import uuid
from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class ApprovalAction(str, PyEnum):
    send_email = "send_email"
    exec_shell = "exec_shell"
    access_sensitive_path = "access_sensitive_path"
    new_domain = "new_domain"
    bulk_export = "bulk_export"


class ApprovalRiskLevel(str, PyEnum):
    warning = "warning"
    critical = "critical"


class ApprovalStatus(str, PyEnum):
    pending = "pending"
    approved = "approved"
    denied = "denied"
    expired = "expired"


class ApprovalRequest(Base):
    __tablename__ = "approval_requests"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instance_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("instances.id"), nullable=False, index=True
    )
    thread_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("threads.id"), index=True
    )
    skill_name: Mapped[str] = mapped_column(String(255), nullable=False)
    action: Mapped[ApprovalAction] = mapped_column(Enum(ApprovalAction), nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    risk_level: Mapped[ApprovalRiskLevel] = mapped_column(Enum(ApprovalRiskLevel), nullable=False)
    options: Mapped[list | None] = mapped_column(JSONB, default=lambda: ["allow_once", "allow_always", "deny"])
    evidence: Mapped[dict | None] = mapped_column(JSONB)
    status: Mapped[ApprovalStatus] = mapped_column(
        Enum(ApprovalStatus), default=ApprovalStatus.pending, index=True
    )
    decided_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id")
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decision: Mapped[str | None] = mapped_column(String(50))  # allow_once, allow_always, deny
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
