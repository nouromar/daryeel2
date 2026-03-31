from fastapi.testclient import TestClient

from app.main import app


def test_config_bootstrap_customer_app() -> None:
    client = TestClient(app)
    response = client.get("/config/bootstrap", params={"product": "customer_app"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["bootstrapVersion"] == 1
    assert payload["product"] == "customer_app"
    assert payload["initialScreenId"] == "customer_home"
    assert payload["defaultThemeId"] == "customer-default"
    assert payload["configSchemaVersion"] == 1
    assert payload["configSnapshotId"]
    assert payload["configTtlSeconds"] > 0
    # Unified service advertises itself for schema/theme base URLs.
    assert payload["schemaServiceBaseUrl"]
    assert payload["themeServiceBaseUrl"]
    assert payload["configServiceBaseUrl"]
    assert payload["telemetryIngestUrl"]

    assert response.headers.get("etag")
    assert response.headers.get("cache-control")


def test_config_bootstrap_etag_304() -> None:
    client = TestClient(app)
    first = client.get("/config/bootstrap", params={"product": "customer_app"})
    assert first.status_code == 200
    etag = first.headers.get("etag")
    assert etag

    second = client.get(
        "/config/bootstrap",
        params={"product": "customer_app"},
        headers={"if-none-match": etag},
    )
    assert second.status_code == 304
    assert second.headers.get("etag") == etag


def test_config_snapshot_roundtrip() -> None:
    client = TestClient(app)
    bootstrap = client.get("/config/bootstrap", params={"product": "customer_app"})
    snapshot_id = bootstrap.json()["configSnapshotId"]

    response = client.get(f"/config/snapshots/{snapshot_id}")
    assert response.status_code == 200
    payload = response.json()
    assert payload["schemaVersion"] == 1
    assert payload["snapshotId"] == snapshot_id
    assert isinstance(payload["flags"], dict)

    assert response.headers.get("etag")
    assert "immutable" in (response.headers.get("cache-control") or "")
