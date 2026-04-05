# Daryeel2 — Framework Completion Checklist (Executable)

This is the executable checklist version of `docs/framework-completion-plan.md`.

How to use this doc:
- Treat each **Milestone** as a mergeable slice.
- Keep tasks small; each checkbox should be shippable with tests.
- For each milestone, ensure:
  - framework docs stay in sync
  - tests exist (unit + at least one end-to-end demo path)
  - diagnostics are emitted for failure modes

Quick commands (current repo state):
- Schema-service tests: `cd Daryeel2/services/schema-service && . .venv/bin/activate && python -m pytest -q`
- Schema fixtures validation: `cd Daryeel2/services/schema-service && . .venv/bin/activate && python -m app.validate_all`
- Customer app tests: `cd Daryeel2/apps/customer-app && flutter test`
- Run schema-service (Docker): `cd Daryeel2 && docker compose up --build`

---

## Milestone A — Contracts + schema authoring ergonomics

### A1) Contract registry completeness
Targets:
- `Daryeel2/packages/component-contracts/`
- `Daryeel2/packages/flutter_schema_renderer/`
- `Daryeel2/docs/schema_component_contracts.md`

Checklist:
- [ ] Define/confirm contract fields: props (types/enums), defaults, slots, actions, fallbacks.
- [x] Add contract introspection API (list components + props/slots/actions).
- [ ] Ensure strict-mode behavior is consistent:
  - unknown props rejected (or dropped deterministically with a diagnostic)
  - unknown slots rejected (or ignored deterministically with a diagnostic)
  - unknown actions rejected
- [ ] Add contract fixtures for 5–10 core components.

Acceptance:
- Renderer can render those components using only contract-approved props.
- A contract change that breaks a fixture fails tests with a clear error.

### A2) Schema validation + lint workflow (CI-ready)
Targets:
- `Daryeel2/packages/schema-contracts/` (JSON Schemas)
- `Daryeel2/packages/schema_runtime_dart/` (client validation helpers)
- `Daryeel2/services/schema-service/` (optional server-side validation)

Checklist:
- [x] Add a single “validate all schema fixtures” command (Dart or Python), deterministic.
  - Current: `cd Daryeel2/services/schema-service && . .venv/bin/activate && python -m app.validate_all`
- [x] Validate:
  - schema format v1
  - contracts compliance (props/slots/actions)
  - ref resolution is acyclic and all refs exist
  - size budgets (nodes/doc size/ref depth)
- [x] Produce human-readable output (which file, which rule, where).

Acceptance:
- One command validates all fixtures and returns non-zero on error.

### A3) Authoring conventions + templates
Targets:
- `Daryeel2/docs/schema_format_v1.md`
- `Daryeel2/docs/schema_driven_ui_design.md`
- `Daryeel2/packages/schema-contracts/fixtures/` (if/when added)

Checklist:
- [ ] Document naming conventions:
  - screen ids: `product_service_purpose`
  - fragment ids: `section:<name>_v<integer>`
  - theme ids/modes
- [ ] Add templates:
  - form screen (with submit)
  - list/detail screen
  - error/empty state section

Acceptance:
- A new screen can be authored by copying a template and passing validation.

---

## Milestone B — Runtime core completeness (Flutter)

### B1) Strict parsing + compatibility enforcement
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/packages/schema_runtime_dart/`
- `Daryeel2/apps/customer-app/`

Checklist:
- [ ] Centralize “compatibility rules” and apply before render:
  - schemaVersion supported
  - contract versions (if introduced)
  - theme mode allowed
- [ ] Ensure incompatible schema:
  - never partially renders
  - falls back to bundled screen
  - emits diagnostics with enough context

Acceptance:
- Tests cover incompatible schema and confirm safe fallback.

### B2) Ref resolution robustness
Targets:
- `Daryeel2/packages/flutter_runtime/` (or shared core in `schema_runtime_dart`)

Checklist:
- [ ] Cycle detection for fragments.
- [ ] Bounded depth and max fragment count limits.
- [ ] Deterministic resolution (no nondeterministic ordering).

Acceptance:
- A cycle produces one diagnostic event and a safe fallback.

### B3) Action engine expansion (bounded)
Targets:
- `Daryeel2/packages/flutter_runtime/` (action dispatcher)
- `Daryeel2/docs/schema_format_v1.md` (action definitions)

Checklist:
- [x] Add `submit_form` action type (bounded contract).
- [x] Add minimal “action failure” diagnostics payload convention.
- [x] Guard unknown actions (no-op + diagnostic).

Acceptance:
- A schema-authored form screen can submit via action id.

### B4) Form + binding engine (Phase 2)
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/packages/flutter_components/` (field widgets)

