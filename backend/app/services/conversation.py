"""ConversationService — CRUD for chat threads and messages."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.message import Message, MessageType, SenderType
from app.models.routing_plan import RoutingPlan
from app.models.thread import Thread


class ConversationService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # ------------------------------------------------------------------
    # Threads
    # ------------------------------------------------------------------

    async def get_or_create_thread(
        self,
        user_id: uuid.UUID,
        instance_id: uuid.UUID,
        thread_id: uuid.UUID | None = None,
    ) -> Thread:
        """Return existing thread or create a new one."""
        if thread_id:
            result = await self.db.execute(
                select(Thread).where(Thread.id == thread_id, Thread.user_id == user_id)
            )
            thread = result.scalar_one_or_none()
            if thread:
                return thread

        thread = Thread(
            id=thread_id or uuid.uuid4(),
            user_id=user_id,
            instance_id=instance_id,
        )
        self.db.add(thread)
        await self.db.flush()
        return thread

    async def list_threads(
        self,
        user_id: uuid.UUID,
        instance_id: uuid.UUID | None = None,
        limit: int = 20,
    ) -> list[Thread]:
        """List threads for a user, newest first."""
        stmt = select(Thread).where(Thread.user_id == user_id)
        if instance_id:
            stmt = stmt.where(Thread.instance_id == instance_id)
        stmt = stmt.order_by(Thread.updated_at.desc()).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_thread_with_messages(
        self,
        thread_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Thread | None:
        """Get a single thread with all its messages."""
        result = await self.db.execute(
            select(Thread)
            .where(Thread.id == thread_id, Thread.user_id == user_id)
            .options(selectinload(Thread.messages))
        )
        return result.scalar_one_or_none()

    async def update_thread_title(self, thread: Thread, title: str) -> None:
        """Auto-generate a thread title from the first user message."""
        if thread.title is None:
            thread.title = title[:100]
            await self.db.flush()

    # ------------------------------------------------------------------
    # Messages
    # ------------------------------------------------------------------

    async def add_user_message(
        self,
        thread: Thread,
        content: str,
        event_id: uuid.UUID | None = None,
        alert_id: uuid.UUID | None = None,
    ) -> Message:
        msg = Message(
            thread_id=thread.id,
            message_type=MessageType.user_message,
            sender_type=SenderType.user,
            content=content,
            event_id=event_id,
            alert_id=alert_id,
        )
        self.db.add(msg)
        thread.updated_at = datetime.now(timezone.utc)
        await self.db.flush()
        return msg

    async def add_system_message(
        self,
        thread: Thread,
        content: str,
        routing_plan_id: uuid.UUID | None = None,
    ) -> Message:
        msg = Message(
            thread_id=thread.id,
            message_type=MessageType.system_message,
            sender_type=SenderType.system,
            content=content,
            routing_plan_id=routing_plan_id,
        )
        self.db.add(msg)
        await self.db.flush()
        return msg

    async def add_agent_response(
        self,
        thread_id: uuid.UUID,
        correlation_id: uuid.UUID,
        content: str | None = None,
        structured_json: dict | None = None,
        tool_usage: dict | None = None,
        skill_name: str | None = None,
    ) -> Message:
        """Record an agent response received from the bridge skill."""
        msg_type = MessageType.structured_card_message if structured_json else MessageType.agent_message
        msg = Message(
            thread_id=thread_id,
            message_type=msg_type,
            sender_type=SenderType.agent,
            content=content,
            structured_json=structured_json,
            correlation_id=correlation_id,
            tool_usage=tool_usage,
        )
        self.db.add(msg)

        # Update thread timestamp
        result = await self.db.execute(select(Thread).where(Thread.id == thread_id))
        thread = result.scalar_one_or_none()
        if thread:
            thread.updated_at = datetime.now(timezone.utc)

        await self.db.flush()
        return msg

    async def get_last_messages(
        self, thread_id: uuid.UUID, limit: int = 10
    ) -> list[Message]:
        """Get the most recent messages in a thread for context."""
        result = await self.db.execute(
            select(Message)
            .where(Message.thread_id == thread_id)
            .order_by(Message.created_at.desc())
            .limit(limit)
        )
        messages = list(result.scalars().all())
        messages.reverse()  # Chronological order
        return messages

    # ------------------------------------------------------------------
    # Routing Plans
    # ------------------------------------------------------------------

    async def save_routing_plan(self, plan: RoutingPlan) -> RoutingPlan:
        self.db.add(plan)
        await self.db.flush()
        return plan
