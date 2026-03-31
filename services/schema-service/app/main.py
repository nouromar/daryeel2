import json
import hashlib
import logging
import time
import uuid

from fastapi import FastAPI, HTTPException, Request
from starlette.responses import JSONResponse, Response

from app.cache import CacheValue, build_cache_backend
from app.config_registry import current_snapshot_id_for_product, get_snapshot
from app.registry import get_bootstrap, get_fragment, get_screen
from app.schemas import (
    BootstrapResponse,
    ConfigSnapshotResponse,
    FragmentSchema,
    HealthResponse,
    ProductBootstrapResponse,
    ScreenSchema,
    ThemeCatalogResponse,
    ThemeDocument,
)
from app.settings import settings
from app.telemetry import (
    DiagnosticsIngestRequest,
    DiagnosticsIngestResponse,
    DiagnosticsIngestor,
    RecentDiagnosticsResponse,
)
from app.theme_registry import find_theme_path, list_theme_paths, load_theme_document

app = FastAPI(title=settings.app_name)

_request_logger = logging.getLogger("daryeel.request")
_telemetry_logger = logging.getLogger("daryeel.telemetry")

_cache = build_cache_backend()

_diagnostics_ingestor = DiagnosticsIngestor(
    # In prod you may want debug=0; keep defaults aligned with the diagnostics spec.
    budgets_per_session={
        "debug": 0 if settings.app_env != "development" else 100,
        "info": 30,
        "warn": 50,
        "error": None,
        "fatal": None,
    }
)


@app.middleware("http")
async def request_id_and_access_log(request: Request, call_next) -> Response:
    start = time.perf_counter()

    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
    session_id = request.headers.get("x-daryeel-session-id")
    schema_version = request.headers.get("x-daryeel-schema-version")

    try:
        response = await call_next(request)
    except Exception as exc:  # pragma: no cover
        latency_ms = int((time.perf_counter() - start) * 1000)
        _request_logger.error(
            json.dumps(
                {
                    "eventName": "backend.request.unhandled_exception",
                    "service": "schema-service",
                    "requestId": request_id,
                    "sessionId": session_id,
                    "schemaVersion": schema_version,
                    "method": request.method,
                    "path": request.url.path,
                    "statusCode": 500,
                    "latencyMs": latency_ms,
                    "errorType": type(exc).__name__,
                }
            )
        )
        if settings.app_env == "development":
            raise
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
            headers={"x-request-id": request_id},
        )

    latency_ms = int((time.perf_counter() - start) * 1000)
    response.headers["x-request-id"] = request_id

    _request_logger.info(
        json.dumps(
            {
                "eventName": "backend.request.completed",
                "service": "schema-service",
                "requestId": request_id,
                "sessionId": session_id,
                "schemaVersion": schema_version,
                "method": request.method,
                "path": request.url.path,
                "statusCode": response.status_code,
                "latencyMs": latency_ms,
            }
        )
    )
    return response


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse()


def _normalized_base_url(request: Request) -> str:
    if settings.public_base_url:
        return settings.public_base_url.rstrip("/")
    # request.base_url includes a trailing slash.
    return str(request.base_url).rstrip("/")


def _strong_etag(payload: dict) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return '"%s"' % hashlib.sha256(raw).hexdigest()


def _cached_json_response(
    *,
    request: Request,
    cache_key: str,
    payload: dict,
    cache_control: str,
    ttl_seconds: int | None,
) -> Response:
    cached = _cache.get(cache_key)
    if cached is not None:
        if request.headers.get("if-none-match") == cached.etag:
            return Response(
                status_code=304,
                headers={
                    "etag": cached.etag,
                    "cache-control": cache_control,
                },
            )
        return JSONResponse(
            content=json.loads(cached.payload_json),
            headers={
                "etag": cached.etag,
                "cache-control": cache_control,
            },
        )

    etag = _strong_etag(payload)
    value = CacheValue(payload_json=json.dumps(payload), etag=etag)
    _cache.set(cache_key, value, ttl_seconds=ttl_seconds)

    if request.headers.get("if-none-match") == etag:
        return Response(
            status_code=304,
            headers={
                "etag": etag,
                "cache-control": cache_control,
            },
        )

    return JSONResponse(
        content=payload,
        headers={
            "etag": etag,
            "cache-control": cache_control,
        },
    )


