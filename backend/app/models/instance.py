import uuid
from datetime import datetime
from enum import Enum as PyEnum

from sqlalchemy import DateTime, Enum, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class InstanceMode(str, PyEnum):
    active = "active"
    paused = "paused"
    safe = "safe"


class HealthStatus(str, PyEnum):
    ok = "ok"
    degraded = "degraded"
    offline = "offline"


class Instance(Base):
    __tablename__ = "instances"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    shared_secret: Mapped[str] = mapped_column(String(512), nullable=False)
    mode: Mapped[InstanceMode] = mapped_column(Enum(InstanceMode), default=InstanceMode.active)
    health: Mapped[HealthStatus] = mapped_column(Enum(HealthStatus), default=HealthStatus.offline)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="instances")
    integration_tokens: Mapped[list["IntegrationToken"]] = relationship(
        back_populates="instance", cascade="all, delete-orphan"
    )
    events: Mapped[list["Event"]] = relationship(back_populates="instance", cascade="all, delete-orphan")


class IntegrationToken(Base):
    __tablename__ = "integration_tokens"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    instance_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("instances.id"), nullable=False
    )
    token_hash: Mapped[str] = mapped_column(String(512), nullable=False, unique=True)
    label: Mapped[str] = mapped_column(String(255), default="default")
    scope: Mapped[str | None] = mapped_column(String(255))  # skill name scope
    is_revoked: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    instance: Mapped["Instance"] = relationship(back_populates="integration_tokens")
