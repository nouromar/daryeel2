# Framework next PR slices (B3/B4/D1/E2/F2)

This document turns the remaining checklist items into **mergeable PR slices**.

Rules for every PR:
- Keep the slice shippable.
- Add/adjust tests that fail before the change and pass after.
- Emit diagnostics for every new failure mode.
- Prefer shared engines in `packages/` over app-local implementations.

---

## B3 — Action engine expansion (bounded)

### PR B3.1 — `open_url` handler (safe, bounded)
Status: DONE (implemented)

Implemented in:
- `packages/flutter_runtime/lib/src/actions/open_url_dispatcher.dart`
- `packages/flutter_runtime/lib/src/actions/action_policy.dart` (action allowlist + `UriPolicy`)
- `apps/customer-app/lib/src/actions/url_launcher_open_url_handler.dart` (app-layer implementation)
- `apps/customer-app/lib/src/runtime/customer_runtime_policy_provider.dart` (restrictive allowlist + host policy)

---

### PR B3.2 — `track_event` handler (no PII, bounded)
Status: DONE (implemented)

Implemented in:
- `packages/flutter_runtime/lib/src/actions/track_event_dispatcher.dart`
- `packages/flutter_runtime/lib/src/actions/action_policy.dart`
- `apps/customer-app/lib/src/actions/diagnostics_track_event_handler.dart` (PII-safe metric emission)

---

### PR B3.3 — `submit_form` contract + dispatcher interface (no network yet)
Status: DONE (implemented)

Implemented in:
- `packages/flutter_runtime/lib/src/actions/submit_form_dispatcher.dart`
- `packages/flutter_runtime/lib/src/forms/schema_form_store.dart` (form state + validation rules)
- `packages/flutter_runtime/test/submit_form_dispatcher_test.dart`
- `apps/customer-app/lib/src/actions/diagnostics_submit_form_handler.dart` (non-networking placeholder)

---

## B4 — Form + binding engine (Phase 2)

### PR B4.1 — Form state engine (local-only)
Status: DONE (implemented)

Implemented in:
- `packages/flutter_runtime/lib/src/forms/schema_form_store.dart` (`SchemaFormStore`, `SchemaFormScope`, `SchemaFieldBinding`)

---

### PR B4.2 — Built-in validators (required + length)
Status: DONE (implemented)

Implemented in:
- `packages/flutter_runtime/lib/src/forms/schema_form_store.dart` (`SchemaFieldValidationRules`)
- `packages/flutter_runtime/test/submit_form_dispatcher_test.dart` (validation gating behavior)

---

### PR B4.3 — `submit_form` end-to-end (fake backend)
Status: DONE (implemented)

Goal:
- The customer app can run a full schema-authored form submit flow.

Implemented in:
- `apps/customer-app/lib/src/app/customer_app.dart` (wires `SchemaFormScope` + full action dispatcher)
- `apps/customer-app/lib/src/ui/customer_component_registry.dart` (`TextInput` bound to `SchemaFormStore` via `bind`)
- `apps/customer-app/test/e2e_form_flow_test.dart` (widget test: bind → validate → submit + PII-safe diagnostics)

Acceptance:
- A schema-authored form can bind values, validate, and submit end-to-end.

---

## D1 — Threat model + hard limits

### PR D1.1 — Add security plan doc + budgets table
Status: DONE (implemented)

Goal:
- Make budgets explicit and reviewable.

Changes:
- Create `docs/security-plan.md` with:
  - threat model summary
  - budgets table (doc bytes, nodes, refs, depth, fragments)
  - policy statements (treat schema/theme as untrusted input)

Tests:
- Doc-only PR (no tests), but must reference existing budget constants and where enforced.

Acceptance:
- Budget values are defined in one place and referenced by code/docs.

Implemented in:
- `docs/security-plan.md`
- `packages/flutter_runtime/lib/src/security/security_budgets.dart`

---

### PR D1.2 — Client-side doc-size/node-count budgeting
Status: DONE (implemented)

Goal:
- Prevent DoS by oversized remote documents even before parse/ref resolution.

Changes:
- Add a pre-parse budget check in `flutter_runtime` load pipeline:
  - max UTF-8 bytes of JSON body
  - optional max node count (post-parse)
- Emit diagnostics on rejection with reason codes.

Tests:
- `packages/flutter_runtime/test/schema_budgeting_test.dart`
  - oversized JSON rejected (no throw)
  - node count exceeded rejected (no throw)

Acceptance:
- Oversized inputs fail safely with diagnostics.

Implemented in:
- `packages/flutter_runtime/lib/src/schema/schema_diagnostics.dart` (`parseScreenSchemaWithDiagnostics`)
- `packages/flutter_runtime/lib/src/security/security_budgets.dart`
- `packages/flutter_runtime/test/schema_budgeting_test.dart`
- `apps/customer-app/lib/src/schema/customer_schema_loader.dart` (HTTP body size checks)

---

## E2 — Runtime inspector (debug-only)

### PR E2.1 — Debug inspector screen (read-only)
Status: DONE (implemented)

Goal:
- QA/support can capture a screenshot of exact runtime state.

Changes:
- Add a debug-only route/screen in customer-app that shows:
  - config snapshot id
  - schema docId + ladder source
  - theme docId + ladder source
  - last N diagnostics (from the in-memory sink)

Tests:
- `apps/customer-app/test/runtime_inspector_test.dart`
  - screen renders and shows required fields

Acceptance:
- A screenshot provides enough context to reproduce.

Implemented in:
- `apps/customer-app/lib/src/app/runtime_inspector_screen.dart`
- `apps/customer-app/lib/src/app/customer_app.dart` (debug-only route + in-memory diagnostics sink)
- `apps/customer-app/test/runtime_inspector_test.dart`

---

## F2 — Cache correctness and corruption handling

### PR F2.1 — Corrupt cache entry handling
Status: DONE (implemented)

Goal:
- Cache corruption never crashes the app.

Implemented in:
- `apps/customer-app/lib/src/cache/http_json_cache.dart`
  - emits `runtime.http_cache.corrupt_entry`
  - ignores corrupt cached bodies
  - returns a structured `HttpJsonCacheFailure` on network failure (no throw)

Tests:
- `apps/customer-app/test/http_json_cache_test.dart`
  - corrupt JSON ignored (network succeeds)
  - corrupt JSON + network failure returns failure (no throw)

Acceptance:
- No crashes due to corrupt cache.

---

### PR F2.2 — `304` reuse + key stability tests
Status: DONE (implemented)

Goal:
- Ensure caching invariants remain stable across refactors.

Changes:
- Add tests for:
  - cached body reused on `304`
  - stable cache keys for schema selector vs docId

Tests:
- `apps/customer-app/test/http_json_cache_test.dart`

Acceptance:
- Cache correctness is enforced by tests.

Implemented in:
- `apps/customer-app/lib/src/cache/http_json_cache.dart`
- `apps/customer-app/test/http_json_cache_test.dart`
