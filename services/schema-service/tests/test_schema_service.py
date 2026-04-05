from fastapi.testclient import TestClient

from app.main import app


def test_health_ok() -> None:
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert "x-request-id" in response.headers
    payload = response.json()
    assert payload["status"] == "ok"


def test_request_id_is_echoed_when_provided() -> None:
    client = TestClient(app)
    response = client.get(
        "/health",
        headers={"x-request-id": "abc123", "x-daryeel-session-id": "sess1"},
    )
    assert response.status_code == 200
    assert response.headers.get("x-request-id") == "abc123"


def test_ingest_diagnostics_accepts_events() -> None:
    client = TestClient(app)
    response = client.post(
        "/telemetry/diagnostics",
        headers={"x-request-id": "req1", "x-daryeel-session-id": "sess1"},
        json={
            "events": [
                {
                    "eventSchemaVersion": 1,
                    "kind": "diagnostic",
                    "eventName": "runtime.action.dispatch_failed",
                    "severity": "error",
                    "timestamp": "2026-03-31T12:00:00Z",
                    "fingerprint": "runtime.action.dispatch_failed:navigate:x",
                    "context": {"app": {"appId": "customer-app"}},
                    "payload": {"actionType": "navigate"},
                }
            ],
            "droppedEventCount": 2,
        },
    )
    assert response.status_code == 202
    assert response.headers.get("x-request-id") == "req1"
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["accepted"] == 1


def test_ingest_diagnostics_dedupes_by_fingerprint() -> None:
    client = TestClient(app)
    payload = {
        "events": [
            {
                "eventSchemaVersion": 1,
                "kind": "diagnostic",
                "eventName": "runtime.visibility.unknown_rule_key",
                "severity": "warn",
                "timestamp": "2026-03-31T12:00:00Z",
                "fingerprint": "runtime.visibility.unknown_rule_key:x",
                "context": {},
                "payload": {},
            }
        ]
    }

    r1 = client.post("/telemetry/diagnostics", json=payload)
    assert r1.status_code == 202
    p1 = r1.json()
    assert p1["accepted"] == 1

    r2 = client.post("/telemetry/diagnostics", json=payload)
    assert r2.status_code == 202
    p2 = r2.json()
    assert p2["accepted"] == 0
    assert p2["droppedDedupe"] >= 1


def test_recent_diagnostics_endpoint_in_development() -> None:
    client = TestClient(app)
    client.post(
        "/telemetry/diagnostics",
        json={
            "events": [
                {
                    "eventSchemaVersion": 1,
                    "kind": "diagnostic",
                    "eventName": "runtime.schema.activated",
                    "severity": "info",
                    "timestamp": "2026-03-31T12:00:01Z",
                    "fingerprint": "runtime.schema.activated:test",
                    "context": {},
                    "payload": {},
                }
            ]
        },
    )

    recent = client.get("/telemetry/diagnostics/recent?limit=10")
    assert recent.status_code == 200
    body = recent.json()
    assert body["status"] == "ok"
    assert body["events"]
    assert any(e["eventName"] == "runtime.schema.activated" for e in body["events"])


def test_screen_customer_home_ok() -> None:
    client = TestClient(app)
    response = client.get("/schemas/screens/customer_home")
    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == "customer_home"
    assert payload["schemaVersion"] == "1.0"


    def test_screen_schema_etag_304(client):
        first = client.get("/schemas/screens/customer_home")
        assert first.status_code == 200
        assert "etag" in {k.lower(): v for k, v in first.headers.items()}
        etag = first.headers.get("ETag")
        assert etag

        second = client.get(
            "/schemas/screens/customer_home",
            headers={"If-None-Match": etag},
        )
        assert second.status_code == 304
        assert second.text == ""


def test_ref_nodes_are_supported_by_models() -> None:
    # Contract allows refs in slots; ensure our Pydantic models accept it.
    client = TestClient(app)
    raw = client.get("/schemas/screens/customer_home").json()

    slots = raw.get("root", {}).get("slots", {})
    assert isinstance(slots, dict)

    slot_key: str | None = None
    if isinstance(slots.get("body"), list):
        slot_key = "body"
    elif isinstance(slots.get("home"), list):
        slot_key = "home"
    else:
        for k, v in slots.items():
            if isinstance(v, list):
                slot_key = k
                break

    assert slot_key is not None
    slots[slot_key].append({"ref": "section:example"})

    # If models don't support RefNode, /schemas/screens would fail to validate.
    # This uses the same model parsing codepath as the live endpoint.
    from app.schemas import ScreenSchema

    parsed = ScreenSchema.model_validate(raw)
    assert parsed.root.slots[slot_key][-1].ref == "section:example"


def test_fragment_endpoint_ok() -> None:
    client = TestClient(app)
    response = client.get("/schemas/fragments/section:customer_welcome_v1")
    assert response.status_code == 200
    payload = response.json()
    assert payload["documentType"] == "fragment"
    assert payload["id"] == "section:customer_welcome_v1"
    assert payload["node"]["type"] == "InfoCard"