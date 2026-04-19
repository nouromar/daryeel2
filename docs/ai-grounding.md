# Daryeel2 — AI Grounding (Repo Overview)

This document is a single, high-signal “entry point” for Copilot/AI assistants working in this repo.

Goals:
- Provide a fast mental model of the architecture.
- Point to the canonical detailed docs (avoid duplicating them).
- Capture “where to change what” for common tasks.

Non-goals:
- Replace the detailed design docs under `docs/`.
- Describe every file/package exhaustively.

## Quick orientation

Monorepo layout:
- `apps/` — end-user Flutter apps and web apps
  - `apps/customer-app/` — thin Flutter wrapper around the shared client shell
  - `apps/provider-app/` — thin Flutter wrapper around the shared client shell
  - `apps/admin-ops-web/` — admin web app (separate stack)
- `packages/` — shared packages (Flutter + schema runtime)
- `services/` — backend services (Python/other)
- `docs/` — design docs, plans, and checklists

## Canonical docs (read these first)

Architecture and structure:
- [docs/project-structure.md](project-structure.md)
- [docs/01-design-philosophy.md](01-design-philosophy.md)

Schema-driven UI runtime:
- [docs/schema_driven_ui_design.md](schema_driven_ui_design.md)
- [docs/schema_format_v1.md](schema_format_v1.md)
- [docs/theming.md](theming.md)
- [docs/schema_runtime_flutter_mapping.md](schema_runtime_flutter_mapping.md)
- [docs/schema_client_runtime_architecture.md](schema_client_runtime_architecture.md)
- [docs/schema_component_contracts.md](schema_component_contracts.md)
- [docs/skills/schema-screen.md](skills/schema-screen.md) ← **start here when building or reviewing a screen**
- [docs/schema-screen-authoring.md](schema-screen-authoring.md)
- [docs/skills/README.md](skills/README.md) ← repo-specific “how-to” playbooks

Compatibility/fallback and rollout:
- [docs/schema_compatibility_and_fallback_rfc.md](schema_compatibility_and_fallback_rfc.md)

Config and caching:
- [docs/config-service.md](config-service.md)
- [docs/caching-framework.md](caching-framework.md)

Diagnostics:
- [docs/diagnostics-and-telemetry.md](diagnostics-and-telemetry.md)

## Flutter client architecture (current state)

### Shared client shell

Primary reuse point:
- `packages/flutter_daryeel_client_app/`

Responsibilities (high level):
- Owns the schema-driven client runtime (bootstrap + config snapshot + schema/theme loading).
- Provides HTTP caching (ETag/304) and optional “pinning ladder” behavior (immutable docId pin; schema pinning is gated by `DaryeelRuntimeConfig.enableSchemaPinning`).
- Owns the screen/theme load ladders, compatibility checks, diagnostics emission, and runtime inspector.
- Hosts the shared runtime action set and delegates product-specific actions/components to app-owned extension layers.
- Emits diagnostics events (PII-safe) and provides a debug Runtime Inspector screen in debug builds.

Key supporting shared packages:
- `packages/flutter_runtime/` — state store, expression engine, visibility evaluation, action dispatch primitives, form/query helpers.
- `packages/flutter_schema_renderer/` — schema-to-widget renderer and widget registry.
- `packages/flutter_components/` — shared schema-renderable components and their Flutter implementations.
- `packages/schema_runtime_dart/` — framework-agnostic schema core for parsing/normalization parity.

### Thin app wrappers

Each app under `apps/*` should be thin:
- Provide branding/title.
- Provide product/app identifiers.
- Provide bundled fallback screen + bundled fragments.
- Provide a theme resolver (local fallback) and a widget registry.
- Provide a schema compatibility policy.
- Provide app-owned extension packs for product-specific widgets, actions, schemas, and contracts.

See:
- `apps/customer-app/lib/src/app/customer_app.dart`
- `apps/provider-app/lib/src/app/provider_app.dart`

### Runtime extension boundary (current design)

The runtime is now explicitly two-tier:

1. Runtime-owned core in `packages/*`
  - Shared actions such as `navigate`, `open_url`, `submit_form`, `track_event`, `set_state`, and `patch_state`
  - Shared schema components and renderer behavior
  - Shared safety/diagnostics/caching logic
2. App-owned extension layer in `apps/*`
  - Product/service-specific components under `apps/*/lib/src/services/**`
  - Product-specific schema component registries under `apps/*/lib/src/ui/*_component_registry.dart`
  - Product-specific action dispatchers under `apps/*/lib/src/actions/**`
  - Product-scoped component/action contracts under `apps/*/contracts/{components,actions}/`

Current customer-app implementation:
- Component registration is layered: register shared core first, then register app-owned components so app overrides are explicit.
- Action dispatch is layered: app-owned actions are handled by a type-map dispatcher that falls back to the shared runtime dispatcher.
- Product-specific pharmacy behaviors live in `apps/customer-app/`, not in `packages/*`.

### Backend validation model (current design)

`services/schema-service/` is the canonical validator and delivery layer for schemas.

Current validation model:
- Shared component contracts come from `packages/component-contracts/`.
- Core runtime action contracts are built into the schema-service.
- App-scoped component/action contracts are loaded from `apps/<product>/contracts/components/` and `apps/<product>/contracts/actions/`.
- The schema-service merges shared + app contracts based on `product` when validating and serving contracts.

This means app-level widgets and actions are first-class and backend-validatable; they are not “invisible” extensions.

## “Where do I change X?”