@app.get("/schemas/bootstrap", response_model=BootstrapResponse)
def bootstrap(request: Request) -> BootstrapResponse | Response:
    payload = get_bootstrap().model_dump()
    return _cached_json_response(
        request=request,
        cache_key="schemas:bootstrap",
        payload=payload,
        cache_control="public, max-age=60, stale-while-revalidate=300",
        ttl_seconds=300,
    )


@app.get("/schemas/screens/{screen_id}", response_model=ScreenSchema)
def screen(request: Request, screen_id: str) -> ScreenSchema | Response:
    schema = get_screen(screen_id)
    if schema is None:
        raise HTTPException(status_code=404, detail="Schema not found")
    payload = schema.model_dump()
    return _cached_json_response(
        request=request,
        cache_key=f"schemas:screen:{screen_id}",
        payload=payload,
        cache_control="public, max-age=300, stale-while-revalidate=3600",
        ttl_seconds=3600,
    )


@app.get("/schemas/fragments/{fragment_id}", response_model=FragmentSchema)
def fragment(request: Request, fragment_id: str) -> FragmentSchema | Response:
    doc = get_fragment(fragment_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="Fragment not found")
    payload = doc.model_dump()
    return _cached_json_response(
        request=request,
        cache_key=f"schemas:fragment:{fragment_id}",
        payload=payload,
        cache_control="public, max-age=300, stale-while-revalidate=3600",
        ttl_seconds=3600,
    )


@app.get("/config/bootstrap", response_model=ProductBootstrapResponse)
def config_bootstrap(request: Request, product: str) -> ProductBootstrapResponse | Response:
    # Framework phase: keep rules deterministic and explicit.
    if product != "customer_app":
        raise HTTPException(status_code=404, detail="Unknown product")

    base_url = _normalized_base_url(request)

    try:
        snapshot_id = current_snapshot_id_for_product(product)
    except KeyError:
        raise HTTPException(status_code=404, detail="Unknown product")

    bootstrap = ProductBootstrapResponse(
        product=product,
        initialScreenId="customer_home",
        defaultThemeId="customer-default",
        defaultThemeMode="light",
        configSnapshotId=snapshot_id,
        configTtlSeconds=3600,
        schemaServiceBaseUrl=base_url,
        themeServiceBaseUrl=base_url,
        configServiceBaseUrl=base_url,
        telemetryIngestUrl=f"{base_url}/telemetry/diagnostics",
    )

    payload = bootstrap.model_dump()
    return _cached_json_response(
        request=request,
        cache_key=f"config:bootstrap:product={product}",
        payload=payload,
        cache_control="public, max-age=60, stale-while-revalidate=300",
        ttl_seconds=300,
    )


@app.get("/config/snapshots/{snapshot_id}", response_model=ConfigSnapshotResponse)
def config_snapshot(request: Request, snapshot_id: str) -> ConfigSnapshotResponse | Response:
    snapshot = get_snapshot(snapshot_id)
    if snapshot is None:
        raise HTTPException(status_code=404, detail="Unknown snapshot")

    payload = snapshot.model_dump()
    return _cached_json_response(
        request=request,
        cache_key=f"config:snapshot:{snapshot_id}",
        payload=payload,
        cache_control="public, max-age=31536000, immutable",
        # Even though snapshots are immutable, keep a bounded TTL in Redis to
        # avoid unbounded growth in early phases.
        ttl_seconds=7 * 24 * 3600,
    )


