from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_pharmacy_catalog_default_shape() -> None:
    client = TestClient(app)
    res = client.get("/v1/pharmacy/catalog")
    assert res.status_code == 200

    payload = res.json()
    assert isinstance(payload.get("items"), list)
    assert isinstance(payload.get("next"), dict)
    assert "cursor" in payload["next"]

    if payload["items"]:
        item = payload["items"][0]
        assert "id" in item
        assert "name" in item
        assert "rx_required" in item
        assert isinstance(item["rx_required"], bool)


def test_pharmacy_catalog_q_filters() -> None:
    client = TestClient(app)
    res = client.get("/v1/pharmacy/catalog", params={"q": "amox"})
    assert res.status_code == 200

    items = res.json()["items"]
    assert items
    assert any("amox" in str(x.get("name", "")).lower() for x in items)


def test_pharmacy_catalog_cursor_paginates() -> None:
    client = TestClient(app)

    first = client.get("/v1/pharmacy/catalog", params={"limit": 1})
    assert first.status_code == 200
    p1 = first.json()
    assert len(p1["items"]) == 1
    cursor = p1["next"].get("cursor")
    assert cursor

    second = client.get(
        "/v1/pharmacy/catalog",
        params={"limit": 1, "cursor": cursor},
    )
    assert second.status_code == 200
    p2 = second.json()
    assert len(p2["items"]) == 1
    assert p2["items"][0]["id"] != p1["items"][0]["id"]
