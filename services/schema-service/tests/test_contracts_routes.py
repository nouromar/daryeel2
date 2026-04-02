from fastapi.testclient import TestClient

from app.main import app


def test_component_contracts_introspection_endpoint() -> None:
    client = TestClient(app)
    response = client.get("/contracts/components")
    assert response.status_code == 200

    assert response.headers.get("etag")
    cache_control = (response.headers.get("cache-control") or "").lower()
    assert "public" in cache_control
    assert "max-age=60" in cache_control
    assert "stale-while-revalidate=300" in cache_control

    payload = response.json()
    assert payload["package"] == "component-contracts"
    assert isinstance(payload["contracts"], list)
    assert any(c.get("name") == "InfoCard" for c in payload["contracts"])


def test_component_contracts_etag_304() -> None:
    client = TestClient(app)
    first = client.get("/contracts/components")
    assert first.status_code == 200
    etag = first.headers.get("etag")
    assert etag

    second = client.get(
        "/contracts/components",
        headers={"if-none-match": etag},
    )
    assert second.status_code == 304
    assert second.text == ""
    assert second.headers.get("etag") == etag
