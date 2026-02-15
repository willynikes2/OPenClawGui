"""Pydantic schemas for the Chat / Unified Assistant API."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Request schemas
# ---------------------------------------------------------------------------

class ChatSendRequest(BaseModel):
    """User sends a message in a thread."""
    thread_id: uuid.UUID | None = None  # None = create new thread
    instance_id: uuid.UUID
    content: str = Field(..., min_length=1, max_length=4000)
    attached_event_id: uuid.UUID | None = None
    attached_alert_id: uuid.UUID | None = None


class ChatReceiveRequest(BaseModel):
    """Bridge skill sends an agent response back to the backend (HMAC auth)."""
    thread_id: uuid.UUID
    correlation_id: uuid.UUID
    content: str | None = None
    structured_json: dict | None = None
    tool_usage: dict | None = None
    skill_name: str | None = None
    agent_name: str | None = None


class AttachContextRequest(BaseModel):
    """Attach an event or alert reference to the next message in a thread."""
    thread_id: uuid.UUID
    event_id: uuid.UUID | None = None
    alert_id: uuid.UUID | None = None


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------

class RoutingPlanResponse(BaseModel):
    id: uuid.UUID
    thread_id: uuid.UUID
    instance_id: uuid.UUID
    intent: str
    targets: list | None = None
    requires_approval: bool
    safety_policy: str
    notes: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class MessageResponse(BaseModel):
    id: uuid.UUID
    thread_id: uuid.UUID
    message_type: str
    sender_type: str
    content: str | None = None
    structured_json: dict | None = None
    routing_plan_id: uuid.UUID | None = None
    correlation_id: uuid.UUID | None = None
    event_id: uuid.UUID | None = None
    alert_id: uuid.UUID | None = None
    tool_usage: dict | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class ThreadResponse(BaseModel):
    id: uuid.UUID
    instance_id: uuid.UUID
    title: str | None = None
    created_at: datetime
    updated_at: datetime
    last_message: MessageResponse | None = None

    model_config = {"from_attributes": True}


class ThreadDetailResponse(BaseModel):
    id: uuid.UUID
    instance_id: uuid.UUID
    title: str | None = None
    created_at: datetime
    updated_at: datetime
    messages: list[MessageResponse]

    model_config = {"from_attributes": True}


class ChatSendResponse(BaseModel):
    """Response from POST /chat/send."""
    thread_id: uuid.UUID
    user_message: MessageResponse
    routing_plan: RoutingPlanResponse
    system_message: MessageResponse | None = None
