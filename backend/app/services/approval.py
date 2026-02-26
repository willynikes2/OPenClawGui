"""ApprovalService — manages human-in-the-loop approval requests and decisions."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.approval import (
    ApprovalAction,
    ApprovalRequest,
    ApprovalRiskLevel,
    ApprovalStatus,
)
from app.models.command import Command, CommandType
from app.models.message import Message, MessageType, SenderType
from app.models.thread import Thread


class ApprovalService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # ------------------------------------------------------------------
    # Create
    # ------------------------------------------------------------------

    async def create_approval(
        self,
        *,
        instance_id: uuid.UUID,
        skill_name: str,
        action: str,
        summary: str,
        risk_level: str,
        evidence: dict | None = None,
        thread_id: uuid.UUID | None = None,
        expires_in_seconds: int = 300,
    ) -> ApprovalRequest:
        """Create an approval request and optionally inject it into a chat thread."""
        approval = ApprovalRequest(
            instance_id=instance_id,
            thread_id=thread_id,
            skill_name=skill_name,
            action=ApprovalAction(action),
            summary=summary,
            risk_level=ApprovalRiskLevel(risk_level),
            evidence=evidence,
            options=["allow_once", "allow_always", "deny"],
            status=ApprovalStatus.pending,
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=expires_in_seconds),
        )
        self.db.add(approval)
        await self.db.flush()

        # If a thread_id is provided, inject an approval_request message
        if thread_id:
            msg = Message(
                thread_id=thread_id,
                message_type=MessageType.approval_request,
                sender_type=SenderType.system,
                content=summary,
                structured_json={
                    "approval_id": str(approval.id),
                    "skill_name": skill_name,
                    "action": action,
                    "risk_level": risk_level,
                    "options": ["allow_once", "allow_always", "deny"],
                    "evidence": evidence or {},
                    "expires_at": approval.expires_at.isoformat(),
                },
            )
            self.db.add(msg)

            # Update thread timestamp
            result = await self.db.execute(select(Thread).where(Thread.id == thread_id))
            thread = result.scalar_one_or_none()
            if thread:
                thread.updated_at = datetime.now(timezone.utc)

            await self.db.flush()

        return approval

    # ------------------------------------------------------------------
    # Decide
    # ------------------------------------------------------------------

    async def decide_approval(
        self,
        *,
        approval_id: uuid.UUID,
        user_id: uuid.UUID,
        decision: str,
    ) -> ApprovalRequest | None:
        """Record a user's decision on an approval request.

        Creates an approve_action command for the bridge skill to consume.
        Returns None if approval not found or already decided.
        """
        result = await self.db.execute(
            select(ApprovalRequest).where(ApprovalRequest.id == approval_id)
        )
        approval = result.scalar_one_or_none()
        if not approval:
            return None

        # Cannot decide on non-pending approvals
        if approval.status != ApprovalStatus.pending:
            return None

        # Check expiry
        if datetime.now(timezone.utc) > approval.expires_at:
            approval.status = ApprovalStatus.expired
            await self.db.flush()
            return None

        # Record decision
        now = datetime.now(timezone.utc)
        approval.status = ApprovalStatus.approved if decision != "deny" else ApprovalStatus.denied
        approval.decided_by = user_id
        approval.decided_at = now
        approval.decision = decision

        # Create approve_action command for the bridge skill
        cmd = Command(
            instance_id=approval.instance_id,
            user_id=user_id,
            command_type=CommandType.approve_action,
            payload={
                "approval_id": str(approval.id),
                "skill_name": approval.skill_name,
                "action": approval.action.value,
                "decision": decision,
                "decided_by": str(user_id),
                "decided_at": now.isoformat(),
            },
            correlation_id=approval.id,
            reason="approval_decision",
            expires_at=now + timedelta(minutes=10),
        )
        self.db.add(cmd)

        # Add system message to thread if linked
        if approval.thread_id:
            decision_label = {
                "allow_once": "Allowed (once)",
                "allow_always": "Always allowed",
                "deny": "Denied",
            }.get(decision, decision)

            msg = Message(
                thread_id=approval.thread_id,
                message_type=MessageType.system_message,
                sender_type=SenderType.system,
                content=f"Approval for '{approval.skill_name}' {approval.action.value}: {decision_label}",
            )
            self.db.add(msg)

        await self.db.flush()
        return approval

    # ------------------------------------------------------------------
    # Query
    # ------------------------------------------------------------------

    async def list_approvals(
        self,
        instance_id: uuid.UUID,
        status: str | None = None,
        limit: int = 20,
    ) -> list[ApprovalRequest]:
        """List approval requests for an instance, newest first."""
        stmt = select(ApprovalRequest).where(ApprovalRequest.instance_id == instance_id)
        if status:
            stmt = stmt.where(ApprovalRequest.status == ApprovalStatus(status))
        stmt = stmt.order_by(ApprovalRequest.created_at.desc()).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_approval(self, approval_id: uuid.UUID) -> ApprovalRequest | None:
        result = await self.db.execute(
            select(ApprovalRequest).where(ApprovalRequest.id == approval_id)
        )
        return result.scalar_one_or_none()

    async def expire_stale_approvals(self, instance_id: uuid.UUID) -> int:
        """Mark pending approvals past their expiry as expired. Returns count updated."""
        now = datetime.now(timezone.utc)
        result = await self.db.execute(
            update(ApprovalRequest)
            .where(
                ApprovalRequest.instance_id == instance_id,
                ApprovalRequest.status == ApprovalStatus.pending,
                ApprovalRequest.expires_at < now,
            )
            .values(status=ApprovalStatus.expired)
        )
        await self.db.flush()
        return result.rowcount