Checklist:
- [x] Form state model:
  - values
  - validation errors
  - submit state
- [ ] Add touched/dirty tracking.
- [x] Bounded binding syntax:
  - parsed from a simple string: `<formId>.<fieldKey>` (also accepts `:` and `/` separators)
  - fail-closed parsing
  - form values are sanitized to primitives (string/num/bool)
- [x] Built-in validators (bounded): required, min/max length, regex (optional).
- [x] Wire `SchemaFormScope` into the customer-app runtime view so `submit_form` can read and validate live field values.

Acceptance:
- “Request form” demo screen is schema-driven end-to-end with diagnostics.

---

## Milestone C — Delivery service hardening (schema-service)

### C1) Caching invariants enforced by tests
Targets:
- `Daryeel2/services/schema-service/app/main.py`
- `Daryeel2/services/schema-service/tests/`
- `Daryeel2/docs/caching-framework.md`

Checklist:
- [x] For bootstrap endpoints, tests assert:
  - `ETag` present
  - supports `If-None-Match` → `304`
  - short TTL cache-control
- [x] For immutable-by-id endpoints (config snapshots today), tests assert:
  - long TTL + `immutable`

Acceptance:
- Cache headers are stable and intentional.

### C2) Immutable-by-id strategy for schema/theme
Targets:
- `Daryeel2/services/schema-service/app/registry.py`
- `Daryeel2/services/schema-service/app/theme_registry.py`
- `Daryeel2/docs/caching-framework.md`

Checklist:
- [x] Introduce versioned/immutable IDs for:
  - screens
  - fragments
  - themes
- [x] Keep current URLs as selectors that map to immutable IDs.
- [ ] Add rollback workflow: “change mapping” without client release.

Acceptance:
- A screen/theme can be pinned to a versioned URL.

### C3) Dev-only operational endpoints
Targets:
- `Daryeel2/services/schema-service/app/main.py`

Checklist:
- [x] Add dev-only endpoint for “current mappings for product X”.
- [x] Add dev-only endpoint for “recent validation/serving errors”.

Acceptance:
- Support can quickly answer: what did we serve?

---

## Milestone D — Security model for schema-driven UI

### D1) Threat model + hard limits
Targets:
- `Daryeel2/services/schema-service/`
- `Daryeel2/packages/schema_runtime_dart/`
- `Daryeel2/docs/security-plan.md` (or create Daryeel2-specific security doc)

Checklist:
- [x] Add size budgets (server + client):
  - max schema doc size
  - max nodes
  - max ref depth
- [x] Ensure schema input is treated as untrusted everywhere.

Acceptance:
- Oversized inputs fail safely with diagnostics.

