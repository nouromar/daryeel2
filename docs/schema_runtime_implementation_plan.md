# Schema Runtime Implementation Plan

## 1. Purpose

This document defines a phased plan for implementing the client runtime behind Daryeel2's schema-driven UI system.

The goal is to deliver the runtime in stable increments rather than building an over-abstract platform all at once.

## 2. Implementation Strategy

Guiding principles:
- build the safety rails first
- ship only the minimum schema surface needed
- keep v1 intentionally constrained
- add observability early
- delay advanced flexibility until core reliability is proven

## 3. Phase 0: Foundations

Goal:
- prepare the codebase for a schema runtime without rendering production screens from schema yet

Scope:
- define schema document models
- define component contract registry models
- define theme models and token bundles
- define action catalog
- define validation rules

Deliverables:
- typed schema models
- typed contract models
- typed theme models
- schema fixtures for development
- cross-platform test vectors for parser/ref resolution parity

Exit criteria:
- schema documents can be parsed and validated in tests
- component contracts are registered and introspectable

## 4. Phase 1: Core Runtime

Goal:
- render simple schema-driven screens with safe fallback behavior

Scope:
- schema fetch and cache engine
- compatibility engine
- validation engine
- component registry and renderer
- theme engine
- basic variant resolution
- fallback and diagnostics engine

Supported features:
- component rendering
- props and defaults
- theme selection
- light/dark mode
- contract validation
- simple screen templates

Not yet included:
- advanced bindings
- multi-step flows
- experiments
- rich conditional rules

Exit criteria:
- a simple screen can render offline from cached schema
- invalid schema falls back safely
- theme resolution and diagnostics work reliably

Implementation note (multi-platform):
- extract the schema pipeline into `packages/schema_runtime_dart/` (pure Dart)
- keep `packages/flutter_runtime/` as a Flutter adapter/orchestrator
- introduce `packages/schema_runtime_ts/` for the Angular runtime (TypeScript core)

## 5. Phase 2: Composition and Forms

Goal:
- support practical product screens with slots, references, and forms

Scope:
- reference resolution engine
- composition engine
- binding engine
- form engine
- supported actions such as navigate and submit form

Supported features:
- slots
- shared fragments via refs
- form field binding
- validation states
- known navigation targets

Exit criteria:
- a real request form flow can be schema-driven end-to-end
- references resolve deterministically
- form submission is observable and recoverable

## 6. Phase 3: Controlled Runtime Flexibility

Goal:
- introduce measured flexibility without destabilizing the runtime

Scope:
- visibility rules engine
- feature flags and experiment integration
- richer styling variants
- bounded subtree-level presentation overrides

Supported features:
- feature-flag gated sections
- experiment branch selection
- service-specific schema selection
- semantic density/tone/surface overrides

Exit criteria:
- rollout and A/B testing can be supported without changing runtime contracts
- styling remains consistent under theme inheritance

## 7. Phase 4: Flow and Operational Hardening

Goal:
- support more complex flows and improve operational tooling

Scope:
- flow state engine
- runtime inspector
- richer diagnostics and support tooling
- stronger asset/media integration

Potential features:
- multi-step checkout flows
- proof capture flows
- richer retry and recovery behavior
- schema debug screens for internal QA/support

Exit criteria:
- multi-step flows remain deterministic and debuggable
- support teams can inspect the exact runtime state of a user session

## 8. Phase 5: Re-evaluation Point

Goal:
- decide whether the platform should expand further

Questions to answer:
- are contracts stable?
- are schemas easy to author and review?
- are debugging and rollback workflows good enough?
- do product teams actually need more runtime flexibility?

Possible expansions:
- richer authoring tools
- stronger internal schema editor
- broader domain coverage
- additional bounded conditional features

## 9. Non-Goals for Early Phases

Avoid in early phases:
- arbitrary expression languages
- dynamic endpoint definitions in schema
- free-form styling blobs
- generic workflow scripting
- components with unstable contracts

These features increase complexity faster than they increase delivery value.

## 10. Testing Strategy by Phase

### Phase 0 and 1
- schema parser tests
- contract validation tests
- theme resolution tests
- fallback tests

### Phase 2
- form binding tests
- ref resolution tests
- navigation/action tests

### Phase 3
- feature flag tests
- variant and override tests
- visibility rule tests

### Phase 4
- flow state tests
- recovery tests
- runtime inspector tests

## 11. Recommended Order of Investment

If implementation capacity is tight, prioritize in this order:
1. validation and compatibility
2. renderer and theme engine
3. fallback and diagnostics
4. forms and bindings
5. references and slots
6. flags and controlled visibility
7. flow state and inspector tooling

This order keeps the platform safe while it grows.