"""Pydantic schemas for the Human-in-the-Loop Approvals API."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Request schemas
# ---------------------------------------------------------------------------

class ApprovalCreateRequest(BaseModel):
    """Bridge skill creates an approval request (HMAC auth)."""
    skill_name: str = Field(..., min_length=1, max_length=255)
    action: str  # send_email, exec_shell, access_sensitive_path, new_domain, bulk_export
    summary: str = Field(..., min_length=1, max_length=2000)
    risk_level: str  # warning, critical
    evidence: dict | None = None
    thread_id: uuid.UUID | None = None
    expires_in_seconds: int = Field(default=300, ge=60, le=3600)  # Default 5 min


class ApprovalDecideRequest(BaseModel):
    """User decides on an approval request (JWT auth)."""
    decision: str  # allow_once, allow_always, deny


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------

class ApprovalResponse(BaseModel):
    id: uuid.UUID
    instance_id: uuid.UUID
    thread_id: uuid.UUID | None = None
    skill_name: str
    action: str
    summary: str
    risk_level: str
    options: list | None = None
    evidence: dict | None = None
    status: str
    decided_by: uuid.UUID | None = None
    decided_at: datetime | None = None
    decision: str | None = None
    expires_at: datetime
    created_at: datetime

    model_config = {"from_attributes": True}
