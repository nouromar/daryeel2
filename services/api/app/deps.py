from __future__ import annotations

from dataclasses import dataclass

from fastapi import Depends
from fastapi import Header
from fastapi import HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.auth import AccessTokenPayload, verify_bearer_token
from app.db import get_db
from app.models import Permission, PersonRoleAssignment, RolePermission, User
from app.settings import load_settings

_settings = load_settings()


def require_access_token_payload(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(get_db),
) -> AccessTokenPayload:
    if authorization is None:
        raise HTTPException(status_code=401, detail="Missing Authorization")
    return verify_bearer_token(
        secret=_settings.auth_secret,
        authorization_header=authorization,
        db=db,
    )


@dataclass(frozen=True)
class AuthorizedActor:
    token_payload: AccessTokenPayload
    user_id: int


def require_permission(permission_code: str, *, service_id: str | None = None):
    def dependency(
        token_payload: AccessTokenPayload = Depends(require_access_token_payload),
        db: Session = Depends(get_db),
    ) -> AuthorizedActor:
        try:
            user_id = int(token_payload.sub)
        except ValueError as exc:
            raise HTTPException(status_code=401, detail="Invalid token subject") from exc

        user = db.scalar(select(User).where(User.id == user_id))
        if user is None:
            raise HTTPException(status_code=401, detail="Unknown user")
        if user.person_id is None:
            raise HTTPException(status_code=403, detail=f"Missing permission: {permission_code}")

        conditions = [
            Permission.code == permission_code,
            PersonRoleAssignment.person_id == user.person_id,
            PersonRoleAssignment.status == "active",
            or_(PersonRoleAssignment.starts_at.is_(None), PersonRoleAssignment.starts_at <= func.now()),
            or_(PersonRoleAssignment.ends_at.is_(None), PersonRoleAssignment.ends_at > func.now()),
        ]
        if service_id is not None:
            conditions.append(
                or_(
                    PersonRoleAssignment.service_id.is_(None),
                    PersonRoleAssignment.service_id == service_id,
                )
            )

        permission = db.scalar(
            select(Permission.id)
            .join(RolePermission, RolePermission.permission_id == Permission.id)
            .join(PersonRoleAssignment, PersonRoleAssignment.role_id == RolePermission.role_id)
            .where(*conditions)
            .limit(1)
        )
        if permission is None:
            raise HTTPException(status_code=403, detail=f"Missing permission: {permission_code}")

        return AuthorizedActor(token_payload=token_payload, user_id=user_id)

    return dependency
