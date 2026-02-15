"""Command channel — queue commands for bridge skill polling and acknowledgment."""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Path, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.command import Command, CommandStatus, CommandType
from app.models.instance import Instance
from app.models.user import User
from app.schemas.command import (
    CommandAcknowledge,
    CommandCreate,
    CommandResponse,
    PendingCommandsResponse,
)
from app.security.hmac_verify import verify_hmac

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
# iOS / Dashboard: send commands
# ===================================================================

@router.post(
    "/instances/{instance_id}/commands",
    response_model=CommandResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_command(
    body: CommandCreate,
    instance_id: uuid.UUID = Path(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Queue a command for the bridge skill to pick up."""
    await _get_user_instance(instance_id, user, db)

    command = Command(
        instance_id=instance_id,
        user_id=user.id,
        command_type=body.command_type,
        payload=body.payload,
        reason=body.reason,
    )
    db.add(command)
    await db.flush()
    await db.refresh(command)
    return command


@router.get(
    "/instances/{instance_id}/commands",
    response_model=list[CommandResponse],
)
async def list_commands(
    instance_id: uuid.UUID = Path(...),
    command_status: CommandStatus | None = Query(None, alias="status"),
    limit: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List commands for an instance (for dashboard/history view)."""
    await _get_user_instance(instance_id, user, db)

    query = select(Command).where(Command.instance_id == instance_id)
    if command_status:
        query = query.where(Command.status == command_status)
    query = query.order_by(Command.created_at.desc()).limit(limit)

    result = await db.execute(query)
    return list(result.scalars().all())


# ===================================================================
# Bridge skill: poll for pending commands (HMAC-authenticated)
# ===================================================================

@router.get(
    "/instances/{instance_id}/commands/pending",
    response_model=PendingCommandsResponse,
)
async def poll_pending_commands(
    instance_id: uuid.UUID = Path(...),
    x_signature: str = Header(...),
    x_timestamp: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Bridge skill polls this endpoint for pending commands.

    Authenticated via HMAC (same as ingest) rather than JWT,
    since the bridge skill uses instance_secret, not user tokens.
    """
    # Look up instance
    result = await db.execute(select(Instance).where(Instance.id == instance_id))
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")

    # Verify HMAC — payload is empty string for GET requests
    if not verify_hmac(instance.shared_secret, x_timestamp, "", x_signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature")

    # Fetch pending commands
    cmd_result = await db.execute(
        select(Command)
        .where(Command.instance_id == instance_id, Command.status == CommandStatus.pending)
        .order_by(Command.created_at.asc())
        .limit(10)
    )
    commands = list(cmd_result.scalars().all())

    return PendingCommandsResponse(
        commands=[CommandResponse.model_validate(c) for c in commands],
    )


@router.post(
    "/instances/{instance_id}/commands/{command_id}/ack",
    response_model=CommandResponse,
)
async def acknowledge_command(
    body: CommandAcknowledge,
    instance_id: uuid.UUID = Path(...),
    command_id: uuid.UUID = Path(...),
    x_signature: str = Header(...),
    x_timestamp: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Bridge skill acknowledges a command after processing it.

    HMAC-authenticated (same as poll).
    """
    # Look up instance
    result = await db.execute(select(Instance).where(Instance.id == instance_id))
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")

    # Verify HMAC — payload is the JSON body
    # For simplicity in MVP, we verify with empty payload for ack too
    if not verify_hmac(instance.shared_secret, x_timestamp, "", x_signature):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid HMAC signature")

    # Fetch command
    cmd_result = await db.execute(
        select(Command).where(
            Command.id == command_id,
            Command.instance_id == instance_id,
        )
    )
    command = cmd_result.scalar_one_or_none()
    if not command:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Command not found")

    now = datetime.now(timezone.utc)

    if body.status == CommandStatus.acknowledged:
        command.status = CommandStatus.acknowledged
        command.acknowledged_at = now
    elif body.status == CommandStatus.completed:
        command.status = CommandStatus.completed
        command.completed_at = now
        if not command.acknowledged_at:
            command.acknowledged_at = now
    elif body.status == CommandStatus.failed:
        command.status = CommandStatus.failed
        command.completed_at = now

    if body.result_message:
        command.result_message = body.result_message

    await db.flush()
    await db.refresh(command)
    return command