@app.get("/themes/catalog", response_model=ThemeCatalogResponse)
def themes_catalog(request: Request) -> ThemeCatalogResponse | Response:
    payload = ThemeCatalogResponse(themes=list_theme_paths()).model_dump()
    return _cached_json_response(
        request=request,
        cache_key="themes:catalog",
        payload=payload,
        cache_control="public, max-age=60, stale-while-revalidate=300",
        ttl_seconds=300,
    )


@app.get("/themes/{theme_id}/{theme_mode}", response_model=ThemeDocument)
def theme_document(request: Request, theme_id: str, theme_mode: str) -> ThemeDocument | Response:
    theme_path = find_theme_path(theme_id, theme_mode)
    if theme_path is None:
        raise HTTPException(status_code=404, detail="Theme not found")
    payload = ThemeDocument.model_validate(load_theme_document(theme_path)).model_dump()
    return _cached_json_response(
        request=request,
        cache_key=f"themes:doc:{theme_id}:{theme_mode}",
        payload=payload,
        cache_control="public, max-age=3600, stale-while-revalidate=86400",
        ttl_seconds=86400,
    )


@app.post("/telemetry/diagnostics", response_model=DiagnosticsIngestResponse, status_code=202)
def ingest_diagnostics(request: Request, body: DiagnosticsIngestRequest) -> DiagnosticsIngestResponse:
    # Keep ingestion safe and bounded.
    events = body.events
    if len(events) > 50:
        raise HTTPException(status_code=413, detail="Too many events")

    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > 128 * 1024:
                raise HTTPException(status_code=413, detail="Payload too large")
        except ValueError:
            pass

    session_id = request.headers.get("x-daryeel-session-id")
    result = _diagnostics_ingestor.ingest(events, session_id=session_id)

    accepted_events = result.accepted

    # Summarize rather than logging every event by default.
    by_severity = result.accepted_by_severity

    sample = [
        {
            "eventName": ev.eventName,
            "severity": ev.severity,
            "fingerprint": ev.fingerprint,
        }
        for ev in accepted_events[:3]
    ]

    _telemetry_logger.info(
        json.dumps(
            {
                "eventName": "telemetry.diagnostics.ingested",
                "service": "schema-service",
                "requestId": request.headers.get("x-request-id"),
                "sessionId": request.headers.get("x-daryeel-session-id"),
                "schemaVersion": request.headers.get("x-daryeel-schema-version"),
                "received": len(events),
                "accepted": len(accepted_events),
                "droppedEventCount": body.droppedEventCount,
                "droppedDedupe": result.dropped_dedupe,
                "droppedBudget": result.dropped_budget,
                "droppedInvalid": result.dropped_invalid,
                "receivedBySeverity": result.received_by_severity,
                "bySeverity": by_severity,
                "sample": sample,
            }
        )
    )

    # In development, log individual error/fatal events to aid debugging.
    if settings.app_env == "development":
        for ev in accepted_events:
            if ev.severity in ("error", "fatal"):
                _telemetry_logger.info(
                    json.dumps(
                        {
                            "eventName": "telemetry.diagnostics.event",
                            "severity": ev.severity,
                            "kind": ev.kind,
                            "name": ev.eventName,
                            "fingerprint": ev.fingerprint,
                        }
                    )
                )

    return DiagnosticsIngestResponse(
        accepted=len(accepted_events),
        droppedDedupe=result.dropped_dedupe,
        droppedBudget=result.dropped_budget,
        droppedInvalid=result.dropped_invalid,
    )


@app.get("/telemetry/diagnostics/recent", response_model=RecentDiagnosticsResponse)
def recent_diagnostics(limit: int = 50) -> RecentDiagnosticsResponse:
    # Dev-only inspection endpoint.
    if settings.app_env != "development":
        raise HTTPException(status_code=404, detail="Not found")
    events = _diagnostics_ingestor.recent(limit=limit)
    return RecentDiagnosticsResponse(events=events)