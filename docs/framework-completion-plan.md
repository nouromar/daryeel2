# Daryeel2 — Framework Completion Plan (Schema-driven UI platform)

## 0) Goal and scope

Goal: complete the **end-to-end schema-driven framework** so product teams can build new screens/flows and ship updates safely via schema/theme/config delivery.

Execution checklist: `docs/framework-completion-checklist.md`.

This plan intentionally focuses on the **framework** (contracts, runtime, delivery, tooling, security, efficiency, usability). It explicitly defers “core business services” (requests/providers/payments/etc) until the framework is stable.

Non-goals (until framework exit criteria are met):
- building Daryeel2 domain services (Postgres/Alembic models, orchestration workflows)
- adding arbitrary expression languages or free-form scripting in schema (bounded one-line expressions are allowed in specific fields)
- allowing raw styling blobs as a primary styling mechanism

Source-of-truth constraints (must remain consistent):
- `docs/schema_format_v1.md`
- `docs/schema_component_contracts.md`
- `docs/schema_client_runtime_architecture.md`
- `docs/schema_runtime_implementation_plan.md`
- `docs/config-service.md`
- `docs/caching-framework.md`
- `docs/diagnostics-and-telemetry.md`

---

## 1) Current baseline (what already exists)

Based on repo state (Mar 2026):
- **Schema-service** is the unified runtime delivery backend:
  - config bootstrap + snapshots
  - schema bootstrap/screens/fragments
  - theme catalog + theme documents
  - ETag/304 and cache-control are in place across config/schema/theme endpoints
  - optional Redis cache backend is supported and runnable via Docker
- **Flutter runtime** supports:
  - schema rendering via component mapping
  - deterministic action dispatch (`navigate`, `open_url`, `submit_form`, `track_event`) with an allowlist policy
  - bounded expression engine for `${...}` interpolation and typed evaluation
  - `If.expr` and `visibleWhen.expr`
  - `visibleWhen` filtering (feature-flag and expression based)
  - diagnostics pipeline (dedupe/budgets, remote ingest)
  - mobile-first HTTP JSON caching with SharedPreferences + ETag/304

The framework is in a strong “Phase 1 → early Phase 2” state, but needs hardening and completion to be scalable and easy for teams to use.

---

## 2) Framework definition (what “done” means)

The framework is “complete enough to build services” when the following are true:

### 2.1 Safety and determinism
- Remote schema/theme/config cannot crash the app; failures are isolated and recoverable.
- Runtime behavior is deterministic (same inputs → same outputs).
- Schema cannot execute arbitrary logic; only approved actions and bounded rules.

### 2.2 Reusability and scalability
- Fragments (`ref`) are first-class and widely used.
- A small set of shared components covers most UI needs.
- Contracts are versioned and compatibility is enforced.

### 2.3 Security
- No auth-scoped or PII data is cached in shared caches.
- Delivery endpoints are safe for public caching; any protected endpoints are explicitly non-cacheable.
- Actions are permission-guarded in the runtime and enforced server-side later.

### 2.4 Efficiency
- Startup uses LKG caches and conditional requests.
- No per-frame network work; refresh is throttled to lifecycle events.
- Server responses are cacheable; Redis is optional.

### 2.5 Usability (for teams)
- There’s a clear authoring workflow for schema/theme:
  - validation, linting, testing, and rollout process
- There are fixtures and templates for new screens.
- Debugging is practical: “what schema/theme/config did the user have?” is easy to answer.

---

## 3) Workstreams and milestones

This plan is organized into parallel workstreams with gated milestones. Each milestone has exit criteria (tests, invariants, or observable behaviors).

### Milestone A — Contracts + schema authoring ergonomics

**A1. Contract registry completion**
- Define/confirm the canonical component contract representation (props, defaults, slots, actions, fallbacks).
- Ensure the same contract definitions are consumable by:
  - Flutter renderer
  - Angular/TS runtime (later)
  - schema-service validation (server-side) (optional but recommended)

Exit criteria:
- Contract registry can list all components and their supported props/slots/actions.
- Unknown props/actions are rejected (strict mode) and produce diagnostics.

**A2. Schema lint/validate workflow (CI-ready)**
- Add a repeatable command/tooling that validates:
  - schema JSON against schema format
  - refs resolve and are acyclic
  - component props conform to contracts
  - actions resolve to declared action types and required fields

Exit criteria:
- A single command can validate all schema fixtures in the repo.
- CI can run this command deterministically.

**A3. Authoring conventions + templates**
- Document conventions:
  - naming: screen IDs, fragment IDs, theme IDs
  - slot usage patterns
  - actionKey conventions
  - safe defaults and fallbacks
- Provide templates:
  - “form screen” template
  - “list/detail” template

Exit criteria:
- Adding a new screen involves copying a template and passing validation.

---

### Milestone B — Runtime core completeness (Flutter)

**B1. Strict parsing + compatibility enforcement**
- Strengthen compatibility checks:
  - schemaVersion support
  - required contract versions (if versioned)
  - allowed theme modes
- Ensure compatibility failures:
  - never render partially
  - produce diagnostics
  - fall back to bundled screen

Exit criteria:
- Incompatible schema never renders; app shows fallback/bundled experience.

**B2. Ref resolution robustness**
- Ensure ref resolution has:
  - cycle detection
  - bounded depth/size limits
  - deterministic merge rules

Exit criteria:
- Cycles and missing fragments produce structured diagnostics and safe fallback.

**B3. Interaction engine expansion (still bounded)**
Add a minimal, safe action set that covers real flows without over-generalizing:
- `navigate` (already)
- `submit_form`
- `open_modal` (optional; only if needed)
- `refresh_screen` (optional)

