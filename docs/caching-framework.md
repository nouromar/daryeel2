# Daryeel2 — Caching Framework (Mobile-first clients + Redis-backed backend)

## Purpose
Daryeel2 needs a consistent caching strategy that:
- makes mobile clients **fast and offline-safe**
- keeps runtime overhead **near-zero** (no hot-path fetches)
- reduces backend load and cost
- supports controlled rollouts of config/schema/theme without app releases

This document defines the caching contract shared by:
- Flutter apps (customer/provider)
- web apps (ops/admin)
- runtime delivery services (schema-service)
- core API services

## Guiding principles
1) **Immutable-by-ID is the golden path**
- If a resource URL includes a stable identifier (snapshot/version/hash), the server MUST treat it as immutable.
- Immutable responses get long-lived caching.

2) **Bootstrap is small + revalidated**
- Bootstrap URLs are stable and can change.
- Clients should refresh bootstrap cheaply using `ETag` + `If-None-Match` → `304 Not Modified`.

3) **Last-known-good (LKG) everywhere**
- Clients must not be hostage to live delivery.
- Persist last-known-good config/schema/theme locally.

4) **No per-frame work**
- UI reads from an in-memory snapshot.
- Network refresh happens only on startup/foreground (throttled).

5) **Safety + privacy**
- Never cache user-specific or auth-scoped responses in shared caches.
- Avoid caching anything containing PII.

---

## Resource classes and cache rules

### A) Bootstrap (mutable)
Examples:
- `GET /config/bootstrap?product=customer_app`
- `GET /schemas/bootstrap`
- `GET /schemas/screens/{screen_id}`
- `GET /schemas/fragments/{fragment_id}`
- `GET /themes/catalog`
- `GET /themes/{theme_id}/{theme_mode}`

Server:
- MUST send `ETag`.
- SHOULD send: `Cache-Control: public, max-age=60, stale-while-revalidate=300`.
- MUST support conditional requests:
  - request: `If-None-Match: <etag>`
  - response: `304 Not Modified` (no body) when unchanged

Client:
- Store the last body + ETag.
- On refresh, send `If-None-Match`.
- If `304`, reuse cached body.

### B) Snapshots (immutable)
Examples:
- `GET /config/snapshots/{snapshotId}`

Server:
- MUST treat snapshot content as immutable.
- MUST send: `Cache-Control: public, max-age=31536000, immutable`.
- SHOULD send `ETag` and support `304` (optional but consistent).

Client:
- Persist snapshot JSON as LKG.
- If the snapshot is immutable, the client may skip revalidation.

### C) Documents that should become immutable-by-ID
Over time, schema/theme should follow the snapshot pattern:
- Schema screen documents should be addressable by stable IDs + versions.
- Theme documents should be addressable by stable IDs + versions.

DocId pinning (planned):
- Selector (mutable) responses SHOULD include a stable `x-daryeel-doc-id` header so clients can pin the exact immutable document they just received.
- Immutable documents SHOULD be fetchable by docId via endpoints like:
  - `GET /schemas/screens/docs/by-id/{docId}`
  - `GET /themes/docs/by-id/{docId}`
- Flutter client loaders already include support for these immutable-by-docId routes and header caching.
- As of current repo state, `schema-service` does not yet expose the immutable-by-docId routes and does not emit `x-daryeel-doc-id` on selector responses, so full end-to-end pinning requires server work.

If the URL does **not** contain a version, treat it like bootstrap (revalidated + short TTL).

---

## Mobile-first client caching architecture

### Layers
1) **In-memory (authoritative while app is running)**
- Parsed config snapshot
- Active schema bundle + resolved fragments
- Active theme tokens

2) **On-disk LKG (offline-safe)**
- LKG config snapshot JSON
- Optional: LKG bootstrap JSON + ETag
- Optional: LKG schema/theme documents + ETag

3) **Network revalidation**
- Conditional GET using `If-None-Match`.
- Refresh triggers:
  - cold start
  - app foreground (throttled, e.g. once per 5–15 minutes)

### Storage format (recommended)
For each cached HTTP resource:
- `body` (JSON string)
- `etag` (string)
- `storedAt` (unix ms)

### Failure handling
- If the network fails, use LKG.
- If LKG is corrupt/unparseable, fall back to bundled defaults.

---

## Backend caching architecture (Redis + in-process)

### Goals
- Reduce repetitive work (DB reads, JSON building, compatibility checks).
- Avoid cache stampedes.
- Keep correctness independent of cache availability.

### Where Redis fits
Use Redis for:
- shared caches across multiple instances
- high-read low-write resources (bootstrap selection results, resolved documents)
- rate limiting / budgets (already relevant to diagnostics ingestion)

Keep in-process caches only as micro-optimizations.

### Cache key strategy
- Prefix all keys per service:
  - `daryeel2:schema-service:<resource>:<selector>`

Examples:
- `daryeel2:schema-service:config:bootstrap:product=customer_app`
- `daryeel2:schema-service:config:snapshot:cfg_customer_app_default_v1`

### Cache entries
Store (at minimum):
- serialized JSON body
- ETag

### TTL guidance
- Bootstrap cache TTL: 60–300s
- Snapshot cache TTL: very long (days) or no expiry

### Stampede protection (recommended)
When a key misses, use a short-lived lock:
- `SET lock:<key> <token> NX EX 5`
- only the lock holder recomputes
- others serve stale if available or retry with jitter

---

## Standard HTTP headers (contract)

### Response headers
- Always include:
  - `ETag: "..."`
  - `Cache-Control: ...`

### Request headers
- Conditional GET:
  - `If-None-Match: "..."`

### Correlation headers
Keep correlation headers separate from caching semantics:
- `x-request-id`
- `x-daryeel-session-id`
- `x-daryeel-schema-version`
- `x-daryeel-config-snapshot`

Do NOT put these in `Vary` unless absolutely required.

---

## Rollout plan
1) Adopt ETag/304 + cache-control on bootstrap and snapshot endpoints (done for config/schema/theme selectors + snapshots).
2) Add client HTTP cache helper for conditional GET and LKG persistence.
3) Introduce Redis cache backend in services (optional early; mandatory later at scale).
4) Move schema/theme documents toward immutable-by-ID addressing.

## Non-goals (v1)
- caching private/user-specific resources in shared caches
- complex cache invalidation graphs
- realtime push cache invalidation
