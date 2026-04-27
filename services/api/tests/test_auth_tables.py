from __future__ import annotations

import os
import tempfile
from datetime import UTC, datetime, timedelta
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


def test_auth_tables_persist_full_foundation_rows() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import AuthChallenge, AuthFactor, AuthIdentity, AuthPolicy, AuthSession, Person

    now = datetime.now(UTC)

    with dbmod.SessionLocal() as db:
        person = Person(
            primary_person_type="customer",
            status="active",
            phone_e164="+252610001111",
        )
        db.add(person)
        db.flush()

        identity = AuthIdentity(
            person_id=person.id,
            identity_type="phone",
            identity_value="+252610001111",
            identity_value_normalized="+252610001111",
            is_primary=True,
            is_verified=True,
            verified_at=now,
            status="active",
        )
        db.add(identity)
        db.flush()

        factor = AuthFactor(
            person_id=person.id,
            identity_id=identity.id,
            factor_type="phone_otp",
            display_label="Primary phone OTP",
            is_primary=True,
            is_verified=True,
            verified_at=now,
            status="active",
        )
        challenge = AuthChallenge(
            person_id=person.id,
            identity_id=identity.id,
            factor_type="phone_otp",
            challenge_type="sign_in",
            delivery_channel="sms",
            code_hash="hashed-otp",
            attempt_count=1,
            max_attempts=5,
            expires_at=now + timedelta(minutes=5),
            status="pending",
            ip_address="127.0.0.1",
            user_agent="pytest",
        )
        session = AuthSession(
            person_id=person.id,
            session_token_hash="session-hash-1",
            refresh_token_hash="refresh-hash-1",
            auth_strength="single_factor",
            issued_at=now,
            expires_at=now + timedelta(days=30),
            ip_address="127.0.0.1",
            user_agent="pytest",
            device_id="simulator",
        )
        policy = AuthPolicy(
            subject_type="person_type",
            subject_value="customer",
            allowed_factor_types=["phone_otp"],
            min_factor_count=1,
            require_verified_identity=True,
            require_vpn=False,
            session_ttl_minutes=43200,
            status="active",
        )

        db.add_all([factor, challenge, session, policy])
        db.commit()

        saved_identity = db.scalar(
            select(AuthIdentity).where(AuthIdentity.identity_value_normalized == "+252610001111")
        )
        saved_policy = db.scalar(
            select(AuthPolicy).where(AuthPolicy.subject_value == "customer")
        )

        assert saved_identity is not None
        assert saved_identity.is_primary is True
        assert saved_identity.is_verified is True
        assert saved_policy is not None
        assert saved_policy.allowed_factor_types == ["phone_otp"]


def test_auth_sessions_enforce_unique_session_token_hash() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import AuthSession, Person

    now = datetime.now(UTC)

    with dbmod.SessionLocal() as db:
        person = Person(primary_person_type="customer", status="active")
        db.add(person)
        db.flush()

        db.add(
            AuthSession(
                person_id=person.id,
                session_token_hash="duplicate-session-hash",
                auth_strength="single_factor",
                issued_at=now,
                expires_at=now + timedelta(days=1),
            )
        )
        db.commit()

        db.add(
            AuthSession(
                person_id=person.id,
                session_token_hash="duplicate-session-hash",
                auth_strength="single_factor",
                issued_at=now,
                expires_at=now + timedelta(days=1),
            )
        )
        with pytest.raises(IntegrityError):
            db.commit()
