from __future__ import annotations

import os
import tempfile
import uuid
from pathlib import Path

import pytest

from app.events import record_request_event
from app.events.types import REQUEST_STATUS_CHANGED


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


def test_record_request_event_updates_state_and_related_refs() -> None:
    _init_sqlite_db()

    import app.db as dbmod
    from sqlalchemy import select

    from app.models import RequestEvent, ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
        )
        db.add(request)
        db.flush()

        record_request_event(
            db,
            request=request,
            event_type=REQUEST_STATUS_CHANGED,
            actor_type="system",
            actor_id=None,
            to_status="accepted",
            sub_status="preparing",
            related_entity_type="assignment",
            related_entity_id="assign-1",
            metadata={"reason": "accepted for testing"},
        )
        db.commit()

        db.refresh(request)
        event = db.scalar(select(RequestEvent).where(RequestEvent.request_id == request.id))

        assert request.status == "accepted"
        assert request.sub_status == "preparing"
        assert event is not None
        assert isinstance(event.id, uuid.UUID)
        assert event.id.version == 7
        assert event.type == REQUEST_STATUS_CHANGED
        assert event.from_status == "created"
        assert event.to_status == "accepted"
        assert event.related_entity_type == "assignment"
        assert event.related_entity_id == "assign-1"
        assert event.metadata_json == {"reason": "accepted for testing"}


def test_record_request_event_rejects_unknown_event_type() -> None:
    _init_sqlite_db()

    import app.db as dbmod

    from app.models import ServiceRequest

    with dbmod.SessionLocal() as db:
        request = ServiceRequest(
            service_id="pharmacy",
            customer_user_id=1,
            status="created",
        )
        db.add(request)
        db.flush()

        with pytest.raises(ValueError, match="Unsupported request event type"):
            record_request_event(
                db,
                request=request,
                event_type="unknown_event",
                actor_type="system",
                actor_id=None,
            )
