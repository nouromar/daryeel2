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
- [docs/02-backend-design-reusable-entities.md](02-backend-design-reusable-entities.md)
- [docs/03-ui-design-and-component-inventory.md](03-ui-design-and-component-inventory.md)

Schema-driven UI runtime:
- [docs/schema_driven_ui_design.md](schema_driven_ui_design.md)
- [docs/schema_format_v1.md](schema_format_v1.md)
- [docs/schema_runtime_flutter_mapping.md](schema_runtime_flutter_mapping.md)
- [docs/schema_client_runtime_architecture.md](schema_client_runtime_architecture.md)
- [docs/schema_component_contracts.md](schema_component_contracts.md)

Compatibility/fallback and rollout:
- [docs/schema_compatibility_and_fallback_rfc.md](schema_compatibility_and_fallback_rfc.md)

Config and caching:
- [docs/config-service.md](config-service.md)
- [docs/caching-framework.md](caching-framework.md)

Diagnostics:
- [docs/diagnostics-and-telemetry.md](diagnostics-and-telemetry.md)

Planning/checklists:
- [docs/framework-completion-checklist.md](framework-completion-checklist.md)
- [docs/framework-completion-plan.md](framework-completion-plan.md)
- [docs/framework-next-pr-slices.md](framework-next-pr-slices.md)

## Flutter client architecture (current state)

### Shared client shell

Primary reuse point:
- `packages/flutter_daryeel_client_app/`

Responsibilities (high level):
- Owns the schema-driven client runtime (bootstrap + config snapshot + schema/theme loading).
- Provides HTTP caching (ETag/304) and “pinning ladder” behavior (immutable docId pin).
- Emits diagnostics events (PII-safe) and provides a debug Runtime Inspector screen in debug builds.

### Thin app wrappers

Each app under `apps/*` should be thin:
- Provide branding/title.
- Provide product/app identifiers.
- Provide bundled fallback screen + bundled fragments.
- Provide a theme resolver (local fallback) and a widget registry.
- Provide a schema compatibility policy.

See:
- `apps/customer-app/lib/src/app/customer_app.dart`
- `apps/provider-app/lib/src/app/provider_app.dart`

## “Where do I change X?”

- Add/modify schema-to-widget mapping: start with `packages/flutter_schema_renderer/` and the app registry builders under `apps/*/lib/src/ui/*_component_registry.dart`.
- Change runtime loading behavior (bootstrap/config/schema/theme ladders, caching, pins): `packages/flutter_daryeel_client_app/`.
- Update schema format: `packages/schema-contracts/` (examples/schemas) + `docs/schema_format_v1.md`.
- Update server-side schema service: `services/schema-service/`.

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
- App-specific branding/config/fallback bundles/fragments/themes/compat policy: `apps/customer-app/lib/src/` or `apps/provider-app/lib/src/`.
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
