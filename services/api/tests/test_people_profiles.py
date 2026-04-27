from __future__ import annotations

import os
import tempfile
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


def test_dev_otp_verify_creates_customer_person_and_profile() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    start = client.post(
        "/dev/auth/otp/start",
        json={"phone": "+252610000123"},
    )
    assert start.status_code == 200

    verify = client.post(
        "/dev/auth/otp/verify",
        json={"phone": "+252610000123", "otp": "123456"},
    )

    assert verify.status_code == 200
    payload = verify.json()
    assert payload["isNewUser"] is True

    import app.db as dbmod
    from app.models import CustomerProfile, Person, User

    with dbmod.SessionLocal() as db:
        user = db.scalar(select(User).where(User.phone == "+252610000123"))
        assert user is not None
        assert user.person_id is not None

        person = db.get(Person, user.person_id)
        assert person is not None
        assert person.primary_person_type == "customer"
        assert person.status == "active"
        assert person.phone_e164 == "+252610000123"

        profile = db.get(CustomerProfile, user.person_id)
        assert profile is not None
        assert profile.marketing_consent is False

    me = client.get(
        "/v1/me",
        headers={"Authorization": f"Bearer {payload['accessToken']}"},
    )
    assert me.status_code == 200
    assert me.json()["user"] == {
        "id": str(payload["user"]["id"]),
        "phone": "+252610000123",
    }


def test_dev_otp_verify_backfills_missing_person_link_for_existing_user() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import CustomerProfile, User

    with dbmod.SessionLocal() as db:
        user = User(phone="+252610000124")
        db.add(user)
        db.commit()
        db.refresh(user)
        assert user.person_id is None

    client = TestClient(app)
    start = client.post(
        "/dev/auth/otp/start",
        json={"phone": "+252610000124"},
    )
    assert start.status_code == 200

    verify = client.post(
        "/dev/auth/otp/verify",
        json={"phone": "+252610000124", "otp": "654321"},
    )

    assert verify.status_code == 200
    assert verify.json()["isNewUser"] is False

    with dbmod.SessionLocal() as db:
        user = db.scalar(select(User).where(User.phone == "+252610000124"))
        assert user is not None
        assert user.person_id is not None
        assert db.get(CustomerProfile, user.person_id) is not None
