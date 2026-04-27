from __future__ import annotations

import os
import tempfile
import uuid
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.main import app


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


def test_dev_otp_flow_creates_challenge_identity_factor_and_session() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    start = client.post("/dev/auth/otp/start", json={"phone": "+252610000200"})
    assert start.status_code == 200
    start_payload = start.json()
    assert start_payload["ok"] is True
    assert start_payload["phone"] == "+252610000200"
    assert isinstance(start_payload["challengeId"], str)

    verify = client.post(
        "/dev/auth/otp/verify",
        json={"phone": "+252610000200", "otp": "111111"},
    )
    assert verify.status_code == 200
    verify_payload = verify.json()
    assert verify_payload["isNewUser"] is True

    import app.db as dbmod
    from app.models import AuthChallenge, AuthFactor, AuthIdentity, AuthSession, Person, User

    with dbmod.SessionLocal() as db:
        user = db.scalar(select(User).where(User.phone == "+252610000200"))
        assert user is not None

        person = db.get(Person, user.person_id)
        assert person is not None
        assert person.status == "active"

        identity = db.scalar(
            select(AuthIdentity).where(AuthIdentity.identity_value_normalized == "+252610000200")
        )
        assert identity is not None
        assert identity.is_verified is True

        factor = db.scalar(
            select(AuthFactor).where(AuthFactor.identity_id == identity.id)
        )
        assert factor is not None
        assert factor.is_verified is True

        challenge = db.get(AuthChallenge, uuid.UUID(start_payload["challengeId"]))
        assert challenge is not None
        assert challenge.status == "completed"
        assert challenge.challenge_type == "sign_up"

        session = db.scalar(
            select(AuthSession).where(AuthSession.person_id == person.id)
        )
        assert session is not None
        assert session.revoked_at is None

    me = client.get(
        "/v1/me",
        headers={"Authorization": f"Bearer {verify_payload['accessToken']}"},
    )
    assert me.status_code == 200
    assert me.json()["user"]["phone"] == "+252610000200"


def test_dev_otp_session_revocation_invalidates_me() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    client.post("/dev/auth/otp/start", json={"phone": "+252610000201"})
    verify = client.post(
        "/dev/auth/otp/verify",
        json={"phone": "+252610000201", "otp": "222222"},
    )
    assert verify.status_code == 200
    token = verify.json()["accessToken"]

    import app.db as dbmod
    from app.models import AuthSession
    from app.main import _now_utc

    with dbmod.SessionLocal() as db:
        session = db.scalar(select(AuthSession))
        assert session is not None
        session.revoked_at = _now_utc()
        session.revoke_reason = "test"
        db.commit()

    me = client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 401