- Add/modify schemas (screens/fragments): `apps/*/schemas/**`.
- Add/modify schema-to-widget mapping: start with `packages/flutter_schema_renderer/` and the app registry builders under `apps/*/lib/src/ui/*_component_registry.dart`.
- Change runtime loading behavior (bootstrap/config/schema/theme ladders, caching, pins): `packages/flutter_daryeel_client_app/`.
- Add/modify themes (canonical guide: `docs/theming.md`):
  - App resolvers: `apps/*/lib/src/ui/*_theme.dart`
  - Shared theme resolver: `packages/flutter_themes/`
  - Theme contracts/documents: `packages/theme-contracts/`
- Add/modify core schema components (when a new reusable widget is truly needed): `packages/flutter_components/lib/src/schema_components/` + `packages/flutter_components/lib/src/widgets/` + contracts in `packages/component-contracts/contracts/`.
- Add/modify app-specific widgets: `apps/*/lib/src/services/**` plus app registry wiring in `apps/*/lib/src/ui/*_component_registry.dart`.
- Add/modify app-specific actions: `apps/*/lib/src/actions/**` plus action contracts in `apps/*/contracts/actions/`.
- Add/modify app-specific contract validation: `apps/*/contracts/{components,actions}/` and `services/schema-service/app/contract_catalog.py`.
- Update schema format: `packages/schema-contracts/` (JSON schema contracts) + `docs/schema_format_v1.md`.
- Update server-side schema service: `services/schema-service/`.
- Update product APIs consumed by schemas/apps: `services/api/app/routers/` (grouped by service; stable prefix convention is `/v1/<service>/...`).

## Local development commands (common)

Flutter apps:
- From an app folder (e.g. `apps/customer-app`):
  - `flutter pub get`
  - `flutter test`
  - `flutter analyze`
  - `flutter run`

Schema service:
- See [services/schema-service/README.md](../services/schema-service/README.md)

## Guardrails for AI changes

The schema-driven runtime framework is nearing majority/stability.

Rules:
- Every code change must be accompanied by extensive unit tests.
  - Aim for 100% code coverage of the changed/added logic (especially new branches and edge cases).
- For Flutter changes, always run:
  - `flutter test`
  - `flutter analyze`
  - Fix any issues they raise before considering the change complete.
- Do not change anything under `packages/*` unless the user explicitly approves it first.
  - If a `packages/*` change seems necessary, STOP and ask for permission before editing.
- When implementing a product/service feature, prefer using existing runtime functionality (schema-driven UI, existing components/actions/state/persistence) in the app layer:
  - schema changes in `apps/*/schemas/**`
  - app wiring/widgets/components in `apps/*/lib/src/services/<service>/**`
- Only when there is no reasonable app-level or schema-level path:
  - propose 2–3 options (including “no framework change” if feasible)
  - explain the smallest `packages/*` change that would unblock it
  - wait for explicit confirmation before making that framework change.

## Copilot quick-start (how to use this repo context)

When a request comes in, follow this order:
1) Identify *what layer* the change belongs to (app wrapper vs shared shell vs schema renderer vs service).
2) For product/service features, prefer app + schema changes that use existing runtime capabilities.
3) Treat `packages/*` as stable: only propose framework changes after offering alternatives, and only edit after explicit approval.
4) Make the smallest possible change; keep apps thin wrappers.
5) Validate locally with the nearest tests/analyzer (for Flutter: `flutter test` + `flutter analyze`).

Decision hints:
- UI rendering bugs or schema widget behavior: `packages/flutter_schema_renderer/` and the app registry in `apps/*/lib/src/ui/*_component_registry.dart`.
- Runtime behavior (bootstrap/config/schema/theme ladders, caching, pinning, diagnostics, runtime inspector): `packages/flutter_daryeel_client_app/`.
- Shared expression/visibility/state/action primitives: `packages/flutter_runtime/`.
- App-specific branding/config/fallback bundles/fragments/themes/compat policy: `apps/customer-app/lib/src/` or `apps/provider-app/lib/src/`.
- App-specific schemas and service flows: `apps/*/schemas/**` and `apps/*/lib/src/services/**`.
- Schema format/contracts: `packages/schema-contracts/` plus the schema docs listed above.
- Backend schema service behavior: `services/schema-service/`.

- Prefer using shared logic in `packages/*` over copying runtime behavior into apps.
- Apps should not reintroduce “runtime/cache/actions/telemetry” duplicates; keep wrappers thin.
- Any edits under `packages/*` must be explicitly approved first.
- Don’t commit generated Flutter artifacts (`build/`, `.dart_tool/`, `ios/Pods/`, `*/Flutter/ephemeral/`, `android/local.properties`, IDE `.iml`).
- When changing runtime behavior, add/adjust focused widget tests to lock in ladder/caching/compat behavior.

## Notes for keeping this doc current

When large architectural changes land:
- Update this doc’s “Quick orientation”, “Flutter client architecture”, and “Where do I change X?” sections.
- Add links to the new canonical doc(s) rather than duplicating details here.

## Optional background (larger / sometimes outdated)

These are useful for deeper architecture work, but are often too large for day-to-day schema + app changes.

- [docs/02-backend-design-reusable-entities.md](02-backend-design-reusable-entities.md) — conceptual backend spine and entities; helpful when editing `services/api`
- [docs/03-ui-design-and-component-inventory.md](03-ui-design-and-component-inventory.md) — high-level UI philosophy; inventory sections may not match the current schema widget set
