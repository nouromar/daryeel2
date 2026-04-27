from __future__ import annotations

import os
import tempfile
import uuid
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import select


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


def test_organization_membership_persists_person_org_link() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import Organization, OrganizationMembership, Person

    organization_id = uuid.UUID("018f2f22-0000-7000-8000-000000000901")
    starts_at = datetime(2026, 4, 27, 12, 0, tzinfo=UTC)

    with dbmod.SessionLocal() as db:
        person = Person(primary_person_type="staff", status="active")
        organization = Organization(
            id=organization_id,
            name="Daryeel Internal Ops",
            status="active",
        )
        db.add_all([person, organization])
        db.flush()

        membership = OrganizationMembership(
            person_id=person.id,
            organization_id=organization.id,
            membership_type="manager",
            title="Operations Lead",
            status="active",
            starts_at=starts_at,
        )
        db.add(membership)
        db.commit()

        saved = db.scalar(
            select(OrganizationMembership).where(OrganizationMembership.id == membership.id)
        )
        assert saved is not None
        assert saved.person_id == person.id
        assert saved.organization_id == organization.id
        assert saved.membership_type == "manager"
        assert saved.title == "Operations Lead"
        assert saved.status == "active"
        assert saved.starts_at == starts_at.replace(tzinfo=None)


def test_organization_memberships_support_multiple_membership_types() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import Organization, OrganizationMembership, Person

    with dbmod.SessionLocal() as db:
        person = Person(primary_person_type="provider", status="active")
        organization = Organization(
            id=uuid.UUID("018f2f22-0000-7000-8000-000000000902"),
            name="Partner Clinic",
            status="active",
        )
        db.add_all([person, organization])
        db.flush()

        db.add_all(
            [
                OrganizationMembership(
                    person_id=person.id,
                    organization_id=organization.id,
                    membership_type="provider",
                    status="active",
                ),
                OrganizationMembership(
                    person_id=person.id,
                    organization_id=organization.id,
                    membership_type="manager",
                    status="pending",
                ),
            ]
        )
        db.commit()

        memberships = db.scalars(
            select(OrganizationMembership).where(
                OrganizationMembership.person_id == person.id,
                OrganizationMembership.organization_id == organization.id,
            )
        ).all()
        assert len(memberships) == 2
        assert {membership.membership_type for membership in memberships} == {
            "provider",
            "manager",
        }
        assert {membership.status for membership in memberships} == {
            "active",
            "pending",
        }
