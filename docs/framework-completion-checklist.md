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
- [ ] Add a single “validate all schema fixtures” command (Dart or Python), deterministic.
  - Current: `cd Daryeel2/services/schema-service && . .venv/bin/activate && python -m app.validate_all`
- [ ] Validate:
  - schema format v1
  - contracts compliance (props/slots/actions)
  - ref resolution is acyclic and all refs exist
  - size budgets (nodes/doc size/ref depth)
- [ ] Produce human-readable output (which file, which rule, where).

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
- [ ] For bootstrap endpoints, tests assert:
  - `ETag` present
  - supports `If-None-Match` → `304`
  - short TTL cache-control
- [ ] For immutable-by-id endpoints (config snapshots today), tests assert:
  - long TTL + `immutable`

Acceptance:
- Cache headers are stable and intentional.

### C2) Immutable-by-id strategy for schema/theme
Targets:
- `Daryeel2/services/schema-service/app/registry.py`
- `Daryeel2/services/schema-service/app/theme_registry.py`
- `Daryeel2/docs/caching-framework.md`

Checklist:
- [ ] Introduce versioned/immutable IDs for:
  - screens
  - fragments
  - themes
- [ ] Keep current URLs as selectors that map to immutable IDs.
- [ ] Add rollback workflow: “change mapping” without client release.

Acceptance:
- A screen/theme can be pinned to a versioned URL.

### C3) Dev-only operational endpoints
Targets:
- `Daryeel2/services/schema-service/app/main.py`

Checklist:
- [ ] Add dev-only endpoint for “current mappings for product X”.
- [ ] Add dev-only endpoint for “recent validation/serving errors”.

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
- `Daryeel2/services/schema-service/`
- `Daryeel2/docs/diagnostics-and-telemetry.md`

Checklist:
- [ ] Ensure every fetch/action/validation event includes:
  - request id
  - schema id/version
  - config snapshot id
  - theme id/mode

Acceptance:
- A single log trail ties client screen load → schema-service → ingest.

### E2) Runtime inspector (debug-only)
Targets:
- `Daryeel2/apps/customer-app/`

Checklist:
- [ ] Add a debug-only view that displays:
  - active bootstrap + snapshot ids
  - active schema bundle id/version
  - active theme id/mode
  - last N diagnostics (local memory sink)

Acceptance:
- QA can screenshot “exact runtime state”.

---

## Milestone F — Performance + reliability (mobile-first)

### F1) Startup contract: LKG-first
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

### F2) Cache correctness and corruption handling
Targets:
- `Daryeel2/apps/customer-app/lib/src/cache/http_json_cache.dart`

Checklist:
- [ ] Add tests for:
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

- [ ] A schema-authored form flow works end-to-end in the customer app.
- [ ] Schema/theme/config can be updated and rolled back without app release.
- [ ] Runtime never crashes on invalid remote input; always falls back safely.
- [ ] There is a debug inspector and a practical on-call playbook.
- [ ] Validation/linting is automated and CI-ready.
- [ ] Performance budgets exist and are enforced.
