# Diagnostics, Logs, and Telemetry (Daryeel2)

This document defines how Daryeel clients and services should emit diagnostics and telemetry in a way that is:

- **Actionable** (supports debugging and rollback analysis)
- **Low-noise** (deduplicated, sampled, and budgeted)
- **Safe** (PII-minimizing with strict redaction rules)
- **Consistent** (shared event schema, naming, and correlation)
- **Affordable** (bounded performance and cost)

It consolidates the “Observability” expectations already stated across the schema-driven runtime docs into a single, implementable standard.

## 1) Scope

Applies to:

- **Mobile clients** (Flutter apps; primary focus today)
- **Web clients** (future parity; same event model)
- **Backend services** (FastAPI services in `services/`)
- **Schema-driven runtime** layers (schema pipeline → rendering → interaction → safety)

Out of scope:

- Product analytics (funnels, growth attribution) except where it overlaps with reliability.
- Business/audit events stored in DB (those are “domain events”, not logs).

## 2) Definitions (use these terms consistently)

### Diagnostics
Structured, runtime-level signals designed for **debugging and support**. Diagnostics are the canonical “what went wrong / what is active” stream.

Examples:
- Schema validation failure on screen render
- Unsupported component contract version
- Action dispatch failure (`navigate` route missing)

### Logs
Human-oriented line output used primarily during development (e.g., `debugPrint`). Logs should be treated as a *sink*, not the source of truth.

### Telemetry
The broader concept: diagnostics + performance metrics + counters + traces.

### Analytics
Product behavior measurement (e.g., conversion). Keep separate pipelines and governance.

### Audit / Domain Events
Append-only, attributable events stored for compliance and timelines (e.g., job status changes). These belong in the backend domain model; they are not “telemetry”.

## 3) Goals and non-goals

### Goals
1. **Reproduce issues from a single report** by seeing:
   - active schema id/version
   - component contract versions
   - flags/experiments
   - service slug + screen id
   - validation failures
   - action execution failures
2. **Make failures diagnosable without crashing**: degrade gracefully; still capture diagnostics.
3. **Prevent spam**: dedupe, per-session budgets, deterministic sampling.
4. **Respect privacy and security**: minimize PII and never log secrets.

### Non-goals
- Logging every UI interaction.
- Shipping raw schema JSON or user-entered text to telemetry.
- Using telemetry as an authorization/audit source.

## 4) Design principles

1. **Structured first**: diagnostics are structured events, not strings.
2. **Stable fingerprints**: every repeatable issue has a consistent fingerprint.
3. **Budgets over best-effort**: cap events per session; count suppressions.
4. **Redaction by default**: PII never enters event payloads.
5. **Separation of concerns**:
   - UI messaging is for users (short, friendly, localized)
   - diagnostics are for developers/support (structured, precise)
6. **Deterministic sampling**: avoid random sampling that hides “always-on” failures.
7. **Testable contracts**: event schema and key capture points have unit tests.

## 5) Event taxonomy

Every event MUST have:

- `eventName` (namespaced)
- `severity` (`debug|info|warn|error|fatal`)
- `kind` (`diagnostic|metric|trace`)
- `timestamp` (UTC)
- `fingerprint` (stable string)
- `context` (standard runtime context; see §6)
- `payload` (event-specific; must follow PII rules)

### 5.1 Severity meaning
- `debug`: dev-only details; typically disabled in prod.
- `info`: notable lifecycle state (e.g., schema activated).
- `warn`: recoverable abnormal conditions.
- `error`: operation failed, but app recovered.
- `fatal`: crash / unrecoverable error boundary.

### 5.2 Required diagnostic categories
Use this consistent naming hierarchy:

- `runtime.schema.*` — fetch/cache/compat/parse/validate/refs
- `runtime.render.*` — widget build failures, unsupported nodes
- `runtime.action.*` — resolve/dispatch/unsupported action types
- `runtime.visibility.*` — visibleWhen evaluation issues
- `runtime.perf.*` — latency and frame/perf indicators
- `app.lifecycle.*` — app start, session start, background/foreground
- `backend.request.*` — server-side request logs and failures

