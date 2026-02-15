import uuid
from datetime import datetime

from pydantic import BaseModel

from app.models.event import Severity


class AlertResponse(BaseModel):
    id: uuid.UUID
    event_id: uuid.UUID
    instance_id: uuid.UUID
    detector_name: str
    skill_name: str
    severity: Severity
    explanation: str
    recommended_action: str
    evidence: dict | None
    created_at: datetime

    model_config = {"from_attributes": True}


class AlertListResponse(BaseModel):
    alerts: list[AlertResponse]
    next_cursor: str | None


class RiskSummaryResponse(BaseModel):
    total_alerts_today: int
    most_common_detector: str | None
    last_critical_timestamp: datetime | None
    status: str  # "ok" | "degraded" | "critical"


class ContainmentRequest(BaseModel):
    reason: str = "user_action"  # "security_alert" | "user_action"
    alert_id: uuid.UUID | None = None


class ContainmentResponse(BaseModel):
    status: str
    instance_id: uuid.UUID | None = None
    skill_name: str | None = None
    token_revoked: bool | None = None
    timestamp: datetime


class SkillResponse(BaseModel):
    id: uuid.UUID
    name: str
    trust_status: str
    last_run: datetime | None
    instance_id: uuid.UUID
    created_at: datetime
    observed_behaviors: list[str] = []

    model_config = {"from_attributes": True}


class SkillTrustUpdateRequest(BaseModel):
    trust_status: str  # "trusted" | "untrusted" | "unknown"
