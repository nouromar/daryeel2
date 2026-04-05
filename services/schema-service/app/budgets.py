"""Centralized security/telemetry budgets for schema-service.

Keep these aligned with client-side (flutter_runtime) hardening budgets.
"""

from __future__ import annotations

from typing import Final


# -------------------------
# Schema validation budgets
# -------------------------

MAX_JSON_BYTES: Final[int] = 256 * 1024
MAX_NODES_PER_DOCUMENT: Final[int] = 5_000
MAX_REF_DEPTH: Final[int] = 32
MAX_FRAGMENTS_PER_SCREEN: Final[int] = 200


# -------------------------
# Telemetry ingest budgets
# -------------------------

# Per-session budgets within a rolling window (see DiagnosticsIngestor).
DEFAULT_DIAGNOSTICS_BUDGETS_PER_SESSION: Final[dict[str, int | None]] = {
    "debug": 0,
    "info": 30,
    "warn": 50,
    "error": None,
    "fatal": None,
}
