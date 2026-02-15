"""Chat API — Unified Assistant conversation endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Path, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.instance import Instance
from app.models.message import Message
from app.models.routing_plan import RoutingPlan
from app.models.thread import Thread
from app.models.user import User
from app.schemas.chat import (
    AttachContextRequest,
    ChatReceiveRequest,
    ChatSendRequest,
    ChatSendResponse,
    MessageResponse,
    RoutingPlanResponse,
    ThreadDetailResponse,
    ThreadResponse,
)
from app.security.hmac_verify import verify_hmac
from app.services.conversation import ConversationService
from app.services.orchestrator import OrchestratorService
from app.services.router import classify_intent

router = APIRouter()


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

async def _get_user_instance(
    instance_id: uuid.UUID, user: User, db: AsyncSession,
) -> Instance:
    result = await db.execute(
        select(Instance).where(Instance.id == instance_id, Instance.user_id == user.id)
    )
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")
    return instance


# ===================================================================
# POST /chat/send — user sends a message
# ===================================================================

@router.post("/chat/send", response_model=ChatSendResponse, status_code=status.HTTP_201_CREATED)
async def chat_send(
    body: ChatSendRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Send a user message. Returns the routing plan and enqueues commands."""
    instance = await _get_user_instance(body.instance_id, user, db)

    conv = ConversationService(db)
    orch = OrchestratorService(db)

    # 1. Get or create thread
    thread = await conv.get_or_create_thread(
        user_id=user.id,
        instance_id=instance.id,
        thread_id=body.thread_id,
    )

    # 2. Store user message
    user_msg = await conv.add_user_message(
        thread=thread,
        content=body.content,
        event_id=body.attached_event_id,
        alert_id=body.attached_alert_id,
    )

    # Auto-title from first message
    await conv.update_thread_title(thread, body.content)

    # 3. Route the message
    routing_result = classify_intent(body.content)

    # 4. Save routing plan
    plan = RoutingPlan(
        thread_id=thread.id,
        instance_id=instance.id,
        intent=routing_result.intent,
        targets=[
            {"type": t.type, "name": t.name, "confidence": t.confidence, "params": t.params}
            for t in routing_result.targets
        ],
        requires_approval=routing_result.requires_approval,
        safety_policy=routing_result.safety_policy,
        notes=routing_result.notes,
    )
    await conv.save_routing_plan(plan)

    # 5. Add system message showing routing
    target_desc = routing_result.targets[0].name if routing_result.targets else "default"
    sys_content = f"Routed to: {target_desc} ({routing_result.intent.value})"
    sys_msg = await conv.add_system_message(thread, sys_content, routing_plan_id=plan.id)

    # 6. Execute routing plan — create commands for the instance
    await orch.execute_routing_plan(plan, user.id, body.content)

    return ChatSendResponse(
        thread_id=thread.id,
        user_message=MessageResponse.model_validate(user_msg),
        routing_plan=RoutingPlanResponse.model_validate(plan),
        system_message=MessageResponse.model_validate(sys_msg),
    )


# ===================================================================
# GET /chat/threads — list user threads
# ===================================================================

@router.get("/chat/threads", response_model=list[ThreadResponse])
async def list_threads(
    instance_id: uuid.UUID | None = Query(None),
    limit: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List the user's chat threads, newest first."""
    conv = ConversationService(db)
    threads = await conv.list_threads(user.id, instance_id, limit)

    results = []
    for thread in threads:
        # Get last message for preview
        messages = await conv.get_last_messages(thread.id, limit=1)
        last_msg = MessageResponse.model_validate(messages[0]) if messages else None
        results.append(ThreadResponse(
            id=thread.id,
            instance_id=thread.instance_id,
            title=thread.title,
            created_at=thread.created_at,
            updated_at=thread.updated_at,
            last_message=last_msg,
        ))
    return results


# ===================================================================
# GET /chat/thread/{thread_id} — get thread with messages
# ===================================================================

@router.get("/chat/thread/{thread_id}", response_model=ThreadDetailResponse)
async def get_thread(
    thread_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a chat thread with all its messages."""
    conv = ConversationService(db)
    thread = await conv.get_thread_with_messages(thread_id, user.id)
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")

    return ThreadDetailResponse(
        id=thread.id,
        instance_id=thread.instance_id,
        title=thread.title,
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        messages=[MessageResponse.model_validate(m) for m in thread.messages],
    )


# ===================================================================
# POST /chat/receive — bridge skill sends agent response (HMAC auth)
# ===================================================================

@router.post("/chat/receive", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def chat_receive(
    body: ChatReceiveRequest,
    x_signature: str = Header(...),
    x_timestamp: str = Header(...),
    x_instance_id: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Bridge skill sends an agent response back to the conversation.

    HMAC-authenticated using the instance shared secret.
    """
    # Look up instance
    try:
        instance_id = uuid.UUID(x_instance_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid instance ID")

    result = await db.execute(select(Instance).where(Instance.id == instance_id))
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")

    if not verify_hmac(instance.shared_secret, x_timestamp, "", x_signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature")

    # Verify thread belongs to the instance
    thread_result = await db.execute(
        select(Thread).where(Thread.id == body.thread_id, Thread.instance_id == instance_id)
    )
    if not thread_result.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")

    conv = ConversationService(db)
    msg = await conv.add_agent_response(
        thread_id=body.thread_id,
        correlation_id=body.correlation_id,
        content=body.content,
        structured_json=body.structured_json,
        tool_usage=body.tool_usage,
    )

    return MessageResponse.model_validate(msg)


# ===================================================================
# POST /chat/attach_context — attach event/alert to thread
# ===================================================================

@router.post("/chat/attach_context", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def attach_context(
    body: AttachContextRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Attach an event or alert reference to the conversation as a system message."""
    conv = ConversationService(db)
    thread = await conv.get_thread_with_messages(body.thread_id, user.id)
    if not thread:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Thread not found")

    parts = []
    if body.event_id:
        parts.append(f"Attached event: {body.event_id}")
    if body.alert_id:
        parts.append(f"Attached alert: {body.alert_id}")

    content = "; ".join(parts) if parts else "Context attached"

    msg = await conv.add_system_message(thread, content)
    # Store references on the message
    if body.event_id:
        msg.event_id = body.event_id
    if body.alert_id:
        msg.alert_id = body.alert_id
    await db.flush()

    return MessageResponse.model_validate(msg)