Exit criteria:
- Actions are declared centrally and resolved by ID.
- Unknown actions are rejected with diagnostics.

**B4. Form/binding engine (Phase 2 from runtime plan)**
- Introduce a form state engine:
  - registration, touched/dirty, validation results
  - submit lifecycle (pending/success/failure)
- Introduce bounded bindings:
  - e.g. `bind: { target: "form.delivery_address" }`
  - limited value types

Exit criteria:
- A full “request form” can be represented end-to-end in schema using:
  - shared fragments
  - form fields
  - submit action

---

### Milestone C — Delivery service hardening (schema-service)

**C1. Delivery invariants + caching semantics**
Confirm and test caching rules by resource class:
- bootstrap endpoints: short TTL + ETag revalidation
- immutable-by-id endpoints: long TTL + immutable

Exit criteria:
- Tests enforce `ETag` presence where required.
- Tests enforce `Cache-Control` policies.

**C2. Versioning + immutability strategy**
Move schema and theme toward immutable-by-id URLs (golden path):
- Introduce stable version identifiers for:
  - screen documents
  - fragment documents
  - theme documents
- Keep existing mutable endpoints as “bootstrap selectors” that map to immutable IDs.

Exit criteria:
- Clients can pin to a versioned immutable schema/theme doc.
- Rollbacks are possible by changing bootstrap mapping.

**C3. Operational endpoints (dev-only where appropriate)**
- Add dev-only inspection endpoints:
  - “what is the active mapping for product X?”
  - “recent schema/theme validation errors” (server side)

Exit criteria:
- Support/debug can quickly determine what was served.

---

### Milestone D — Security model for schema-driven UI

**D1. Threat model + guardrails**
Document and enforce:
- schema input is untrusted
- limit payload sizes
- limit ref resolution depth
- prohibit remote URLs for assets unless whitelisted

Exit criteria:
- Hard limits are in code and tested.

**D2. Permission guard engine (client)**
- Define a minimal permission context available on device (role/product/service/flags)
- Provide `visibleWhen` support beyond feature flags in a bounded way:
  - role checks (if already known client-side)
  - “capability” checks (locally known)

Exit criteria:
- Sensitive actions don’t appear when clearly disallowed.

**D3. Server-side enforcement boundary (future services)**
- Document the rule: UI permission gating is advisory; server is authoritative.
- Ensure delivery endpoints stay non-PII, cache-friendly.

Exit criteria:
- No user-specific data in schema/theme/config delivery.

---

### Milestone E — Observability + support tooling (end-to-end)

**E1. Correlation and fingerprints everywhere**
- Ensure every runtime request includes:
  - request id
  - config snapshot id
  - schema id/version

Exit criteria:
- A single telemetry trace can tie client screen load → schema-service request → diagnostics ingest.

**E2. Runtime inspector (dev/QA)**
- Add a debug-only screen/panel in Flutter:
  - shows active config snapshot
  - shows active schema bundle id/version
  - shows active theme id/mode
  - shows last validation/compatibility issues

Exit criteria:
- QA can capture a screenshot and engineers can reproduce.

**E3. Noise control (already started) + playbooks**
- Keep dedupe/budgets tuned from config snapshot.
- Provide playbooks:
  - “schema broke production” rollback steps
  - “theme regression” rollback steps

Exit criteria:
- A rollback can be executed without app release.

---

### Milestone F — Performance and reliability (mobile-first)

**F1. Startup behavior contract**
- Enforce:
  - LKG-first load
  - network refresh on startup/foreground (throttled)
  - never block first render on network

Exit criteria:
- Cold start is reliable offline.

**F2. Cache correctness + invalidation**
- Ensure cache keys are stable and scoped:
  - per endpoint + selector
  - no accidental collision
- Ensure “corrupt cache” is safely ignored.

Exit criteria:
- Tests cover cache fallback and corrupt cache behavior.

**F3. Payload size budgets**
- Define and enforce budgets:
  - max schema doc size
  - max fragment size
  - max number of nodes

Exit criteria:
- Oversized documents fail safely and emit diagnostics.

---

## 4) Recommended execution order (minimal critical path)

If we want the fastest path to framework completion:

1) **A2** schema lint/validate workflow (CI)
2) **B1** strict parsing + compatibility enforcement
3) **B2** ref resolution robustness
4) **F1** startup contract (LKG-first, throttled refresh)
5) **B4** form/binding engine
6) **C2** versioning + immutable-by-id strategy
7) **E2** runtime inspector
8) **D1/D2** security guardrails + permission gating

This order ensures safety, debuggability, and authoring ergonomics before adding more power.

---

## 5) Acceptance suite (what we should be able to demo)

### Demo 1 — Offline boot
- Launch customer app in airplane mode.
- App renders a valid screen from bundled/LKG schema.

### Demo 2 — Schema update via bootstrap
- Change bootstrap mapping on schema-service.
- App refreshes schema via ETag/304 and shows new screen.
- Roll back mapping; app returns to previous screen.

### Demo 3 — Fragment reuse
- Screen uses multiple refs.
- Update a fragment; dependent screens update consistently.

### Demo 4 — Form flow
- Render a form from schema.
- Fill it, validate, submit.
- Observe diagnostics events with correlation ids.

### Demo 5 — Safe failure
- Serve an invalid schema.
- App falls back (no crash), emits diagnostics, shows an explainable error state.

---

## 6) What we defer until services start

When the framework is complete, we can start Daryeel2 core services with confidence:
- introduce `services/api` implementation
- set up Postgres + Alembic + Redis as needed for domain data and workflows
- align auth/permission model end-to-end

The key benefit of completing the framework first: product UI can evolve safely and quickly while services are built.
