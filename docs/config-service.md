# Daryeel2 — Config Service (Mobile-first, Near-zero Overhead)

## Purpose
Daryeel2 needs a single, consistent way to control and tune runtime behavior across:
- mobile apps (customer/provider)
- web apps (ops/admin)
- runtime delivery services (schema/theme/config)
- core API services

The config service provides **versioned, cached, offline-safe configuration snapshots** that are:
- cheap to fetch (one bootstrap request)
- cheap to evaluate (snapshot reads, no per-frame work)
- safe by default (last-known-good + bundled defaults)
- auditable (who changed what, when)

This document defines the target shape. The current framework implementation is a minimal `/config/bootstrap` endpoint in the unified schema-service.

Current repo reality:
- Config delivery is implemented in the unified `schema-service`.
- Both `GET /config/bootstrap` and `GET /config/snapshots/{snapshotId}` exist.
- Snapshots are currently deterministic, in-memory documents (file-free) intended to evolve toward DB-backed immutable snapshots.

## Goals
- **Mobile-first**: offline-safe, low bandwidth, avoids chatty fetches.
- **Near-zero runtime overhead**: config reads are in-memory, O(1), no polling in hot UI paths.
- **Operational tuning without app releases**: adjust intervals, endpoints, feature enablement.
- **Deterministic behavior**: no hidden implicit targeting rules; explicit selection inputs.
- **Backwards compatible evolution**: versioned payloads, safe defaults, ignore unknown keys.

## Non-goals (v1)
- A/B testing, percentage rollouts, or complex per-user targeting.
- Real-time push updates.
- Arbitrary expression language in config.
- Letting config declare arbitrary backend endpoints to call from schema.

## Key concepts

### 1) Bootstrap vs snapshot
- **Bootstrap**: a tiny response that tells the client which **snapshot** to use and where to fetch runtime assets (schema/theme/config).
- **Snapshot**: an immutable config document with an ID/version. Clients can persist it and reuse it offline.

This is the core pattern that keeps the system efficient:
- bootstrap can be cached with `ETag` and refreshed cheaply
- snapshots are addressed by ID and are immutable, so they cache perfectly

### 2) Last-known-good (LKG)
Clients must never become hostage to live config delivery.

Rules:
- The app ships with **bundled defaults** (compile-time or baked JSON) sufficient to run.
- The app persists the **last-known-good snapshot**.
- On startup:
  1. load bundled defaults
  2. load LKG (if present) and apply
  3. fetch bootstrap (best-effort)
  4. if bootstrap points to a newer snapshot, fetch snapshot and promote it to LKG

### 3) Explicit selection inputs
Bootstrap selection uses a bounded set of request attributes:
- `product` (required): e.g. `customer_app`
- `platform` (optional): `ios | android | web`
- `appVersion` (optional): semver/string
- `locale` (optional): `en`, `so`, ...
- `region` (optional): internal region slug

In v1, selection should stay deterministic and simple (exact match then fallback).

## API design (v1)

### `GET /config/bootstrap`
Returns the minimal information required to start the app and find the current config snapshot.

Request:
- query params:
  - `product` (required)
  - `platform` (optional)
  - `appVersion` (optional)

Response (current repo shape; served by `schema-service`):

```json
{
  "bootstrapVersion": 1,
  "product": "customer_app",
  "initialScreenId": "customer_home",
  "defaultThemeId": "customer-default",
  "defaultThemeMode": "light",

  "configSchemaVersion": 1,
  "configSnapshotId": "cfg_customer_app_default_v1",
  "configTtlSeconds": 3600,

  "schemaServiceBaseUrl": "https://runtime.example.com",
  "themeServiceBaseUrl": "https://runtime.example.com",
  "configServiceBaseUrl": "https://runtime.example.com",
  "telemetryIngestUrl": "https://runtime.example.com/telemetry/diagnostics"
}
```

Response (target shape; optional future refactor):

```json
{
  "bootstrapVersion": 1,
  "product": "customer_app",

  "endpoints": {
    "schemaBaseUrl": "https://runtime.example.com",
    "themeBaseUrl": "https://runtime.example.com",
    "configBaseUrl": "https://runtime.example.com",
    "telemetryIngestUrl": "https://runtime.example.com/telemetry/diagnostics"
  },

  "initial": {
    "screenId": "customer_home",
    "themeId": "customer-default",
    "themeMode": "light"
  },

  "config": {
    "snapshotId": "cfg_01J...",
    "schemaVersion": 1,
    "ttlSeconds": 3600
  }
}
```

