# Schema-Driven UI With Predesigned Component Contracts

## 1. Executive Summary

Daryeel2 will pursue a schema-driven UI approach built on a robust library of predesigned native components.

The core idea is:
- the backend sends schemas that describe composition
- the client renders those schemas using known native components
- components expose typed, versioned, customizable interfaces
- business-critical logic remains in platform code and backend policies

This is not a free-form remote UI system. It is a controlled composition platform designed for deployment flexibility, multi-service reuse, and long-term extensibility.

Related documents:
- [Schema Component Contracts](schema_component_contracts.md)
- [Schema Format v1](schema_format_v1.md)
- [Schema Client Runtime Architecture](schema_client_runtime_architecture.md)
- [Schema Runtime Implementation Plan](schema_runtime_implementation_plan.md)
- [Schema Runtime Flutter Mapping](schema_runtime_flutter_mapping.md)

These documents should be read together:
- architecture defines the runtime subsystems
- implementation plan defines delivery phases
- Flutter mapping turns the runtime into a concrete client structure


## 2. Goals

- Launch and evolve UI without requiring app-store releases for every structural change.
- Reuse the same platform across customer, provider, and admin/dispatch products.
- Support multiple services with a common composition language.
- Keep the UI runtime safe, typed, testable, and debuggable.
- Make service expansion easier over time without multiplying hardcoded screens.

## 3. Core Position

### 3.1 What the schema controls
- Screen composition.
- Section ordering.
- Component variants.
- Visibility of supported elements.
- Labels, helper text, and localized copy.
- Wiring of predefined actions.
- Selection among prebuilt branches.

### 3.2 What the schema does not control
- Authorization and permissions.
- Pricing rules.
- Dispatch scoring policy.
- Security-sensitive checks.
- Arbitrary business logic.
- Arbitrary code execution.

The schema is responsible for composition and controlled configuration, not domain policy.

## 4. Architecture

```text
Schema Authoring / Internal Tools
        ↓
Schema Registry / Delivery API
        ↓
Client Runtime
  - Schema cache
  - Schema validator
  - Reference resolver
  - UI renderer
  - Action dispatcher
  - Native component library
```

### Backend responsibilities
- Store versioned schemas.
- Assign schemas by app version, service, market, role, or experiment.
- Validate schema before publishing.
- Deliver schema bundles and dependencies.

Current implementation note (this repo snapshot):
- `services/schema-service` performs strict validation using component contracts registered in `packages/component-contracts/catalog.json`.
- Schemas and contracts are baked into the schema-service Docker image at build time (see `services/schema-service/Dockerfile`), so schema/contract changes require rebuilding that image.

### Client responsibilities
- Fetch and cache schemas.
- Validate schema compatibility.
- Resolve references.
- Render known component contracts.
- Execute only supported action types.
- Fall back safely when schema is unsupported.

## 5. Predesigned Component Strategy

The strength of this approach depends on the component library.

### 5.1 Component levels
- Shared components: reusable across many services and products.
- Domain components: reusable within a domain family like mobility, commerce, or healthcare.
- Service-specific components: allowed only when a service truly has unavoidable domain needs.

### 5.2 Abstraction rule
Components should be high-level enough to be useful in real product flows, but not so specific that they lock the system to a single service.

Good examples:
- `AddressSection`
- `PaymentOptionsSection`
- `QuoteSummaryCard`
- `ProviderCard`
- `StatusTimelinePanel`
- `TrackingPanel`

Poor examples for schema composition:
- low-level layout primitives only
- components whose names encode one exact service flow
- components that need many flags just to work outside one service

## 6. Component Contracts

Every renderable component must expose a contract.

Minimum contract shape:
- component name
- category
- supported props
- prop types
- default values
- supported actions/events
- supported child slots
- version support
- fallback behavior

This allows schema authors to customize components safely while preserving a stable runtime.

In this repo snapshot, contracts live in `packages/component-contracts/` and are consumed by schema-service for server-side validation.

