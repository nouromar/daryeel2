# RFC — Schema Compatibility & Fallback (Client + schema-service)

Status: Draft

## 1) Purpose
Define a long-term, low-risk compatibility and fallback design for Daryeel2’s schema-driven UI.

This RFC aims to minimize:
- **Outage risk** (bad rollout, backend downtime, network failures)
- **Feature-loss risk** (unexpected incompatibility or partial rendering)
- **Security risk** (treating remote schema/theme as trusted code)

While staying:
- **Simple to maintain** (centralized, testable policies)
- **Scalable** (multiple apps/products, multiple runtimes)
- **Rollback-friendly** (server mapping changes do not require app releases)

## 2) Non-goals
- Real-time push invalidation
- Arbitrary code execution or “Turing-complete schema logic”
- Letting remote configuration expand what a binary can safely render (unless signed)

## 3) Terms
- **Selector URL (mutable)**: A stable URL that can change over time (e.g., “latest for screenId”).
  - Example: `GET /schemas/screens/{screen_id}`
- **Immutable document URL**: A URL addressed by a stable identifier (docId) whose content MUST NOT change.
  - Example: `GET /schemas/screens/docs/by-id/{docId}`
- **docId**: Stable identifier for a schema/theme document (currently SHA-256 in schema-service).
  - Exposed via header: `x-daryeel-doc-id: <sha256>`
- **Pinned**: Client stores a docId that is known to have rendered successfully.
- **LKG (Last Known Good)**: Cached/persisted document content (and optional metadata) that is known to be safe.
- **Compatibility policy**: Rules that decide whether a document is safe to render in this binary.
- **Budgeting**: Hard limits that prevent denial-of-service via oversized/deep schemas (max bytes/nodes/depth/fragments).

## 4) Design Principles
### 4.1 Treat schema/theme as untrusted input
Every remote document (schema/theme/config) must be:
- parsed strictly
- validated against format and budgets
- checked for compatibility before render

### 4.2 Centralize compatibility decisions
Compatibility is a **single decision point** in the shared runtime, not scattered across UI code.
Apps provide a policy configuration; the runtime enforces it.

### 4.3 Never partially render incompatible/invalid schemas
If a document is incompatible or invalid:
- **do not** partially render
- **do** fall back deterministically
- **do** emit diagnostics with reason codes

### 4.4 Two-phase commit for pinned state
Never overwrite pinned/LKG state with a candidate document until it has:
- passed compatibility
- resolved refs (bounded)
- loaded theme (if required)
- successfully built/rendered

### 4.5 Remote policy is restrict-only by default
Remote configuration is useful operationally, but must not become an attack surface.

Rule:
- shipped policy = **maximum** trust boundary
- remote policy may only **restrict** acceptance (intersection)
- expanding acceptance requires signed policy + pinned public key

Implementation status (repo):
- Customer app supports a restrict-only overlay loaded from the immutable config snapshot under `runtime.schemaCompatibilityPolicyOverlay`.
- Overlay is applied via intersection with the shipped policy (never expands acceptance).

## 5) Compatibility Model (Long-term)

This RFC recommends **capability-based compatibility** with a small “hard gate” integer.

### 5.1 Schema metadata (recommended)
Every schema/theme document SHOULD include a `meta` object (exact schema format may vary per doc type):

- `meta.schemaFormatVersion`: e.g. `"1.0"` (format contract)
- `meta.product`: e.g. `"customer_app"`
- `meta.id`: screenId/fragmentId/themeId
- `meta.mode`: theme mode (for themes only), e.g. `"light" | "dark"`
- `meta.requiresCapabilities`: list of strings
  - examples:
    - `"refNodes"`
    - `"actions.submit_form.v1"`
    - `"component.AddressSection@1"`
- `meta.minRuntimeApi`: integer hard gate, monotonic
- `meta.contractsCatalogVersion` (optional): string version or hash of contracts catalog