### D2) Permission guard engine (client)
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/docs/schema_driven_ui_design.md`

Checklist:
- [ ] Define minimal local permission context (role/capabilities).
- [ ] Extend `visibleWhen` in a bounded way:
  - `featureFlag` (already)
  - `role` (optional)
  - `capability` (optional)

Acceptance:
- Sensitive actions are hidden when clearly disallowed.

---

## Milestone E — Observability + support tooling

### E1) Correlation everywhere
Targets:
- `Daryeel2/apps/customer-app/`
- `Daryeel2/services/api/`
- `Daryeel2/services/schema-service/`
- `Daryeel2/docs/diagnostics-and-telemetry.md`

Checklist:
- [x] Clients attach correlation headers to backend calls:
  - `x-request-id`
  - `x-daryeel-session-id`
  - `x-daryeel-schema-version` (when applicable)
  - `x-daryeel-config-snapshot` (when available)
- [x] Backends echo `x-request-id` and emit structured access logs with the correlation context.

Acceptance:
- A single log trail ties client screen load → schema-service → ingest.

### E2) Runtime inspector (debug-only)
Targets:
- `Daryeel2/apps/customer-app/`

Checklist:
- [x] Add a debug-only view that displays:
  - active bootstrap + snapshot ids
  - active schema bundle id/version
  - active theme id/mode
  - last N diagnostics (local memory sink)

Acceptance:
- QA can screenshot “exact runtime state”.

---

## Milestone F — Dynamic data (fetch, render, filter, edit, save)

Goal:
- Support schema-authored catalog/search/list/detail and edit flows without building screen-specific native pages.
- Keep the native work bounded: one query engine, one list engine, one mutation engine, plus a small set of components.

Non-goals:
- No general-purpose expression language.
- No schema-defined arbitrary networking (must be bounded/allowlisted).

### F1) QuerySpec contract (bounded)
Targets:
- `Daryeel2/docs/schema_format_v1.md`
- `Daryeel2/packages/schema_runtime_dart/`

Checklist:
- [ ] Define `QuerySpec` schema shape (bounded):
  - `id`
  - `endpointId` or `path` (no arbitrary full URL by default)
  - `method` (start with `GET`)
  - `params` bindings (read from `$state`, `$route`)
  - `cachePolicy` (e.g., `ttlMs`, `staleWhileRevalidateMs`)
  - optional `pagination` (cursor/offset)
- [ ] Define a bounded binding vocabulary needed for data:
  - `$state.<key>`
  - `$route.<param>`
  - `$query.<id>.data` / `.error` / `.meta`
  - `$item.<field>` in repeated templates

Acceptance:
- A schema can declare at least one query without enabling arbitrary scripting.

### F2) Query engine (Flutter runtime)
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/packages/flutter_daryeel_client_app/` (preferred shared shell integration)

Checklist:
- [ ] Implement a single query executor that:
  - injects auth headers and correlation ids
  - uses `API_BASE_URL` and an allowlisted `endpointId -> path` mapping
  - normalizes responses into `AsyncValue`-like states
- [ ] Implement query caching keyed by:
  - endpoint + params
  - auth/account context
  - schema screen id + query id (for debugging)
- [ ] Add retry policy (bounded) and explicit timeout defaults.

Acceptance:
- A query can be executed from a schema screen and produces deterministic loading/data/error rendering.

### F3) Async rendering primitives
Targets:
- `Daryeel2/packages/flutter_schema_renderer/`
- `Daryeel2/packages/flutter_components/`

Checklist:
- [ ] Add a `QueryView`-style component (or equivalent) that renders:
  - `loadingSlot`
  - `errorSlot`
  - `emptySlot`
  - `dataSlot`
- [ ] Ensure error presentation is consistent and emits diagnostics.

Acceptance:
- Every query-backed screen has an explicit and testable empty/error/loading UX.

### F4) Repeat/List templating
Targets:
- `Daryeel2/packages/flutter_schema_renderer/`
- `Daryeel2/packages/flutter_components/`

Checklist:
- [x] Add a bounded list component that:
  - iterates `items` from a query result (array)
  - renders an `itemTemplate` with `$item` binding scope
  - uses `ListView.builder` (or slivers) for performance
- [x] Define stable keys for items (e.g., `item.id`) to avoid UI churn.

Acceptance:
- A catalog-like list screen can be authored as “query + itemTemplate” in schema.

### F5) Filtering + search (state -> query)
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/packages/flutter_components/`

Checklist:
- [x] Add a screen-scoped state store engine that:
  - supports `set_state` action and/or two-way component bindings
  - supports defaults from schema
- [x] Add debounced search input behavior (bounded) so typing doesn’t spam API.
- [x] Ensure queries re-run when their dependent `$state` keys change.

Acceptance:
- Search + filter controls update the list results without a native, screen-specific controller.

### F6) Pagination (infinite scroll on mobile)
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/packages/flutter_components/`