Additional standardized events (implemented in Flutter runtime + customer app):
- `runtime.screen_load.summary` — one event per screen load attempt with stable payload keys (see `ScreenLoadSummaryKeys` in `packages/flutter_runtime`)
- Schema fallback ladder events:
  - `runtime.schema.ladder.source_used`
  - `runtime.schema.ladder.fallback`
  - `runtime.schema.ladder.pin_cleared`
  - `runtime.schema.ladder.pin_promoted`
- Theme fallback ladder events:
  - `runtime.theme.ladder.source_used`
  - `runtime.theme.ladder.fallback_to_local`

## 6) Standard runtime context (required fields)

### 6.1 Client context
These fields should be attached to every client diagnostic event:

- `app`:
  - `appId` (e.g., `customer-app`)
  - `buildFlavor` (`dev|staging|prod`)
  - `version` (semantic version)
  - `buildNumber`
- `device`:
  - `platform` (`ios|android|web|desktop`)
  - `osVersion`
  - `model` (coarse; optional)
- `session`:
  - `sessionId` (random UUID per app launch)
  - `installId` (stable random UUID; rotated on reinstall)
  - `sampleBucket` (0-99 derived deterministically from installId/sessionId)
- `actor` (minimal):
  - `role` (`customer|provider|dispatcher|admin|unknown`)
  - `userIdHash` (hash; optional)
  - `orgIdHash` (hash; optional)

### 6.2 Schema/runtime context
Required for schema-driven events:

- `schema`:
  - `bundleId` (or “schema id”)
  - `bundleVersion`
  - `screenId`
  - `serviceSlug`
  - `schemaFormatVersion` (e.g., `1.0`)
- `contracts`:
  - `componentContractVersions` (map: contract → version)
- `theme`:
  - `themeId`
  - `mode` (`light|dark|system`)
- `flags`:
  - `featureFlags` (list of enabled flag keys; no values)

### 6.3 Backend correlation context
Clients should attach correlation IDs to API calls:

- Request header: `x-daryeel-session-id: <sessionId>`
- Request header: `x-daryeel-schema-version: <bundleId>@<bundleVersion>` (when applicable)
- Request header: `x-request-id: <uuid>` (client-generated if backend doesn’t)

Backends MUST include `x-request-id` in responses.

Schema-service ingest (current repo):
- `POST /telemetry/diagnostics` accepts bounded batches and returns `202` with:
  - `accepted`
  - `droppedDedupe`, `droppedBudget`, `droppedInvalid`
- `GET /telemetry/diagnostics/recent` exists in development only.

## 7) PII, secrets, and redaction rules

Hard rules:

- Never emit: access tokens, refresh tokens, OTP codes, passwords, key material.
- Never emit: raw phone numbers, emails, addresses, precise GPS.
- Never emit: user-entered free text (notes, chat, medical content).
- Never emit: raw schema JSON or arbitrary props.

Allowed (with care):

- `userIdHash`, `orgIdHash` (salted, one-way)
- coarse location (e.g., city-level) if required for debugging, but prefer not.
- enumerations (role, screenId, action type)

Redaction guidance:

- Prefer structured enums and IDs over strings.
- If an event needs to reference a field, emit the **field key/name**, not its value.
- If an event needs to reference a route, emit the **route name**, not parameters.

## 8) Noise control: dedupe, budgets, sampling

### 8.1 Fingerprints
A fingerprint is a stable identifier used to dedupe repeated events.

Rules:

- Fingerprints must be **stable across sessions** for the same underlying issue.
- Fingerprints must not include PII.
- Prefer: `eventName + stable classifier fields`.

Examples:

- `runtime.action.dispatch_failed:navigate:route_missing:checkout.review`
- `runtime.schema.validation_failed:screen=home:missing_prop=title`

### 8.2 Dedupe window
Clients SHOULD dedupe identical fingerprints within a TTL window (e.g., 60s) and increment a suppressed counter.

### 8.3 Budgets
Per session, cap diagnostics volume:

- `error|fatal`: always record, but still dedupe repeats.
- `warn`: capped (e.g., 50/session).
- `info`: capped (e.g., 30/session).
- `debug`: disabled in prod unless explicitly enabled.

When budgets are exceeded:

- suppress events
- increment suppression counters so QA/support can see what was dropped.

Current repo implementation notes:
- The Flutter runtime tracks suppression counts in `RuntimeDiagnostics.stats` (by severity and fingerprint).
- A dedicated “suppressed summary” event is not emitted by default today.

