# Schema Client Runtime Architecture

## 1. Purpose

This document defines the client-side runtime architecture needed to execute Daryeel2's schema-driven UI platform reliably.

The runtime is not a single engine. It is a coordinated set of focused engines that together:
- fetch and validate schemas
- resolve reusable references
- render approved components
- apply themes and variants
- execute supported actions
- manage bindings, forms, and flow state
- recover safely when anything is invalid or unsupported

## 2. Runtime Layers

The client runtime can be understood in five layers:

1. schema pipeline
2. rendering pipeline
3. interaction pipeline
4. safety pipeline
5. observability pipeline

Cross-platform design note:
- the schema pipeline should be implemented as a language-level core (Dart core for Flutter apps; TypeScript core for Web admin)
- rendering/actions/bindings are platform adapters built on top of the same normalized tree semantics

## 3. Schema Pipeline

### 3.1 Schema Fetch and Cache Engine
Responsibilities:
- fetch schema documents and referenced fragments
- cache last known good schemas locally
- support offline startup and fallback
- handle refresh, invalidation, and rollback

Why it matters:
- schema-driven products become unreliable immediately if schema delivery is fragile

### 3.2 Schema Compatibility Engine
Responsibilities:
- validate supported schema version
- validate required component contract versions
- validate supported theme IDs and modes
- reject incompatible schemas before rendering

Why it matters:
- prevents the client from partially rendering something it cannot support safely

### 3.3 Schema Validation Engine
Responsibilities:
- validate document shape
- validate node types
- validate props against contracts
- validate slots, bindings, actions, visibility rules, and references

v1 note (current implementation):
- `visibleWhen` evaluation is intentionally narrow and safe:
	- `visibleWhen.featureFlag` (feature flags)
	- `visibleWhen.expr` (bounded one-line boolean expression)
- Unknown `visibleWhen` keys should not break rendering; they should default to visible and emit diagnostics.

Why it matters:
- this is the main safety barrier between remote schema input and the renderer

### 3.4 Reference Resolution Engine
Responsibilities:
- resolve `ref` nodes to approved fragments
- detect missing or circular references
- materialize the final resolved tree

Why it matters:
- reuse only works if reference resolution is deterministic and inspectable

### 3.5 Composition Engine
Responsibilities:
- merge defaults with provided props
- assemble slot trees
- apply overrides in the correct precedence order
- emit a normalized render tree used by the renderer

Why it matters:
- rendering should consume a normalized tree, not raw schema documents

## 4. Rendering Pipeline

### 4.1 Component Registry and Renderer
Responsibilities:
- map schema component names to native components
- instantiate components with validated props
- provide fallback behavior for unknown nodes
- support product-specific renderers where needed

Why it matters:
- the registry is the bridge between schema language and real UI

### 4.2 Theme Engine
Responsibilities:
- resolve `themeId` and `themeMode`
- load token bundles
- apply inheritance: base -> product -> service -> mode -> accessibility
- expose resolved semantic tokens to rendered components

Why it matters:
- schema chooses semantic intent; the theme engine resolves actual visual values

### 4.3 Variant and Styling Resolution Engine
Responsibilities:
- resolve `variant`, `tone`, `size`, `surface`, and `density`
- combine semantic styling props with active theme tokens
- apply bounded overrides
- prevent raw style drift

Why it matters:
- this engine converts styling intent into concrete appearance without letting schema act like a style language

### 4.4 Layout Engine
Responsibilities:
- enforce slot layout rules
- support screen templates and section composition
- handle responsive layout behavior
- keep layout deterministic across platforms

Why it matters:
- schema-driven composition needs predictable layout rules, not ad hoc nesting behavior

## 5. Interaction Pipeline

### 5.1 Action Engine
Responsibilities:
- resolve action IDs to platform-defined handlers
- execute supported action types
- reject unsupported action definitions
- emit diagnostics for action failures

Supported action types (implemented in the Flutter runtime as of Apr 2026):
- navigate
- open url
- submit form
- track event

Planned (not currently implemented in this repo snapshot):
- open modal
- refresh data
- select value

### 5.2 Navigation Engine
Responsibilities:
- map allowed navigation actions to known routes
- guard unknown routes
- preserve stack and deep-link rules

Why it matters:
- schema must not invent arbitrary navigation semantics at runtime

### 5.3 Binding Engine
Responsibilities:
- resolve `bind` targets like `form.phone`
- synchronize component values with local state
- support safe one-way and two-way bindings where allowed

Why it matters:
- form-heavy flows become hard to reason about if binding behavior is inconsistent

### 5.4 Form Engine
Responsibilities:
- track field state, errors, touched state, and submission
- coordinate field registration
- orchestrate validation and submit lifecycle

Why it matters:
- forms are a central product surface for Daryeel2

### 5.5 Flow State Engine
Responsibilities:
- manage deterministic local flow states
- support multi-step flows like checkout or proof capture
- enforce state transitions for known flow types

Why it matters:
- schema-driven screens still need reliable local interaction state

## 6. Safety Pipeline

### 6.1 Fallback and Recovery Engine
Responsibilities:
- recover from invalid schema nodes
- recover from theme or contract mismatches
- fall back to built-in safe screens when necessary
- keep failures isolated when possible

Why it matters:
- a bad schema should degrade gracefully, not crash the app

### 6.2 Permission Guard Engine
Responsibilities:
- gate UI based on known client-side permission context
- coordinate with backend authorization rules
- prevent sensitive actions from appearing when clearly disallowed

Why it matters:
- UI must not expose misleading or unsafe operations

### 6.3 Accessibility Engine
Responsibilities:
- enforce focus order, labels, and contrast expectations
- adapt to text scale and accessibility modes
- verify contract-level accessibility metadata is applied

Why it matters:
- schema-driven rendering should not compromise accessibility guarantees

## 7. Observability Pipeline

### 7.1 Telemetry and Diagnostics Engine
Responsibilities:
- log schema version and screen id
- log theme and mode
- log validation and render failures
- log action failures
- support production debugging and rollback analysis

### 7.2 Runtime Inspector
Responsibilities:
- show active schema id/version
- show active flags and theme
- inspect resolved component tree
- surface fallback reasons

Why it matters:
- schema-driven systems become hard to operate without introspection tools

## 8. Platform Adapter Layer

The runtime also needs adapters for platform-bound capabilities:
- maps
- location picker
- camera/uploads
- notifications
- payment sheet handoff
- device theme mode

These are not schema engines themselves, but the runtime depends on them.

## 9. Multi-Platform Runtime Parity

Because Daryeel2 targets multiple clients (Flutter customer/provider and Angular admin), the platform needs two implementations of the schema pipeline:
- a pure Dart core (no Flutter imports)
- a pure TypeScript core (framework-agnostic; used by Angular)

Parity rules:
- both cores must implement the same ref resolution semantics and strictness behaviors
- both cores should be validated against shared test vectors (JSON inputs with expected normalized outputs and expected error lists)

## 10. Minimum Viable Runtime

The minimum viable runtime for v1 should include:
- schema fetch and cache engine
- compatibility engine
- validation engine
- reference resolution engine
- component registry and renderer
- theme engine
- variant and styling resolution engine
- action engine
- navigation engine
- binding engine
- form engine
- fallback and recovery engine
- telemetry and diagnostics engine

## 11. Design Rule

The runtime should stay strict, typed, and boring.

If a feature would turn the runtime into a general-purpose interpreted application platform, it should be rejected or deferred.