# Daryeel2 — AI Grounding

Fast repo mental model + canonical links. Keep behavior rules and guardrails in `CLAUDE.md` and `.github/copilot-instructions.md`; this doc should stay focused on architecture and navigation.

## Quick orientation

- `apps/` — thin product wrappers (`customer-app`, `provider-app`, `admin-ops-web`)
- `packages/` — shared Flutter runtime, renderer, components, contracts
- `services/` — backend services (`api`, `schema-service`)
- `docs/` — architecture, design docs, skills, checklists

Screens are JSON under `apps/*/schemas/**` and are rendered at runtime through app registries plus the shared schema renderer.

## Start here

Architecture and structure:
- [docs/project-structure.md](project-structure.md)
- [docs/01-design-philosophy.md](01-design-philosophy.md)

Schema-driven UI runtime:
- [docs/skills/README.md](skills/README.md) ← repo-specific playbooks
- [docs/skills/schema-screen.md](skills/schema-screen.md) ← start here for screen work
- [docs/skills/expression-engine.md](skills/expression-engine.md) ← start here for expressions
- [docs/schema-screen-authoring.md](schema-screen-authoring.md)
- [docs/schema_driven_ui_design.md](schema_driven_ui_design.md)
- [docs/schema_format_v1.md](schema_format_v1.md)
- [docs/schema_runtime_flutter_mapping.md](schema_runtime_flutter_mapping.md)
- [docs/schema_client_runtime_architecture.md](schema_client_runtime_architecture.md)
- [docs/schema_component_contracts.md](schema_component_contracts.md)
- [docs/theming.md](theming.md)

Platform/runtime support:
- [docs/schema_compatibility_and_fallback_rfc.md](schema_compatibility_and_fallback_rfc.md)
- [docs/config-service.md](config-service.md)
- [docs/caching-framework.md](caching-framework.md)
- [docs/diagnostics-and-telemetry.md](diagnostics-and-telemetry.md)

## Current architecture

### Shared client shell

Primary shared app shell:
- `packages/flutter_daryeel_client_app/`

Supporting shared packages:
- `packages/flutter_runtime/` — state, expressions, visibility, action primitives
- `packages/flutter_schema_renderer/` — schema-to-widget renderer and registries
- `packages/flutter_components/` — shared schema components/widgets
- `packages/schema_runtime_dart/` — schema core/parsing parity

High-level split:
- **Shared runtime in `packages/*`** owns bootstrap, schema/theme loading, caching, compatibility, diagnostics, and core shared actions/components.
- **Product extensions in `apps/*`** own service-specific schemas, widgets, actions, and contracts.

Reference app entry points:
- `apps/customer-app/lib/src/app/customer_app.dart`
- `apps/provider-app/lib/src/app/provider_app.dart`

### Validation model

`services/schema-service/` is the canonical schema validator/delivery layer.

- Shared component contracts: `packages/component-contracts/`
- Core runtime action contracts: built into schema-service
- App-scoped contracts: `apps/<product>/contracts/{components,actions}/`
- Contract merge point: `services/schema-service/app/contract_catalog.py`

## Where do I change X?

| Task | Start here |
| --- | --- |
| Add or edit screens/fragments | `apps/*/schemas/**` |
| Add app-specific service UI/widgets | `apps/*/lib/src/services/**` |
| Wire app widget registry | `apps/*/lib/src/ui/*_component_registry.dart` |
| Add app-specific actions | `apps/*/lib/src/actions/**` |
| Add app-specific contracts | `apps/*/contracts/{components,actions}/` |
| Change schema renderer behavior | `packages/flutter_schema_renderer/` |
| Change shared runtime/bootstrap/caching/loading | `packages/flutter_daryeel_client_app/` |
| Change shared state/expression/action primitives | `packages/flutter_runtime/` |
| Change shared schema components | `packages/flutter_components/` |
| Change themes | `apps/*/lib/src/ui/*_theme.dart`, `packages/flutter_themes/`, `packages/theme-contracts/` |
| Change schema format/contracts | `packages/schema-contracts/`, `docs/schema_format_v1.md` |
| Change schema-service validation/delivery | `services/schema-service/` |
| Change product APIs | `services/api/app/routers/` |

## Local references

- Flutter app commands: run from the affected app/package; see `CLAUDE.md` for default validation expectations
- Schema service setup: [services/schema-service/README.md](../services/schema-service/README.md)

## Keep this doc small

When architecture changes:
- update the repo map
- update the canonical links
- update the “Where do I change X?” table
- link out instead of copying detailed rules or long explanations

## Optional background

Useful for deeper backend/product work, but not day-to-day starting points:
- [docs/02-backend-design-reusable-entities.md](02-backend-design-reusable-entities.md)
- [docs/03-ui-design-and-component-inventory.md](03-ui-design-and-component-inventory.md)
