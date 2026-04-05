from __future__ import annotations

from collections import Counter, deque
from datetime import datetime
from threading import Lock
from time import time
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.budgets import DEFAULT_DIAGNOSTICS_BUDGETS_PER_SESSION


DiagnosticSeverity = Literal["debug", "info", "warn", "error", "fatal"]
DiagnosticKind = Literal["diagnostic", "metric", "trace"]


class DiagnosticEventIn(BaseModel):
    eventSchemaVersion: int = 1
    kind: DiagnosticKind
    eventName: str = Field(min_length=1)
    severity: DiagnosticSeverity
    timestamp: datetime
    fingerprint: str = Field(min_length=1)

    # Runtime context + event payload are intentionally flexible, but must remain
    # JSON-object shaped.
    context: dict[str, Any] = Field(default_factory=dict)
    payload: dict[str, Any] = Field(default_factory=dict)


class DiagnosticsIngestRequest(BaseModel):
    events: list[DiagnosticEventIn] = Field(default_factory=list)
    droppedEventCount: int = 0


class DiagnosticsIngestResponse(BaseModel):
    status: str = "ok"
    accepted: int

    # Server-side drops (hardening).
    droppedDedupe: int = 0
    droppedBudget: int = 0
    droppedInvalid: int = 0


class RecentDiagnosticEvent(BaseModel):
    eventName: str
    severity: DiagnosticSeverity
    timestamp: datetime
    fingerprint: str


class RecentDiagnosticsResponse(BaseModel):
    status: str = "ok"
    events: list[RecentDiagnosticEvent]


class DiagnosticsIngestResult(BaseModel):
    accepted: list[DiagnosticEventIn]
    dropped_dedupe: int = 0
    dropped_budget: int = 0
    dropped_invalid: int = 0

    accepted_by_severity: dict[str, int] = Field(default_factory=dict)
    received_by_severity: dict[str, int] = Field(default_factory=dict)


class DiagnosticsIngestor:
    def __init__(
        self,
        *,
        dedupe_ttl_seconds: int = 60,
        max_recent_events: int = 500,
        budget_window_seconds: int = 30 * 60,
        budgets_per_session: dict[str, int | None] | None = None,
        max_dedupe_entries: int = 20_000,
    ) -> None:
        self._dedupe_ttl_seconds = dedupe_ttl_seconds
        self._max_recent_events = max_recent_events
        self._budget_window_seconds = budget_window_seconds
        self._budgets_per_session = budgets_per_session or DEFAULT_DIAGNOSTICS_BUDGETS_PER_SESSION
        self._max_dedupe_entries = max_dedupe_entries

        self._lock = Lock()

        # fingerprint -> last_seen_epoch_seconds
        self._last_seen: dict[str, float] = {}
        self._last_seen_order: deque[tuple[float, str]] = deque()

        # session_id -> (window_start_epoch_seconds, counters)
        self._session_windows: dict[str, tuple[float, Counter[str]]] = {}

        self._recent: deque[RecentDiagnosticEvent] = deque(maxlen=max_recent_events)

    def ingest(self, events: list[DiagnosticEventIn], *, session_id: str | None) -> DiagnosticsIngestResult:
        received_by_severity = dict(Counter([e.severity for e in events]))

        accepted: list[DiagnosticEventIn] = []
        dropped_dedupe = 0
        dropped_budget = 0
        dropped_invalid = 0

        now = time()
        session_key = session_id or "<unknown>"

        with self._lock:
            self._evict_old(now)
            window_start, counters = self._get_window(now, session_key)

            for ev in events:
                # Basic guardrails.
                if not ev.fingerprint or not ev.eventName:
                    dropped_invalid += 1
                    continue

                # 1) TTL dedupe by fingerprint.
                last = self._last_seen.get(ev.fingerprint)
                if last is not None and (now - last) <= self._dedupe_ttl_seconds:
                    dropped_dedupe += 1
                    continue

                # 2) Per-session budgets by severity.
                budget = self._budgets_per_session.get(ev.severity)
                if budget is not None:
                    if counters[ev.severity] >= budget:
                        dropped_budget += 1
                        continue

                # Accept.
                accepted.append(ev)
                counters[ev.severity] += 1
                self._last_seen[ev.fingerprint] = now
                self._last_seen_order.append((now, ev.fingerprint))
                self._recent.append(
                    RecentDiagnosticEvent(
                        eventName=ev.eventName,
                        severity=ev.severity,
                        timestamp=ev.timestamp,
                        fingerprint=ev.fingerprint,
                    )
                )

            # Persist window updates.
            self._session_windows[session_key] = (window_start, counters)

        accepted_by_severity = dict(Counter([e.severity for e in accepted]))
        return DiagnosticsIngestResult(
            accepted=accepted,
            dropped_dedupe=dropped_dedupe,
            dropped_budget=dropped_budget,
            dropped_invalid=dropped_invalid,
            accepted_by_severity=accepted_by_severity,
            received_by_severity=received_by_severity,
        )

    def recent(self, *, limit: int = 50) -> list[RecentDiagnosticEvent]:
        if limit <= 0:
            return []
        limit = min(limit, self._max_recent_events)
        with self._lock:
            items = list(self._recent)
        return items[-limit:]

    def _evict_old(self, now: float) -> None:
        # Dedupe eviction: remove entries older than TTL.
        ttl = self._dedupe_ttl_seconds
        while self._last_seen_order:
            ts, fp = self._last_seen_order[0]
            if (now - ts) <= ttl:
                break
            self._last_seen_order.popleft()
            # Only delete if this queue entry is the latest recorded.
            last = self._last_seen.get(fp)
            if last is not None and last == ts:
                self._last_seen.pop(fp, None)

        # Hard cap safety valve.
        if len(self._last_seen) > self._max_dedupe_entries:
            # Drop oldest half.
            to_drop = len(self._last_seen_order) // 2
            for _ in range(to_drop):
                if not self._last_seen_order:
                    break
                ts, fp = self._last_seen_order.popleft()
                last = self._last_seen.get(fp)
                if last is not None and last == ts:
                    self._last_seen.pop(fp, None)

        # Session window eviction.
        window = self._budget_window_seconds
        expired = [k for k, (start, _) in self._session_windows.items() if (now - start) > window]
        for k in expired:
            self._session_windows.pop(k, None)

    def _get_window(self, now: float, session_key: str) -> tuple[float, Counter[str]]:
        existing = self._session_windows.get(session_key)
        if existing is None:
            return now, Counter()
        window_start, counters = existing
        if (now - window_start) > self._budget_window_seconds:
            return now, Counter()
        return window_start, counters