Implementation note (current repo state):
- The Flutter client applies TTL-based dedupe by fingerprint and per-session budgets.
- Budget/TTL values are configurable from the immutable config snapshot telemetry section (client clamps to safe ranges).

### 8.4 Deterministic sampling
For high-volume `info`/`warn` events, use deterministic sampling:

- Compute `sampleBucket` ∈ [0, 99]
- Emit event only if bucket < threshold (e.g., 10%)

This keeps per-user behavior consistent and makes issues reproducible.

## 9) What to capture (minimum required capture points)

### 9.1 Schema fetch & cache
Events:

- `runtime.schema.fetch_started` (debug)
- `runtime.schema.fetch_succeeded` (info) — include latency + payload size
- `runtime.schema.fetch_failed` (warn/error) — include failure class
- `runtime.schema.cache_hit` / `runtime.schema.cache_miss` (info)
- `runtime.schema.activated` (info) — include active bundleId/version + screenId/serviceSlug

Also required for operational dashboards:
- `runtime.screen_load.summary` (info/metric)
  - keys include: `finalSchemaSource`, `finalSchemaReasonCode`, `schemaDocId`, `parseErrorCount`, `refErrorCount`, `usedRemoteTheme`, `finalThemeSource`, `themeDocId`, `attemptCount`, `fallbackCount`, `totalLoadMs`

### 9.2 Compatibility & validation
Events:

- `runtime.schema.compatibility_failed` (error)
  - examples: unsupported schema version, unsupported theme id, missing required component contracts
- `runtime.schema.validation_failed` (error)
  - include a bounded list of validation codes (not raw JSON)

### 9.3 Reference resolution
Events:

- `runtime.schema.ref_missing` (error) — missing fragment ID
- `runtime.schema.ref_cycle_detected` (error)

### 9.4 Rendering
Events:

- `runtime.render.unsupported_node` (warn) — node type not registered
- `runtime.render.widget_build_failed` (error) — exception boundary; include exception type only
- `runtime.render.fallback_rendered` (info/warn) — fallback reason code

### 9.5 Actions
Events:

- `runtime.action.missing_action_key` (warn)
- `runtime.action.unknown_action_id` (error)
- `runtime.action.unsupported_action_type` (error)
- `runtime.action.dispatch_failed` (error)
- `runtime.action.dispatched` (info, sampled)

Action context to include:

- `actionKey` (trigger key)
- `actionId` (if resolved)
- `actionType` (e.g., `navigate`)
- `routeName` (for navigate; no params)

### 9.6 Visibility (`visibleWhen`)
Events:

- `runtime.visibility.unknown_rule_key` (warn, sampled)
- `runtime.visibility.evaluation_failed` (warn/error)

Notes:
- Unknown `visibleWhen` keys must default to **visible** and emit `runtime.visibility.unknown_rule_key`.
- Failed evaluations (wrong types, missing build context for `expr`, exceptions) must default to **visible** and emit `runtime.visibility.evaluation_failed`.
- Payload is intentionally PII-safe and varies by failure mode; common fields include `nodeType`, `unknownKeys`, and a coarse `reason`.

### 9.7 Performance
Minimum metrics (client):

- `runtime.perf.schema_load_ms` (metric)
- `runtime.perf.screen_first_render_ms` (metric)
- `runtime.perf.action_dispatch_ms` (metric)

Avoid per-frame telemetry by default; add only when needed.

## 10) Backend logging & telemetry

### 10.1 Request logging
Backends MUST emit structured logs (JSON) with:

- `requestId` (`x-request-id`)
- `sessionId` (`x-daryeel-session-id`, if present)
- `userId` (internal id; do not log phone/email)
- `route` (FastAPI path template)
- `method`
- `statusCode`
- `latencyMs`
- `errorCode` (if failure)

### 10.2 Error taxonomy
Backends should prefer stable error codes over free-form messages.

Example:

- `AUTH_INVALID_TOKEN`
- `SCHEMA_NOT_FOUND`
- `RATE_LIMITED`
- `VALIDATION_FAILED`

### 10.3 Joining client ↔ server
With `x-request-id` and `x-daryeel-session-id`, support can correlate:

- a client diagnostic event
- the API request
- any server-side failure

## 11) Sinks and environments

### 11.1 Diagnostics sinks (conceptual)
Clients should support multiple sinks:

