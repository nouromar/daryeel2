# Daryeel2 — Claude Code Instructions

This file is auto-loaded by Claude Code. The same rules govern Copilot — keep them in sync via the imports below rather than duplicating.

## Read first (imported)

@.github/copilot-instructions.md
@docs/ai-grounding.md

## Repo at a glance

Schema-driven UI framework. Flutter monorepo + backend services.

- `apps/` — thin Flutter wrappers (`customer-app`, `provider-app`, `admin-ops-web`)
- `packages/` — shared runtime + components (treat as stable; do not edit without explicit approval)
- `services/` — backend (`api`, `schema-service`)
- `docs/` — architecture, RFCs, skills

Screens live as JSON: `apps/*/schemas/screens/*.screen.json` and fragments in `apps/*/schemas/fragments/`. They are rendered at runtime by the Flutter widget registry. Content changes ship without code deploys.

## Hard rules (summary — full versions in the imports above)

- **Do not edit `packages/*`** without explicit user approval in the current conversation. If a framework change seems needed, STOP and propose 2–3 options including an app-only fallback.
- Keep `apps/*` thin: branding, identifiers, fallback bundles, theme resolver, registries, compatibility rules. Product-specific code goes under `apps/<app>/lib/src/services/<service>/...`.
- Backend routes are grouped per product service with prefix `/v1/<service>/...`.
- Don't commit generated artifacts (`build/`, `.dart_tool/`, `ios/Pods/`, `*/Flutter/ephemeral/`, `android/local.properties`, `*.iml`).

## Building schema UI

When asked to build or modify a screen/fragment, invoke `/schema-screen` first — it loads the full widget catalogue, expression syntax, action types, and the "when to add a new widget vs compose" decision tree.

Key locations (also in memory):
- Core widgets + schema components: `packages/flutter_components/lib/src/`
- Customer app registry: `apps/customer-app/lib/src/ui/customer_component_registry.dart`
- Customer app action dispatcher: `apps/customer-app/lib/src/actions/customer_action_dispatcher.dart`

## Validation (run before declaring work done)

For Flutter changes, from the affected app or package directory:

```
flutter analyze
flutter test
```

Run via `/run-checks` to do this automatically against changed paths.

## Project slash commands

- `/run-checks` — `flutter analyze` + `flutter test` for apps/packages with uncommitted changes
- `/before-merge` — pre-merge checklist (analyze, tests, packages/* guardrail, generated artifacts)
- `/where <topic>` — quick "where do I change X?" answer from `docs/ai-grounding.md`
- `/schema-screen` — guided schema screen authoring (user-level skill; loads widget catalogue)

## Local services

Schema service runs on port 8011 via `docker compose up --build` from the repo root. With Redis caching: `SCHEMA_SERVICE_REDIS_URL=redis://redis:6379/0 docker compose --profile redis up --build`.
