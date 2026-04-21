from __future__ import annotations

import os
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

from app.auth import create_access_token
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

    from app.models import Base, User

    Base.metadata.create_all(bind=engine)

    with dbmod.SessionLocal() as db:
        user = User(phone="+252610000001")
        db.add(user)
        db.commit()
        db.refresh(user)


def _auth_header_for_user_id(user_id: int) -> dict[str, str]:
    token = create_access_token(
        secret="dev-insecure-secret",
        user_id=user_id,
        phone="+252610000001",
        ttl_seconds=60,
    )
    return {"Authorization": f"Bearer {token}"}


def test_notifications_home_summary_prioritizes_action_required() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import ServiceRequest

    with dbmod.SessionLocal() as db:
        # One request that needs user action.
        r1 = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="awaiting_info",
            payload_json={"cart_lines": [], "prescription_upload_ids": []},
        )

        # One normal active request.
        r2 = ServiceRequest(
            service_id="home_visit",
            customer_user_id=1,
            status="assigned",
            payload_json=None,
        )

        db.add_all([r1, r2])
        db.commit()
        db.refresh(r1)

    client = TestClient(app)
    res = client.get(
        "/v1/notifications/home-summary",
        headers=_auth_header_for_user_id(1),
    )
    assert res.status_code == 200

    data = res.json()
    assert data["activeCount"] == 2
    assert data["moreCount"] == 1
    assert data["primary"]["entity"]["id"] == str(r1.id)
    assert data["primary"]["kind"] == "action_required"
    assert data["moreByService"]["home_visit"] == 1


def test_notifications_list_shape() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from app.models import ServiceRequest

    with dbmod.SessionLocal() as db:
        r1 = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="awaiting_info",
            payload_json={"cart_lines": [], "prescription_upload_ids": []},
        )
        db.add(r1)
        db.commit()
        db.refresh(r1)

    client = TestClient(app)
    res = client.get("/v1/notifications", headers=_auth_header_for_user_id(1))
    assert res.status_code == 200

    data = res.json()
    assert data["has_notifications"] is True
    assert isinstance(data["items"], list)
    assert len(data["items"]) == 1

    item = data["items"][0]
    assert item["entity"]["kind"] == "request"
    assert item["entity"]["id"] == str(r1.id)
    assert item["service"] == "pharmacy"
    assert "title" in item
    assert "subtitle" in item