Notes:
- `schemaFormatVersion` is not sufficient alone as the platform grows.
- `requiresCapabilities` allows compatibility to evolve without constant global version bumps.

### 5.2 Runtime declares support
Each runtime binary declares:
- `runtimeApi`: integer
- `supportedCapabilities: Set<String>`

### 5.3 Compatibility decision
A document is compatible if:
- `minRuntimeApi` is absent OR `runtimeApi >= minRuntimeApi`
- `requiresCapabilities ⊆ supportedCapabilities`
- additional app policy constraints pass (product allowlist, theme modes, etc.)

### 5.4 Compatibility outputs (required)
The checker MUST return a structured result:

- `compatible`
- `incompatible` with:
  - `code`: stable reason code
  - `details`: helpful debugging info

Recommended reason codes:
- `schema_format_unsupported`
- `min_runtime_too_high`
- `missing_capability`
- `product_not_allowed`
- `theme_mode_not_allowed`
- `contracts_version_mismatch`

## 6) Fallback Ladder (Client)

For each screenId (or entry point), the client uses this order:

1) **Pinned immutable doc** (network)
2) **Cached LKG pinned doc** (offline/fast path)
3) **Selector (latest)** (network)
4) **Bundled** (always available)

This guarantees:
- stable UX during rollouts
- offline boot when possible
- safe behavior during backend failures

### 6.1 Client state
Persist per `(product, screenId)`:
- `pinnedDocId`: string | null
- `pinnedDocStoredAt`: timestamp

Persist per `docId`:
- `docBody`: JSON string
- `etag` (optional)
- `storedAt`

Additionally:
- selector cache (body + etag) may be kept for performance, but selector content must not be treated as immutable.

### 6.2 Algorithm (pseudocode)

```
loadScreen(screenId):
  pinned = pinnedDocId(screenId)

  if pinned != null:
    # 1) Pinned immutable (network)
    result = tryLoadImmutableByDocId(pinned)
    if result.ok:
      return result

    # 2) Pinned immutable (cached LKG)
    cached = tryLoadCachedDoc(pinned)
    if cached.ok:
      return cached

  # 3) Selector (latest)
  candidate = tryLoadSelector(screenId)
  if candidate.ok:
    # Two-phase commit: only pin after success
    pinDocId(screenId, candidate.docId)
    persistDoc(candidate.docId, candidate.body)
    return candidate

  # 4) Bundled
  return loadBundled(screenId)
```

Where `tryLoadImmutableByDocId` and `tryLoadSelector` both include:
- strict parsing
- budgets
- compatibility check
- ref resolution
- theme load (if required)

### 6.3 Two-phase commit (strict)
Pin/persist candidate docId only after:
- full load + resolve succeeds
- the screen builds successfully

If the candidate fails at any step:
- keep the old pin
- emit a diagnostic with `fallback_rung` and `reason_code`

### 6.4 Selector → docId mapping
Selector responses SHOULD expose the chosen immutable id:
- `x-daryeel-doc-id: <docId>`

The client MUST treat this as advisory and still validate locally.

## 7) Server Contract (schema-service)

### 7.1 Selector endpoints (mutable)
Examples:
- `GET /schemas/screens/{screen_id}`
- `GET /schemas/fragments/{fragment_id}`
- `GET /themes/{theme_id}/{theme_mode}`

Requirements:
- MUST send `ETag`
- MUST support `If-None-Match` → `304`
- SHOULD send short-lived caching:
  - see `docs/caching-framework.md`
- SHOULD include `x-daryeel-doc-id` for pinning workflows

### 7.2 Immutable endpoints (by docId)
Examples:
- `GET /schemas/screens/docs/by-id/{docId}`
- `GET /schemas/fragments/docs/by-id/{docId}`
- `GET /themes/docs/by-id/{docId}`

Requirements:
- MUST treat content as immutable
- MUST send `Cache-Control: public, max-age=31536000, immutable`

