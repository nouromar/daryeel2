from __future__ import annotations

import os
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient

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


def test_service_definitions_list_returns_seeded_items() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    res = client.get("/v1/service-definitions")

    assert res.status_code == 200
    payload = res.json()
    assert [item["id"] for item in payload["items"]] == [
        "ambulance",
        "home_visit",
        "pharmacy",
    ]
    assert payload["items"][0]["route"]["value"]["screenId"] == "customer_request_ambulance"
    assert payload["items"][2]["route"]["value"]["screenId"] == "pharmacy_shop"
    assert payload["items"][2]["route"]["value"]["chromePreset"] == "pharmacy_cart_badge"
    assert payload["items"][2]["detailRoute"]["value"]["params"]["id"] == "pharmacy"


def test_service_definitions_support_search_and_paging() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    search = client.get("/v1/service-definitions", params={"q": "doctor"})
    assert search.status_code == 200
    assert [item["id"] for item in search.json()["items"]] == ["home_visit"]

    page_one = client.get("/v1/service-definitions/paged", params={"limit": 2})
    assert page_one.status_code == 200
    page_one_payload = page_one.json()
    assert [item["id"] for item in page_one_payload["items"]] == [
        "ambulance",
        "home_visit",
    ]
    assert page_one_payload["next"]["cursor"] == "2"

    page_two = client.get(
        "/v1/service-definitions/paged",
        params={"limit": 2, "cursor": "2"},
    )
    assert page_two.status_code == 200
    page_two_payload = page_two.json()
    assert [item["id"] for item in page_two_payload["items"]] == ["pharmacy"]
    assert page_two_payload["next"]["cursor"] is None


def test_service_definitions_detail_returns_match_or_empty_list() -> None:
    _init_sqlite_db()
    client = TestClient(app)

    found = client.get("/v1/service-definitions/detail", params={"id": "pharmacy"})
    assert found.status_code == 200
    assert found.json()["items"][0]["id"] == "pharmacy"

    missing = client.get("/v1/service-definitions/detail", params={"id": "missing"})
    assert missing.status_code == 200
    assert missing.json() == {"items": []}
