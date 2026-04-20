---
description: "Copilot workspace instructions for the Daryeel2 monorepo (schema-driven UI framework + services)."
---

Read [docs/ai-grounding.md](../docs/ai-grounding.md) first for the repo mental model and canonical doc links.

When building or reviewing a schema-driven UI screen, also read [docs/schema-screen-authoring.md](../docs/schema-screen-authoring.md)
for the full widget catalogue, design principles, expression syntax, action types, and the decision
tree for when to add a new widget vs composing with existing ones.

Key rules:
- Prefer using the shared Flutter client runtime/framework in `packages/*` over copying runtime logic into apps.
- The runtime/framework under `packages/*` is nearing majority/stability: do NOT change anything under `packages/*` unless we explicitly discuss it first and you get explicit permission to proceed.
- If we’ve explicitly agreed on a design/architecture in this conversation, do NOT change or replace that design without first:
	- Asking the user to confirm they want to change it, and
	- Presenting 2–3 concrete alternatives (including, when relevant, a “keep the design and change contracts/validation” option).
- Keep Flutter apps under `apps/*` as thin wrappers: only branding + product/appId + fallback schema/fragments + local theme resolver + widget registry + compatibility rules.
- Product-service specific client code lives in the app, grouped by service:
	- Put schemas, UI components, and widgets that are specific to one product service (e.g. pharmacy, shopping) under the product app in a service-named folder.
	- Suggested default:
		- `apps/customer-app/lib/src/services/<service>/...`
		- `apps/customer-app/schemas/services/<service>/{screens,fragments}/...`
	- Keep cross-service or framework-level logic in `packages/*`.

- App-first changes for service features (framework changes require explicit permission):
	- When implementing a product service feature, prefer changes in `apps/*` (and the service folder) only.
	- Implement product service features using the existing runtime/framework capabilities (schema-driven UI, existing components/actions/state) whenever possible.
	- Do NOT modify `packages/*` as part of a service/feature request unless the user explicitly approves it in this conversation.
	- If a framework change seems necessary, STOP and propose options before making edits in `packages/*`:
		- Include: why it’s needed, exact files to change, and any tests to update/add.
		- Provide a “use existing runtime” option and an app-only fallback option when feasible.
	- Only apply the framework change after explicit user approval.
- Backend API routes must be grouped by product service with a stable path prefix:
	- In `services/api`, each product service must have its own route prefix and router/module.
	- Use the short prefix convention: `/v1/<service>/...`.
- Schema rendering lives in `packages/flutter_schema_renderer/`; app registries are `apps/*/lib/src/ui/*_component_registry.dart`.
- Don’t add or commit generated artifacts: `build/`, `.dart_tool/`, `ios/Pods/`, `*/Flutter/ephemeral/`, `android/local.properties`, IDE `.iml`.

Validation expectations:
- For Flutter app changes, run in that app folder: `flutter test` and `flutter analyze`.
- For shared package changes, add/update focused tests and run package tests when present.

Style/constraints:
- Make minimal, targeted changes; avoid unrelated refactors.
- Preserve public APIs unless the task requires breaking changes.