Note (Apr 2026 repo state):
- Flutter clients already include loaders for `/schemas/screens/docs/by-id/{docId}` and `/themes/docs/by-id/{docId}`.
- `schema-service` does not yet expose immutable-by-id routes and does not yet emit `x-daryeel-doc-id` on selector responses. Full pinning requires those server changes.

### 7.3 Rollback
Rollback is performed server-side by changing selector mappings (e.g., `app/mappings.json`).
Clients remain safe because:
- pinned/LKG continue to work
- selector will eventually point to a known-good docId

### 7.4 Optional: Negotiation (future)
A negotiation layer can reduce wasted downloads:
- client sends `runtimeApi` + capabilities
- server selects best compatible docId

Important: client still validates locally.

## 8) Observability & Diagnostics (required)

Compatibility and fallback are only “safe” if they are observable.

### 8.1 Standard summary event (required)

Clients MUST emit one dashboard-friendly event per screen load:

- `runtime.screen_load.summary`

This event standardizes payload keys and keeps values low-cardinality.
See `ScreenLoadSummaryKeys` (exported by `flutter_runtime`).

Required fields (minimum):
- `screenLoadId`
- `finalSchemaSource`: `pinned_immutable | cached_pinned | selector | bundled | bundled_fallback`
- `finalSchemaReasonCode` (optional): stable wire value from `SchemaLadderReason`
- `schemaDocId` (optional)
- `parseErrorCount`, `refErrorCount`
- `attemptCount`, `fallbackCount`, `totalLoadMs`

### 8.2 Ladder events (recommended)

In addition to the summary, the client SHOULD emit the ladder events:
- `runtime.schema.ladder.source_used`
- `runtime.schema.ladder.fallback`
- `runtime.schema.ladder.pin_promoted`
- `runtime.schema.ladder.pin_cleared`

These provide detailed “why did we fall back?” breadcrumbs without requiring
high-volume per-step tracing.

Correlation requirements:
- client-generated session id
- `x-request-id` header for server logs

Recommended counters/dashboards:
- fallback rung rates (percent)
- top incompatibility reason codes
- selector vs pinned usage ratio
- last-known-good age distribution

## 9) Security Controls (low-risk defaults)

### 9.1 Fail closed
If parsing/validation fails: treat as incompatible and fall back.

### 9.2 Budgeting everywhere
Budgets MUST exist both server-side (publish/validate) and client-side (runtime):
- max doc bytes
- max nodes
- max ref depth
- max fragments

### 9.3 Asset and action restrictions
- restrict external asset domains (or proxy)
- unknown actions become **no-op + diagnostic** (never crash)

### 9.4 Remote policy restrict-only
Remote config must not be able to expand what a binary accepts unless signed.

## 10) Rollout Plan

1) **Establish immutable docId everywhere** (already in schema-service).
2) **Implement pinned + LKG storage** in clients.
3) **Implement ladder** pinned→cached LKG→selector→bundled.
4) **Add compatibility reason codes + metrics**.
5) **(Optional) Add negotiation** once capabilities exist.

## 11) Open Questions
- Exact schema metadata fields to standardize in `schema_format_v1` (where to place `requiresCapabilities` / `minRuntimeApi`).
- Whether `contractsCatalogVersion` should be a semantic version or content hash.
- Whether to sign documents (docId is not a signature; it is an identifier).

---

## Appendix A — Current repo endpoints/headers (April 2026)
- Selector schemas:
  - `GET /schemas/screens/{screen_id}`
  - `GET /schemas/fragments/{fragment_id}`
- Immutable schemas:
  - `GET /schemas/screens/docs/{docId}`
  - `GET /schemas/fragments/docs/{docId}`
- Selector themes:
  - `GET /themes/{theme_id}/{theme_mode}`
- Immutable themes:
  - `GET /themes/docs/by-id/{docId}`
- Pin header:
  - `x-daryeel-doc-id: <sha256>`

See also:
- `docs/caching-framework.md`
- `services/schema-service/README.md`