- `NoopDiagnosticsSink` (default in tests)
- `DebugPrintDiagnosticsSink` (dev)
- `InMemoryDiagnosticsSink` (QA/runtime inspector)
- `RemoteDiagnosticsSink` (prod; sends to backend or 3rd party)

### 11.2 Environment policy
- `dev`: allow debug events; show inspector panel.
- `staging`: production-like budgets + remote sink enabled.
- `prod`: budgets + sampling enforced; debug disabled; PII rules strict.

## 12) Runtime inspector (QA/support tooling)

A runtime inspector should be able to show:

- active schema id/version, theme, mode
- enabled flags
- service slug + screen id
- last N diagnostic events (in-memory)
- last fallback reason
- last action failure with actionKey/actionId

This is not user-facing; gate behind dev/staff build or secret gesture.

## 13) Governance and versioning

- Maintain an **event catalog** (this document is the seed).
- Event names are a compatibility surface: don’t rename casually.
- Payload changes should be additive. If breaking changes are needed, bump an `eventSchemaVersion`.

## 14) Implementation plan (fits current Daryeel2 code)

### Phase A — Flutter runtime diagnostics interface
In `packages/flutter_runtime/`:

- Introduce `RuntimeDiagnostics` (or `SchemaRuntimeDiagnostics`) with:
  - `emit(DiagnosticEvent event)`
  - built-in dedupe + budgets
- Provide sinks listed in §11.1.

### Phase B — Wire capture points
Wire emission from:

- schema load/parse/validate/ref layers (where they exist today)
- `visibleWhen` evaluation
- action resolve/dispatch helpers
- renderer fallback boundaries

### Phase C — Backend correlation
- Ensure clients send correlation headers.
- Ensure services log structured request records including `requestId`.

### Phase D — Remote ingestion
Pick one:

- send to Daryeel backend endpoint `POST /telemetry/diagnostics` (recommended long-term)
- or use a 3rd party crash/diagnostics provider

Either way, preserve the same event schema so sinks are swappable.

## 15) Concrete examples (event shapes)

### 15.1 Action dispatch failed
```json
{
  "eventSchemaVersion": 1,
  "kind": "diagnostic",
  "eventName": "runtime.action.dispatch_failed",
  "severity": "error",
  "timestamp": "2026-03-31T12:34:56.000Z",
  "fingerprint": "runtime.action.dispatch_failed:navigate:route_missing:checkout.review",
  "context": {
    "app": {"appId": "customer-app", "buildFlavor": "staging", "version": "0.1.0", "buildNumber": "42"},
    "session": {"sessionId": "...", "installId": "...", "sampleBucket": 12},
    "schema": {"bundleId": "bundle_2026_03_31", "bundleVersion": "17", "screenId": "checkout", "serviceSlug": "pharmacy", "schemaFormatVersion": "1.0"},
    "theme": {"themeId": "default", "mode": "system"},
    "flags": {"featureFlags": ["new_checkout"]}
  },
  "payload": {
    "actionKey": "continue_checkout",
    "actionId": "continue_checkout",
    "actionType": "navigate",
    "routeName": "checkout.review",
    "failure": {"code": "ROUTE_NOT_REGISTERED"}
  }
}
```

### 15.2 Schema validation failed
```json
{
  "eventSchemaVersion": 1,
  "kind": "diagnostic",
  "eventName": "runtime.schema.validation_failed",
  "severity": "error",
  "timestamp": "2026-03-31T12:35:02.000Z",
  "fingerprint": "runtime.schema.validation_failed:screen=checkout:code=MISSING_REQUIRED_PROP",
  "context": {"schema": {"bundleId": "bundle_2026_03_31", "bundleVersion": "17", "screenId": "checkout", "serviceSlug": "pharmacy", "schemaFormatVersion": "1.0"}},
  "payload": {
    "codes": [
      {"code": "MISSING_REQUIRED_PROP", "path": "root.children[2].props.title"}
    ]
  }
}
```

## 16) Quick checklist (definition of done)

A feature is “diagnostics-ready” when:

- It emits at least one structured event for failure cases.
- Failures have stable fingerprints.
- Payload contains no PII and no secrets.
- Dedupe + budgets prevent spam.
- Events include schema + screen context where applicable.
- A support engineer can answer: “what schema/flags/theme was active?”
