from __future__ import annotations

import os
import tempfile
import uuid
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


def test_person_role_assignment_supports_optional_org_and_service_scope() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import Organization, Person, PersonRoleAssignment, Role, ServiceDefinition

    organization_id = uuid.UUID("018f2f22-0000-7000-8000-000000000801")

    with dbmod.SessionLocal() as db:
        assignee = Person(primary_person_type="staff", status="active")
        assigner = Person(primary_person_type="staff", status="active")
        role = Role(
            code="dispatcher",
            role_group="staff",
            name="Dispatcher",
            description="Operations dispatcher",
            is_system=True,
        )
        service = ServiceDefinition(
            id="pharmacy",
            title="Pharmacy",
            subtitle="Order medicine",
            icon="pill",
            status="active",
        )
        organization = Organization(
            id=organization_id,
            name="Daryeel Ops",
            status="active",
        )

        db.add_all([assignee, assigner, role, service, organization])
        db.flush()

        assignment = PersonRoleAssignment(
            person_id=assignee.id,
            role_id=role.id,
            organization_id=organization.id,
            service_id=service.id,
            assigned_by_person_id=assigner.id,
            status="active",
        )
        db.add(assignment)
        db.commit()

        saved = db.scalar(
            select(PersonRoleAssignment).where(PersonRoleAssignment.id == assignment.id)
        )
        assert saved is not None
        assert saved.person_id == assignee.id
        assert saved.role_id == role.id
        assert saved.organization_id == organization.id
        assert saved.service_id == "pharmacy"
        assert saved.assigned_by_person_id == assigner.id
        assert saved.status == "active"


def test_roles_enforce_unique_code() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import Role

    with dbmod.SessionLocal() as db:
        db.add(Role(code="customer", role_group="customer", name="Customer", is_system=True))
        db.commit()

        db.add(Role(code="customer", role_group="customer", name="Duplicate Customer"))
        with pytest.raises(IntegrityError):
            db.commit()
