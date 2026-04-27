from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError


def _init_sqlite_db() -> None:
    tmpdir = Path(tempfile.mkdtemp(prefix="daryeel_api_test_"))
    db_path = tmpdir / "test.db"
    url = f"sqlite+pysqlite:///{db_path}"

    os.environ["DATABASE_URL"] = url
    os.environ["API_DATABASE_URL"] = url

    import app.db as dbmod

    dbmod._engine = None

    engine = dbmod.get_engine()

    from app.models import Base

    Base.metadata.create_all(bind=engine)


def test_permissions_enforce_unique_code() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import Permission

    with dbmod.SessionLocal() as db:
        db.add(Permission(code="pharmacy.manage_orders", name="Manage orders", is_system=True))
        db.commit()

        db.add(Permission(code="pharmacy.manage_orders", name="Duplicate"))
        with pytest.raises(IntegrityError):
            db.commit()


def test_role_permissions_link_roles_to_permissions() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import Permission, Role, RolePermission

    with dbmod.SessionLocal() as db:
        role = Role(code="dispatcher", role_group="staff", name="Dispatcher", is_system=True)
        permission = Permission(
            code="pharmacy.manage_orders",
            name="Manage orders",
            is_system=True,
        )
        db.add_all([role, permission])
        db.flush()

        db.add(RolePermission(role_id=role.id, permission_id=permission.id))
        db.commit()

        saved = db.scalar(
            select(RolePermission).where(
                RolePermission.role_id == role.id,
                RolePermission.permission_id == permission.id,
            )
        )
        assert saved is not None
