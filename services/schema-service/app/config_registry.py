from __future__ import annotations

from app.schemas import ConfigSnapshotResponse


# Phase 1: file-free, deterministic in-memory snapshots.
# Migration path: move these to DB-backed immutable snapshot documents.


_CUSTOMER_APP_DEFAULT_SNAPSHOT = ConfigSnapshotResponse(
    schemaVersion=1,
    snapshotId="cfg_customer_app_default_v1",
    createdAt="2026-03-31T00:00:00Z",
    flags={
        # Enablement-only flags; values/targeting are out of scope for v1.
        "featureFlags": [],
    },
    telemetry={
        # Defaults that keep remote ingest safe (client still enforces budgets).
        "enableRemoteIngest": True,
        "dedupeTtlSeconds": 60,
        "maxInfoPerSession": 30,
        "maxWarnPerSession": 50,
    },
    runtime={
        # Placeholder for future runtime knobs.
    },
    serviceCatalog={},
)


_SNAPSHOTS: dict[str, ConfigSnapshotResponse] = {
    _CUSTOMER_APP_DEFAULT_SNAPSHOT.snapshotId: _CUSTOMER_APP_DEFAULT_SNAPSHOT,
}


def current_snapshot_id_for_product(product: str) -> str:
    # Framework phase: explicit product mapping.
    if product == "customer_app":
        return _CUSTOMER_APP_DEFAULT_SNAPSHOT.snapshotId
    raise KeyError(product)


def get_snapshot(snapshot_id: str) -> ConfigSnapshotResponse | None:
    return _SNAPSHOTS.get(snapshot_id)