## 7. Customization Model

Components must support schema customization through typed props with safe defaults.

Good customization areas:
- variant selection
- labels and placeholders
- optional visibility
- known state modes
- choice ordering
- icons and badges from approved enums
- enabled actions from approved action types

Avoid making components configurable in ways that turn schema into a programming language.

## 8. Action Model

The platform should support a constrained set of actions, such as:
- navigate to a known route
- submit a form to a known backend action
- refresh a data source
- open a modal
- select an item
- trigger a local state transition from a known state machine

The action system must not support arbitrary API definitions or arbitrary logic trees in schemas.

## 9. Theming and Styling Model

Daryeel2 should use:
- token-based theming
- component variants
- theme inheritance
- bounded styling overrides

Daryeel2 should not use raw style objects as the primary styling mechanism.

### 9.1 Token-based theming
Themes should be expressed primarily as semantic design tokens, such as:
- color tokens
- typography tokens
- spacing tokens
- radius tokens
- elevation tokens

Components consume semantic tokens rather than ad hoc colors or dimensions from schema.

### 9.2 Component variants
Schema should select among approved presentation variants like:
- `variant`
- `tone`
- `size`
- `surface`
- `density`

These variant choices map to the active theme tokens in the client runtime.

Concrete example (implemented):
- A core `Text` schema component supports typography intent through bounded props like `variant`, `weight`, `color`, `align`, `maxLines`, and `overflow`.

### 9.3 Theme inheritance
Themes should support layered inheritance, for example:
- base theme
- product theme
- service theme
- mode override such as `light` / `dark`
- accessibility override such as high contrast

This makes white-labeling and service flavoring possible without fragmenting the component library.

### 9.4 Bounded overrides
Local styling overrides are allowed only through a small approved set of semantic fields.

Good examples:
- `surface: raised`
- `density: compact`
- `tone: emphasized`

Bad examples:
- arbitrary hex colors
- arbitrary spacing values on every node
- raw font sizing everywhere
- free-form layout style blobs

The schema expresses intent. The theme system determines the final visual output.

## 10. Runtime Safety

The schema runtime must be strict.

Rules:
- unknown component -> safe fallback or omit
- unknown prop -> ignore safely when allowed by contract
- incompatible schema version -> reject and use fallback screen
- unsupported action type -> block and log
- invalid reference -> reject subtree or whole schema based on severity

The runtime should never guess.

## 11. Versioning and Compatibility

Compatibility is a first-class platform concern.

Rules:
- schemas are versioned
- component contracts are versioned
- clients declare supported schema and component versions
- breaking changes require new versions
- deprecated props/components remain supported for a defined migration window

This is essential for long-term extensibility.

## 12. Offline and Deployment Flexibility

The schema-driven model must improve deployment flexibility, not reduce reliability.

Requirements:
- cache the last known good schema locally
- ship baseline fallback experiences in the app
- allow service screens to keep working when schema delivery fails
- separate schema bundle rollout from app binary rollout where possible

This gives operational flexibility without making the product hostage to live config delivery.

## 13. Observability

To keep the system supportable, every client should be able to report:
- active schema version
- active component contract versions
- active experiment flags
- service slug and screen identifier
- validation failures
- action execution failures

Without this, a schema-driven platform becomes difficult to debug in production.

## 14. Governance

Schema-driven UI is also an operating model.

You need:
- contract ownership
- schema review and approval
- rollout controls
- rollback strategy
- contract deprecation policy
- testing gates for schemas and components

Without governance, flexibility becomes inconsistency.

## 15. Practical Direction for Daryeel2

Daryeel2 should build toward a disciplined schema-driven system, not an unrestricted one.

The practical architecture is:
- robust predesigned native components
- typed component contracts
- versioned schema documents
- constrained action model
- token-based theming with variants and inheritance
- service-specific components only when unavoidable

That gives the flexibility you want while still preserving system quality over time.