Caching:
- `ETag`: fingerprint of the current bootstrap selection result.
- `Cache-Control`:
  - production recommendation: `public, max-age=60, stale-while-revalidate=300`
  - development: short max-age or disabled

Semantics:
- If the client sends `If-None-Match` with a matching ETag, server returns `304 Not Modified`.
- Bootstrap should remain small (ideally < 2–4 KB).

### `GET /config/snapshots/{snapshotId}`
Returns the immutable snapshot document. This is the main “tuning surface”.

Response (example):

```json
{
  "schemaVersion": 1,
  "snapshotId": "cfg_01J...",
  "createdAt": "2026-03-31T12:00:00Z",

  "flags": {
    "featureFlags": ["customer.new_home", "customer.enable_tips"]
  },

  "telemetry": {
    "enableRemoteIngest": true,
    "maxEventsPerSession": 200,
    "dedupeTtlSeconds": 300
  },

  "runtime": {
    "pollIntervalsSeconds": {
      "activeRequest": 10
    },
    "network": {
      "defaultTimeoutMs": 8000
    }
  },

  "serviceCatalog": {
    "services": [
      {
        "slug": "ambulance",
        "isActive": true,
        "capabilities": {
          "requiresPickup": true,
          "requiresDropoff": true,
          "supportsScheduling": false
        }
      }
    ]
  }
}
```

Caching:
- `Cache-Control: public, max-age=31536000, immutable` (snapshots never change)
- Optionally also include `ETag` for completeness.

Implementation note (current repo):
- Snapshot payload is intentionally flexible: clients must ignore unknown keys.
- The runtime currently consumes:
  - `flags.featureFlags` (list of enabled keys)
  - `telemetry.enableRemoteIngest`, `telemetry.dedupeTtlSeconds`, `telemetry.maxInfoPerSession`, `telemetry.maxWarnPerSession`

## Client integration (Flutter)

### Snapshot access patterns (zero hot-path cost)
- Parse JSON once at load time into a typed config object.
- Keep the active snapshot in memory (e.g. a single provider/state holder).
- Expose accessors that do not allocate:
  - `bool isEnabled(String flagKey)`
  - `Duration pollInterval(String key, {Duration fallback})`

### Refresh strategy
- Do not poll continuously.
- Refresh bootstrap opportunistically:
  - on cold start
  - when app returns to foreground (with a throttle)

### Correlation and diagnostics
- Include the active `config.snapshotId` in:
  - diagnostics context (so events answer “what config was active?”)
  - correlation headers where useful (optional): `x-daryeel-config-snapshot`

### Feature flags and `visibleWhen`
`visibleWhen.featureFlag` should be evaluated against a snapshot-provided set:
- `enabledFeatureFlags = config.flags.featureFlags`

This keeps visibility evaluation purely local and cheap.

## Server-side storage and governance (target)

### Storage model (recommended)
- `config_snapshots` table:
  - `snapshot_id` (string/uuid, unique)
  - `product` (string)
  - `platform` (nullable string)
  - `app_version_min` / `app_version_max` (nullable; optional in v1)
  - `document_json` (jsonb)
  - `created_at`, `created_by`

- `config_bootstrap_index` (optional materialization):
  - maps selection inputs to current `snapshot_id`
  - allows quick bootstrap lookup

### Governance
- All changes are append-only (new snapshot) + pointer update.
- Audit who changed selection pointers.
- Validate payload shape against a versioned schema before publishing.

## Migration path from today
1. Keep current `/config/bootstrap` shape working for `customer_app`.
2. Add `endpoints`, `initial`, and `config.snapshotId` to bootstrap response.
3. Add `/config/snapshots/{snapshotId}` serving a first snapshot (even if file-based initially).
4. Update apps to use bootstrap + snapshot and remove hardcoded tuning knobs.

## Open questions
- Do we want a single unified snapshot per product, or separate snapshots for `flags`, `runtime`, and `serviceCatalog`?
- Should snapshots be signed (integrity) for hostile networks, or is TLS + server trust sufficient for v1?
- How do we want to handle environment separation (`dev/staging/prod`) in bootstrap selection?
