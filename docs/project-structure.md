# Daryeel2 Project Structure

## 1. Purpose

This document defines the recommended repository and package structure for Daryeel2.

The structure is designed for:
- schema-driven UI
- shared component contracts
- shared runtime engines
- multiple client products
- shared backend platform services
- long-term extensibility without turning the repo into one large mixed shared folder

## 2. Naming Recommendation

### 2.1 End-user app name
Recommended name:
- `customer-app`

Why:
- it matches the platform actor language already used in backend and architecture discussions
- it works across taxi, delivery, pharmacy, home visit, ambulance, and future services
- it is clearer than `client-app`
- it is less commerce-specific than `retail-app`

Avoid:
- `retail-app`
  - too commerce-oriented for healthcare and mobility services
- `client-app`
  - too ambiguous because “client” often means any frontend in engineering contexts

### 2.2 Product naming set
Recommended product/app naming set:
- `customer-app`
- `provider-app`
- `admin-ops-web`

Alternative if dispatch is even more central in naming:
- `admin-dispatch-web`

## 3. Top-Level Structure

Current repository structure (as of Apr 2026):

```text
Daryeel2/
  README.md
  docs/
  docker-compose.yml

  apps/
    customer-app/
    provider-app/
    admin-ops-web/

  services/
    api/
    schema-service/

  packages/
    domain/
    schema-contracts/
    theme-contracts/
    component-contracts/

    schema_runtime_dart/
    schema_runtime_ts/

    flutter_daryeel_client_app/
    flutter_runtime/
    flutter_components/
    flutter_themes/
    flutter_schema_renderer/
```

Optional future additions (not present in this repo snapshot):
- `services/asset-service/`
- web runtime packages for schema-driven admin
- internal tooling (`schema-preview`, `contract-linter`, etc.)

## 4. Structure Rationale

This layout treats Daryeel2 as a platform, not only as a set of separate apps.

It separates concerns into:
- `apps/` for product shells
- `services/` for deployable backend services
- `packages/` for reusable libraries and contracts
- (optional) `tooling/` for internal validation and preview tools (not present in this repo snapshot)
- (optional) `examples/` for fixtures used in testing, previewing, and documentation (not present in this repo snapshot)

## 5. Apps

```text
apps/
  customer-app/
  provider-app/
  admin-ops-web/
```

These should remain relatively thin product shells.

Responsibilities:
- bootstrap the product
- configure authentication and navigation
- host product-specific integrations
- register product-specific schema runtime pieces
- hold any non-schema fallback or transitional flows

## 6. Services

```text
services/
  api/
  schema-service/
```

### `api/`
Core business backend:
- requests
- dispatch
- providers
- payments orchestration
- ratings
- events
- auth integration

### `schema-service/`
Unified runtime delivery service (merged MVP):
- schema bundles and fragments
- schema validation (contract enforcement)
- product bootstrap config (`/config/bootstrap`)
- theme catalog + theme documents (`/themes/*`)

These concerns can be split into dedicated services later, but Daryeel2 currently keeps them together to reduce moving pieces.

Optional future additions (not present in this repo snapshot):
- `services/asset-service/` for schema-managed icons/illustrations and content assets

## 7. Shared Packages

### 7.1 Shared contracts and domain language

```text
packages/
  domain/
  schema-contracts/
  theme-contracts/
  component-contracts/
```

These packages define the common language of the platform.

### 7.2 Cross-platform schema runtime cores

To keep the schema pipeline consistent across Flutter and Web, the core schema engines should live in language-level packages that do not depend on a UI framework.

```text
packages/
  schema_runtime_dart/
  schema_runtime_ts/
```

Responsibilities (both cores):
- parse schema documents into typed models
- validate document shape and bounded semantics
- resolve refs deterministically (cycle/missing detection)
- normalize/compose trees for rendering (no raw maps in UI)
- produce structured diagnostics

Flutter and Web then build platform adapters and renderers on top.

#### `domain/`
Shared domain concepts:
- service definitions
- request statuses
- actor types
- event types
- money and tracking concepts

#### `schema-contracts/`
Schema document types:
- screen schemas
- section/fragment references
- action definitions
- binding definitions
- visibility rules

#### `theme-contracts/`
Theme and token model:
- token taxonomy
- theme ids
- mode ids such as light/dark
- inheritance rules

#### `component-contracts/`
Schema-renderable component contracts:
- component names
- props schema
- slots
- styling props
- events
- fallback behavior

## 8. Flutter Runtime Packages

```text
packages/
  flutter_daryeel_client_app/
  flutter_runtime/
  flutter_components/
  flutter_themes/
  flutter_schema_renderer/
```

This is intentionally split by responsibility rather than placed in one large runtime package.

Note: Some planned packages mentioned in older docs (e.g. `flutter_schema_forms`, `flutter_schema_actions`, `flutter_schema_diagnostics`) are not present in this repo snapshot.

### `flutter_daryeel_client_app/`
Shared Flutter client app framework:
- app bootstrap and wiring for schema-driven navigation
- shared app-level utilities used by product shells

### `flutter_runtime/`
Core runtime bootstrapping and orchestration.

### `flutter_components/`
Predesigned reusable widgets used by the schema renderer.

### `flutter_themes/`
Token resolution, theme inheritance, and Flutter theming integration.

### `flutter_schema_renderer/`
Schema-to-widget composition and rendering.

## 9. Optional Future Packages (Not In This Repo Snapshot)

Older architecture drafts sometimes referenced additional package splits (web schema runtime packages, backend core modules, runtime diagnostics packages). These are not present in this repository snapshot; treat them as optional future modularization rather than current structure.

## 10. Tooling (Optional)

Optional future additions (not present in this repo snapshot):

```text
tooling/
  schema-validator/
  contract-linter/
  schema-preview/
  schema-inspector/
```

These tools are recommended because schema-driven UI depends heavily on validation and inspection.

## 11. Examples and Fixtures (Optional)

Optional future additions (not present in this repo snapshot):

```text
examples/
  schema-fixtures/
  component-fixtures/
  theme-fixtures/
```

Fixtures should be treated as part of the platform, not as throwaway samples.

They help with:
- documentation
- preview tooling
- regression tests
- schema validation
- theme testing

Note: `examples/` is not present in this repo snapshot.

## 12. Recommended Reduced MVP Structure

If you want a smaller starting footprint, use this reduced version first:

```text
Daryeel2/
  docs/
  docker-compose.yml

  apps/
    customer-app/
    provider-app/
    admin-ops-web/

  services/
    api/
    schema-service/

  packages/
    domain/
    schema-contracts/
    theme-contracts/
    component-contracts/

    flutter_runtime/
    flutter_components/
    flutter_themes/
    flutter_schema_renderer/
    flutter_daryeel_client_app/

    schema_runtime_dart/
    schema_runtime_ts/
```

This is enough to start without over-fragmenting the platform too early.

## 13. Anti-Patterns to Avoid

Avoid:
- organizing everything by service first
- one giant `shared/` package with mixed concerns
- one monolithic schema runtime package containing rendering, forms, theme, actions, and diagnostics together
- naming products in ways that conflict with the platform actor model

## 14. Recommendation Summary

Recommended naming and structure:
- `customer-app`
- `provider-app`
- `admin-ops-web`
- platform-first monorepo organization
- shared contracts and runtime packages as first-class modules

This gives Daryeel2 a structure that matches the platform direction already defined in the schema, runtime, and theming docs.