Checklist:
- [ ] Implement infinite scroll UX (mobile default) backed by pagination:
  - prefer cursor pagination (`nextCursor`) as the default contract
  - allow offset pagination only if/when needed later
  - query can request next page
  - list triggers pagination on scroll threshold
  - handles “no more results”
- [ ] Ensure filter/search changes reset pagination deterministically (clear items + cursor, refetch page 1).
- [ ] Emit diagnostics for pagination failures without breaking the already-rendered list.

Acceptance:
- A product/provider list can grow beyond one page reliably.

### F7) Mutations (edit + save)
Targets:
- `Daryeel2/packages/flutter_runtime/`
- `Daryeel2/docs/schema_format_v1.md`

Checklist:
- [ ] Define a bounded `MutationSpec` (start with `POST/PUT/PATCH`) with payload bindings from `$state`/`$form`.
- [ ] Implement mutation execution with:
  - submit-in-progress guard
  - standardized error normalization (global vs field errors)
  - success actions: toast, navigate, invalidate queries
- [ ] Add a default policy: on success, invalidate related queries by id.

Acceptance:
- A schema-authored edit form can save to the API and show field errors correctly.

### F8) Demo fixtures + tests
Targets:
- `Daryeel2/apps/customer-app/schemas/screens/`
- `Daryeel2/packages/flutter_runtime/test/` and/or `Daryeel2/packages/flutter_schema_renderer/test/`

Checklist:
- [ ] Add a demo “Service catalog” screen:
  - query `ServiceDefinition` list
  - render as ActionCards
  - filter/search
- [ ] Add a demo “Detail” screen:
  - navigates with an id param
  - fetches details by id
- [ ] Add a demo “Edit” screen:
  - fetch initial entity
  - edit fields
  - save mutation
- [ ] Tests cover:
  - binding resolution correctness
  - query caching key correctness (includes auth context)
  - mutation error mapping (field errors)

Acceptance:
- One end-to-end demo path exercises fetch -> filter -> navigate -> edit -> save.

---

## Milestone G — Performance + reliability (mobile-first)

### G1) Startup contract: LKG-first
Targets:
- `Daryeel2/apps/customer-app/`
- `Daryeel2/packages/flutter_runtime/`

Checklist:
- [ ] Guarantee first render never blocks on network.
- [ ] Throttle refresh on foreground.
- [ ] Persist LKG for:
  - config snapshot (already)
  - schema screen/fragments (now cached; ensure policy)
  - theme docs (once client loads them)

Acceptance:
- App boots offline reliably.

### G2) Cache correctness and corruption handling
Targets:
- `Daryeel2/apps/customer-app/lib/src/cache/http_json_cache.dart`

Checklist:
- [x] Add tests for:
  - cached body + `304` reuse
  - corrupt JSON ignored safely
  - cache key stability

Acceptance:
- No crashes due to cache corruption.

---

## Cross-cutting (do continuously)

- [ ] Keep docs and code in sync (update the relevant doc whenever behavior changes).
- [ ] Prefer shared engines in `schema_runtime_*` packages over duplicating logic in apps.
- [ ] No raw style blobs; use tokens/variants/overrides only.
- [ ] No general-purpose scripting/expression languages.

---

## “Framework complete” exit checklist

- [x] A schema-authored form flow works end-to-end in the customer app.
- [ ] A schema-authored query/list/detail flow works end-to-end (including filtering).
- [ ] A schema-authored edit/save flow works end-to-end (including field error mapping).
- [ ] Schema/theme/config can be updated and rolled back without app release.
- [ ] Runtime never crashes on invalid remote input; always falls back safely.
- [ ] There is a debug inspector and a practical on-call playbook.
- [ ] Validation/linting is automated and CI-ready.
- [x] Performance budgets exist and are enforced.
