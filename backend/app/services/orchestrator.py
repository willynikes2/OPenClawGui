"""OrchestratorService — executes routing plans by creating commands for the instance."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.command import Command, CommandStatus, CommandType
from app.models.routing_plan import RoutingIntent, RoutingPlan
from app.services.router import RoutingResult


class OrchestratorService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def execute_routing_plan(
        self,
        plan: RoutingPlan,
        user_id: uuid.UUID,
        user_message: str,
    ) -> list[Command]:
        """Create commands based on the routing plan and enqueue them for the instance.

        Returns the list of created commands.
        """
        commands: list[Command] = []
        correlation_id = uuid.uuid4()

        for target in (plan.targets or []):
            cmd = self._build_command(
                plan=plan,
                target=target,
                user_id=user_id,
                user_message=user_message,
                correlation_id=correlation_id,
            )
            if cmd:
                self.db.add(cmd)
                commands.append(cmd)

        await self.db.flush()
        return commands

    def _build_command(
        self,
        plan: RoutingPlan,
        target: dict,
        user_id: uuid.UUID,
        user_message: str,
        correlation_id: uuid.UUID,
    ) -> Command | None:
        """Build a Command from a routing target."""
        target_type = target.get("type", "")
        target_name = target.get("name", "default")
        target_params = target.get("params", {})

        if plan.intent == RoutingIntent.control_action:
            # Map to existing control command types
            cmd_type = self._resolve_control_command(user_message)
            return Command(
                instance_id=plan.instance_id,
                user_id=user_id,
                command_type=cmd_type,
                payload={"source": "chat", "message": user_message},
                correlation_id=correlation_id,
                reason="chat_request",
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=5),
            )

        if target_type == "skill":
            return Command(
                instance_id=plan.instance_id,
                user_id=user_id,
                command_type=CommandType.run_skill,
                payload={
                    "skill_name": target_name,
                    "message": user_message,
                    "thread_id": str(plan.thread_id),
                    **target_params,
                },
                correlation_id=correlation_id,
                reason="chat_request",
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
            )

        # Default: send as chat_message to agent
        return Command(
            instance_id=plan.instance_id,
            user_id=user_id,
            command_type=CommandType.chat_message,
            payload={
                "agent_name": target_name,
                "message": user_message,
                "thread_id": str(plan.thread_id),
            },
            correlation_id=correlation_id,
            reason="chat_request",
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )

    @staticmethod
    def _resolve_control_command(message: str) -> CommandType:
        """Determine which control command to issue from the user's message."""
        lower = message.lower()
        if "kill" in lower or "emergency" in lower:
            return CommandType.pause  # Kill switch handled at higher level
        if "resume" in lower or "unpause" in lower:
            return CommandType.resume
        return CommandType.pause
