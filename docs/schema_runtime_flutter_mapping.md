# Schema Runtime Flutter Mapping

## 1. Purpose

This document maps the schema-driven client runtime architecture onto a practical Flutter implementation.

The goal is to make the runtime concrete for Daryeel2's Flutter apps rather than leaving it as a generic platform diagram.

## 2. Suggested Flutter Runtime Structure

Current runtime package layout in this repo (Apr 2026):

- `packages/schema_runtime_dart/` — typed schema models and core semantics
- `packages/flutter_runtime/` — Flutter-facing runtime orchestration (actions, visibility, diagnostics)
- `packages/flutter_schema_renderer/` — schema-to-widget rendering and registry types
- `packages/flutter_components/` — core schema components (e.g. `ScreenTemplate`, layout primitives, `ForEach`, `Text`)
- `packages/flutter_themes/` — token/theme resolution and Flutter integration
- `packages/flutter_daryeel_client_app/` — shared client app bootstrap used by product shells

The conceptual runtime areas (schema/contracts/themes/rendering/actions/diagnostics) are implemented across these packages rather than a single `lib/schema/...` folder.

## 3. Flutter Mapping by Engine

### 3.1 Schema Fetch and Cache Engine
Flutter implementation concerns:
- fetch with standard HTTP client or app API layer
- persist schemas with local storage such as SQLite or another durable store
- cache last known good schema bundle per screen/service/product

Suggested outputs:
- resolved schema bundle model
- cache metadata including fetch time and version

### 3.2 Compatibility Engine
Flutter implementation concerns:
- compare schema version with client-supported versions
- compare theme ID/mode and component contract versions
- produce a structured compatibility result instead of throwing generic errors

### 3.3 Validation Engine
Flutter implementation concerns:
- parse raw JSON into typed schema models
- validate against contract registry before rendering
- return structured error objects for diagnostics UI and logs

### 3.4 Reference Resolution Engine
Flutter implementation concerns:
- maintain a fragment registry in memory for the active schema bundle
- resolve refs recursively
- detect loops and missing refs

### 3.5 Component Registry and Renderer
Flutter implementation concerns:
- register widget factories by component name
- each factory converts validated schema props into Flutter widget inputs
- unknown component names return a safe placeholder or omitted node

Possible registry shape:
- `Map<String, SchemaWidgetFactory>`

### 3.6 Theme Engine
Flutter implementation concerns:
- resolve `themeId` and `themeMode`
- merge token layers
- expose resolved tokens via inherited widget, provider, or another app state mechanism
- map resolved tokens into Flutter `ThemeData` where useful, while retaining custom token access for schema components

### 3.7 Variant and Styling Resolution Engine
Flutter implementation concerns:
- map `variant`, `tone`, `surface`, `size`, and `density` to semantic token usage
- keep presentation logic centralized rather than scattered across every widget
- use style resolver helpers per component family

### 3.8 Action Engine
Flutter implementation concerns:
- dispatch action IDs to known handlers
- keep action handlers typed and centrally registered
- separate action definition parsing from action execution

Possible pattern:
- `Map<String, SchemaActionHandler>` for action types

### 3.9 Navigation Engine
Flutter implementation concerns:
- map navigate actions to approved app routes
- do not let schema create arbitrary route strings without registry support
- support deep links only through approved route contracts

### 3.10 Binding Engine
Flutter implementation concerns:
- resolve bind paths like `form.phone`
- coordinate updates between widgets and form state
- avoid component-local state that bypasses the schema runtime

### 3.11 Form Engine
Flutter implementation concerns:
- manage form state in a dedicated controller layer
- support validation, touched state, and submit state
- expose field state to widgets through structured bindings

### 3.12 Fallback and Diagnostics Engine
Flutter implementation concerns:
- show built-in fallback widgets for invalid screen states
- capture render failures and schema validation errors
- provide internal debug panels for QA and development

## 4. Suggested Flutter Patterns

### 4.1 Keep runtime models separate from widget props
Do not pass raw schema maps deep into widgets.

Instead:
- parse schema into typed runtime models
- normalize models
- map normalized nodes into widget-level props

Recommended package layering (Option B):
- `packages/schema_runtime_dart/` owns typed schema parsing, ref resolution, normalization, and diagnostics
- `packages/flutter_runtime/` owns Flutter-facing orchestration and platform adapter hooks
- `packages/flutter_schema_renderer/` owns mapping normalized nodes to Widgets via a registry

### 4.2 Keep factories thin
Widget factories should:
- validate assumptions
- map props
- call reusable widgets

They should not contain major business logic.

### 4.3 Keep business flows outside schema execution
For Flutter specifically, avoid embedding complex workflow logic in the runtime itself.

Schema should drive composition and allowed interactions; app/domain code should still own domain behavior.

## 5. Suggested State Ownership

State ownership should be explicit:
- schema bundle state
- theme resolution state
- form state
- screen data/query state
- local flow state

Avoid mixing these into one monolithic controller.

## 6. Suggested Debugging Support in Flutter

Internal debug tooling should expose:
- schema id and version
- theme id and mode
- resolved component tree
- failed refs
- failed actions
- fallback reasons

This could be an internal debug screen or a developer-only overlay.

## 7. Performance Notes for Flutter

To keep rendering efficient:
- normalize schema once before rendering
- cache resolved fragments
- avoid rebuilding the entire tree on small field changes
- keep style resolution cheap and memoizable at the runtime layer
- prefer stable widget identities where possible

## 8. Recommended Early Flutter Deliverables

Start with:
- typed schema models
- contract registry
- theme runtime
- widget factory registry
- schema screen renderer
- diagnostics reporting

Then add:
- form binding
- ref resolution
- navigation actions
- visibility rules

Then add later:
- flow state engine
- runtime inspector
- richer operational tooling

## 9. Practical Rule for Flutter Implementation

If a schema-driven capability makes the Flutter widget tree harder to reason about than the product flow itself, the runtime is taking on too much.

The runtime should simplify UI delivery, not become the most complex part of the app.