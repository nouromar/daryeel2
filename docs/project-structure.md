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

Recommended top-level repository structure:

```text
Daryeel2/
  README.md
  docs/

  apps/
    customer-app/
    provider-app/
    admin-ops-web/

  services/
    api/
    schema-service/
    asset-service/

  packages/
    domain/
    api-contracts/
    schema-contracts/
    theme-contracts/
    component-contracts/

    schema_runtime_dart/
    schema_runtime_ts/

    flutter_runtime/
    flutter_components/
    flutter_themes/
    flutter_schema_renderer/
    flutter_schema_forms/
    flutter_schema_actions/
    flutter_schema_diagnostics/

    web_runtime/
    web_components/
    web_themes/
    web_schema_renderer/
    web_schema_actions/
    web_schema_diagnostics/

    backend_core/
    backend_modules/
    backend_auth/
    backend_dispatch/
    backend_payments/
    backend_events/

  tooling/
    schema-validator/
    contract-linter/
    schema-preview/
    schema-inspector/

  infra/
    docker/
    deploy/
    observability/

  examples/
    schema-fixtures/
    component-fixtures/
    theme-fixtures/
```

## 4. Structure Rationale

This layout treats Daryeel2 as a platform, not only as a set of separate apps.

It separates concerns into:
- `apps/` for product shells
- `services/` for deployable backend services
- `packages/` for reusable libraries and contracts
- `tooling/` for internal validation and preview tools
- `examples/` for fixtures used in testing, previewing, and documentation

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
  asset-service/
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

### `asset-service/`
Owns optional remote assets such as:
- schema-managed icons and illustrations
- content images
- signed asset delivery if needed later

This can be deferred or folded into existing storage early on.

## 7. Shared Packages

### 7.1 Shared contracts and domain language

```text
packages/
  domain/
  api-contracts/
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

#### `api-contracts/`
Transport contracts:
- request and response DTOs
- endpoint payload shapes
- versioned server/client models

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
  flutter_runtime/
  flutter_components/
  flutter_themes/
  flutter_schema_renderer/
  flutter_schema_forms/
  flutter_schema_actions/
  flutter_schema_diagnostics/
```

This is intentionally split by responsibility rather than placed in one large runtime package.

### `flutter_runtime/`
Core runtime bootstrapping and orchestration.

### `flutter_components/`
Predesigned reusable widgets used by the schema renderer.

### `flutter_themes/`
Token resolution, theme inheritance, and Flutter theming integration.

### `flutter_schema_renderer/`
Schema-to-widget composition and rendering.

### `flutter_schema_forms/`
Form binding, state, and validation orchestration.

### `flutter_schema_actions/`
Known action handlers and action dispatch.

### `flutter_schema_diagnostics/`
Fallback, inspection, and runtime diagnostics.

## 9. Web Runtime Packages

```text
packages/
  web_runtime/
  web_components/
  web_themes/
  web_schema_renderer/
  web_schema_actions/
  web_schema_diagnostics/
```

These mirror the Flutter runtime concepts, while allowing the web platform to keep its own renderer and delivery concerns.

## 10. Backend Core Packages

```text
packages/
  backend_core/
  backend_modules/
  backend_auth/
  backend_dispatch/
  backend_payments/
  backend_events/
```

### `backend_core/`
Shared platform backend logic.

### `backend_modules/`
Per-service backend modules such as:
- taxi
- delivery
- pharmacy
- ambulance
- home_visit

### `backend_auth/`
Identity, roles, memberships, and policy helpers.

### `backend_dispatch/`
Provider eligibility, offer lifecycle, retries, and scoring orchestration.

### `backend_payments/`
Payment and payout abstractions and processor integrations.

### `backend_events/`
Request timeline events, notifications, and audit fanout.

## 11. Tooling

```text
tooling/
  schema-validator/
  contract-linter/
  schema-preview/
  schema-inspector/
```

These tools are first-class because schema-driven UI depends heavily on validation and inspection.

## 12. Examples and Fixtures

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

## 13. Recommended Reduced MVP Structure

If you want a smaller starting footprint, use this reduced version first:

```text
Daryeel2/
  docs/

  apps/
    customer-app/
    provider-app/
    admin-ops-web/

  services/
    api/
    schema-service/

  packages/
    domain/
    api-contracts/
    schema-contracts/
    theme-contracts/
    component-contracts/

    flutter_runtime/
    flutter_components/
    flutter_themes/
    flutter_schema_renderer/
    flutter_schema_forms/
    flutter_schema_actions/

    web_runtime/
    web_components/
    web_themes/
    web_schema_renderer/

  tooling/
    schema-validator/
    schema-preview/

  examples/
    schema-fixtures/
    theme-fixtures/
```

This is enough to start without over-fragmenting the platform too early.

## 14. Anti-Patterns to Avoid

Avoid:
- organizing everything by service first
- one giant `shared/` package with mixed concerns
- one monolithic schema runtime package containing rendering, forms, theme, actions, and diagnostics together
- naming products in ways that conflict with the platform actor model

## 15. Recommendation Summary

Recommended naming and structure:
- `customer-app`
- `provider-app`
- `admin-ops-web`
- platform-first monorepo organization
- shared contracts and runtime packages as first-class modules

This gives Daryeel2 a structure that matches the platform direction already defined in the schema, runtime, and theming docs.