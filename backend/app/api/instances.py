import secrets
import uuid
from hashlib import sha256

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.instance import Instance, IntegrationToken
from app.models.user import User
from app.schemas.instance import (
    InstanceCreate,
    InstanceResponse,
    InstanceWithSecret,
    IntegrationTokenCreate,
    IntegrationTokenResponse,
)

router = APIRouter()


@router.post("", response_model=InstanceWithSecret, status_code=status.HTTP_201_CREATED)
async def create_instance(
    body: InstanceCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    shared_secret = secrets.token_urlsafe(32)
    instance = Instance(user_id=user.id, name=body.name, shared_secret=shared_secret)
    db.add(instance)
    await db.flush()
    await db.refresh(instance)
    return InstanceWithSecret.model_validate(instance)


@router.get("", response_model=list[InstanceResponse])
async def list_instances(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Instance).where(Instance.user_id == user.id).order_by(Instance.created_at.desc())
    )
    return result.scalars().all()


@router.get("/{instance_id}", response_model=InstanceResponse)
async def get_instance(
    instance_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    instance = await _get_user_instance(instance_id, user.id, db)
    return instance


@router.delete("/{instance_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_instance(
    instance_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    instance = await _get_user_instance(instance_id, user.id, db)
    await db.delete(instance)


# --- Integration Tokens ---


@router.post(
    "/{instance_id}/tokens",
    response_model=IntegrationTokenResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_integration_token(
    instance_id: uuid.UUID,
    body: IntegrationTokenCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _get_user_instance(instance_id, user.id, db)

    raw_token = secrets.token_urlsafe(48)
    token_hash = sha256(raw_token.encode()).hexdigest()

    token = IntegrationToken(
        instance_id=instance_id,
        token_hash=token_hash,
        label=body.label,
        scope=body.scope,
    )
    db.add(token)
    await db.flush()
    await db.refresh(token)

    resp = IntegrationTokenResponse.model_validate(token)
    resp.raw_token = raw_token
    return resp


@router.get("/{instance_id}/tokens", response_model=list[IntegrationTokenResponse])
async def list_integration_tokens(
    instance_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _get_user_instance(instance_id, user.id, db)
    result = await db.execute(
        select(IntegrationToken)
        .where(IntegrationToken.instance_id == instance_id)
        .order_by(IntegrationToken.created_at.desc())
    )
    return result.scalars().all()


@router.post("/{instance_id}/tokens/{token_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_integration_token(
    instance_id: uuid.UUID,
    token_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _get_user_instance(instance_id, user.id, db)
    result = await db.execute(
        select(IntegrationToken).where(
            IntegrationToken.id == token_id,
            IntegrationToken.instance_id == instance_id,
        )
    )
    token = result.scalar_one_or_none()
    if not token:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Token not found")

    token.is_revoked = True
    from datetime import datetime, timezone

    token.revoked_at = datetime.now(timezone.utc)


async def _get_user_instance(
    instance_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession
) -> Instance:
    result = await db.execute(
        select(Instance).where(Instance.id == instance_id, Instance.user_id == user_id)
    )
    instance = result.scalar_one_or_none()
    if not instance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instance not found")
    return instance
