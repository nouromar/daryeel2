from __future__ import annotations

import importlib

import pytest


def test_registry_startup_validation_fails_fast(monkeypatch: pytest.MonkeyPatch) -> None:
    # Force startup validation enabled + strict.
    monkeypatch.setenv("SCHEMA_SERVICE_VALIDATE_FIXTURES_ON_STARTUP", "true")
    monkeypatch.setenv("SCHEMA_SERVICE_STRICT_FIXTURE_VALIDATION", "true")

    # Patch validate_examples to simulate a failure without touching fixtures.
    from app import validate_all

    class _Issue:
        def __init__(self, code: str, message: str, path: str) -> None:
            self.code = code
            self.message = message
            self.path = path

    monkeypatch.setattr(
        validate_all,
        "validate_examples",
        lambda **_: [_Issue("unknown_prop", "bad prop", "x.screen.json")],
    )

    # Reload settings + registry to re-run startup hook.
    from app import settings as settings_module

    importlib.reload(settings_module)

    from app import registry as registry_module

    with pytest.raises(RuntimeError):
        importlib.reload(registry_module)
