from __future__ import annotations

import os
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

from app.auth import create_access_token
from app.main import app


def _init_sqlite_db() -> None:
    # Use a file-backed sqlite DB so the API's session-per-request sees the same DB.
    tmpdir = Path(tempfile.mkdtemp(prefix="daryeel_api_test_"))
    db_path = tmpdir / "test.db"
    url = f"sqlite+pysqlite:///{db_path}"

    os.environ["DATABASE_URL"] = url
    os.environ["API_DATABASE_URL"] = url

    # Reset cached engine between tests.
    import app.db as dbmod

    dbmod._engine = None

    engine = dbmod.get_engine()

    from app.models import Base, User

    Base.metadata.create_all(bind=engine)

    # Seed a user.
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


def test_upload_prescription_creates_record() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    res = client.post(
        "/v1/pharmacy/prescriptions/upload",
        headers=_auth_header_for_user_id(1),
        files={"file": ("rx.jpg", b"fake-image-bytes", "image/jpeg")},
    )

    assert res.status_code == 200
    payload = res.json()
    assert payload.get("ok") is True
    upload_id = payload.get("id")
    assert isinstance(upload_id, str)
    assert len(upload_id) > 10

    import app.db as dbmod

    from sqlalchemy import select

    from app.models import PrescriptionUpload

    with dbmod.SessionLocal() as db:
        rec = db.scalar(
            select(PrescriptionUpload).where(PrescriptionUpload.id == upload_id)
        )
        assert rec is not None
        assert rec.service_id == "pharmacy"
        assert rec.customer_user_id == 1
        assert rec.filename == "rx.jpg"
        assert rec.content_type == "image/jpeg"
