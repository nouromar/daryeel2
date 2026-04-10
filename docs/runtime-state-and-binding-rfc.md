---
description: "RFC: Runtime enhancements for cross-screen state, two-way bindings, interpolation, and generic state actions (enables schema-driven cart flows)."
status: draft
owner: schema-runtime
last_updated: 2026-04-06
---

# RFC: Runtime State Store + Two-Way Bindings (Cart-Ready Schema Runtime)

## Summary
This RFC proposes a **generic, reusable** set of runtime enhancements to support schema-driven flows that require **cross-screen mutable state** and **reactive UI updates**, with cart/checkout as the motivating example.

Today, schema screens can render remote data, navigate, submit forms, and emit telemetry. However, there is no supported way to:

- Mutate shared state from schema actions (beyond form submit payloads).
- Bind component props to state (badge counts, totals, dynamic titles).
- Interpolate strings using state/data (e.g., `"Cart (3)"`).

This RFC introduces:

1. A runtime-scoped state store (the canonical `$state`) that lives for the session and is shared across schema screens.
2. A binding/interpolation mechanism so schema props can **read** state and re-render when it changes.
3. New generic schema actions (`set_state` / `patch_state`) so schema can **write** state.
4. Optional component action hooks (e.g., `CatalogItemTile` add action delegation) so schema defines behavior.

The design is **generic** (not pharmacy-specific) and can power many flows: carts, multi-step wizards, filter chips, saved items, draft forms, and more.

---

## Goals
- **Cross-screen state**: schema screens can share and update state across navigation.
- **Reactive rendering**: UI updates automatically when the referenced state changes.
- **Generic state actions**: schema can mutate state without custom app code.
- **String interpolation**: schema can build titles/labels from state and data.
- **Security + budgets**: state reads/writes are governed by existing policy/budget patterns.
- **Backwards compatible**: existing schemas continue to work unchanged.

## Non-goals
- Replace app-level domain logic entirely.
- Introduce a full expression language or Turing-complete scripting.
- Create a pharmacy-only cart API or specialized runtime cart engine.
- Provide server-side persistence in v1 of this RFC.

---

## Current limitations (why cart is hard in schema today)
A cart flow requires:

- Shared state across: `pharmacy_shop` → cart review → checkout.
- Mutations triggered by user actions in arbitrary components (add/increment/decrement/remove).
- Derived UI (badge counts, totals) that reacts immediately to state changes.

Today:

- The action allowlist is intentionally small (navigate/open_url/submit_form/track_event).
- There is no supported schema action to perform state mutation.
- There is no binding system to read `$state` inside props or text.
- Telemetry payload is sanitized to primitives; it can’t safely carry whole cart item payloads.
- Some components (e.g. `CatalogItemTile`) hardcode behavior instead of delegating to `node.actions`.

---

## How this merges existing work (less bulky, more robust)
This RFC is intentionally designed to **absorb and generalize** capabilities we’ve already built so the framework becomes more consistent and less "feature-by-feature".

Key consolidation points:

- **Single canonical `$state`**
  - We already introduced `$state` concepts in query/state binding (e.g., query params → state → auto re-runs).
  - This RFC turns `$state` into the single runtime store for all schema-level state (queries, filters, carts, drafts), rather than introducing parallel mechanisms per feature.

- **One generic mutation pathway (actions) instead of app overrides**
  - Today, feature flows sometimes require app-level overrides or hardcoded component behavior.
  - Adding `set_state`/`patch_state` lets schemas mutate state directly via the action system, keeping apps thin and avoiding service-specific forks.

- **One generic read/bind pathway (bindings/interpolation)**
  - Instead of adding bespoke "badge" or "cart count" props to components, bindings allow any component prop to become reactive.
  - This reduces component surface area growth and keeps most variability in schema.

- **Reuse existing security + budgets + audit infrastructure**
  - The runtime already has a security/budget philosophy and diagnostics/audit sinks.
  - State read/write becomes budgeted and audited just like other runtime operations, keeping the system safe as it grows.

- **Reuse existing diagnostics + runtime inspector direction**
  - We already invested in inspector visibility into loaded schema/theme and runtime diagnostics.
  - This RFC extends that same debugging model to state: show `$state` snapshots and the last mutations (optional), rather than adding ad-hoc logging per feature.

- **Component action delegation reduces widget duplication**
  - If interactive widgets consistently honor `node.actions.*`, we avoid writing custom widgets for each service flow.
  - Cart becomes "just schema" (actions + bindings), not a new bespoke native flow.

---

## Proposal

### 1) Runtime state store (session scoped)

#### Where state lives
A runtime store instance lives inside the runtime session scope (the same place that owns:
- action dispatcher
- visibility context
- diagnostics sink
- caches/query stores

**Lifetime**: from authenticated session start to logout/session reset.

#### Data model
- Canonical root object: `$state`.
- JSON-like structure: `Map<String, Object?>` with arrays and nested maps.
- Keys are strings; values limited to JSON primitives plus `Map`/`List`.

#### Notification model
The store is observable; any mutation triggers change notifications.

- Widgets that bind to `$state` must be rebuilt on relevant changes.
- Prefer fine-grained invalidation (path-based) but allow coarse fallback initially.

#### Namespacing
Recommend namespacing state by feature:

- `$state.pharmacy.cart` for cart data
- `$state.query.*` for query/filter state
- `$state.formDrafts.*` for drafts

This avoids collisions and keeps schemas readable.

---

### 2) Bindings and interpolation (read path)

This is the core of “two-way binding”:

- **Write**: schema dispatches `set_state` / `patch_state`
- **Read**: component props reference state via binding/interpolation

Two options are compatible; we can support both, but should pick one as canonical.

#### Option A: Structured binding objects (recommended)
A binding is expressed as an object rather than special string syntax.

Example:

```json
{
  "type": "Text",
  "props": {
    "text": {
      "$bind": "state.pharmacy.cart.totalQuantity",
      "default": "0"
    }
  }
}
```

Pros:
- Avoids ambiguity in strings.
- Easier to validate statically in schema-service.

#### Option B: String interpolation
Allow `"${...}"` placeholders in string props.

Example:

```json
{
  "type": "Text",
  "props": {
    "text": "Cart (${state.pharmacy.cart.totalQuantity})"
  }
}
```

Pros:
- Ergonomic for common cases.

Cons:
- Harder to validate reliably; more runtime parsing.

#### Minimal supported expression set
To keep the runtime safe and predictable, expressions are intentionally bounded:

- Roots/scopes: `state`, `data`, `item`, `index`, `params`
- Operators: arithmetic, comparisons, boolean logic, `??`, ternary `?:`
- Small allowlist of pure functions (see `docs/expression-engine-rfc.md`)
- No loops, assignments, mutation, reflection, IO/network/time/randomness

#### Re-render semantics
Any widget using `$bind` or interpolation becomes “state-aware”:

- It subscribes to the runtime store.
- When referenced paths change, it rebuilds.

Initial implementation can rebuild on any store change; later optimize with path subscriptions.

---

### 3) State mutation actions (write path)

Add new schema action types:

- `set_state` — set a value at a path.
- `patch_state` — apply a restricted set of operations at one or more paths.

Both must be:
- allowlisted by policy
- budgeted and audited
- validated by schema-service

#### Action: `set_state`

Canonical schema shape (matches runtime implementation):

```json
{
  "type": "set_state",
  "value": {
    "path": "pharmacy.cart.itemsById.123.quantity",
    "value": 2
  }
}
```

Notes:
- `path` is relative to `$state` root.
- `path` supports interpolation (e.g. `"pharmacy.cart.itemsById.${item.id}.quantity"`).
- `value` must be JSON-like (primitives, arrays, maps) and is sanitized/budgeted.
- `value` supports bounded expression evaluation via:
  - exact-placeholder typed strings (e.g. `"${state.profile.defaultAddress}"`)
  - explicit typed objects (e.g. `{ "$expr": "state.profile.defaultAddress" }`)
  - nested template strings inside maps/lists

#### Action: `patch_state`

Supports safe operations without exposing arbitrary scripting:

```json
{
  "type": "patch_state",
  "value": {
    "ops": [
      {
        "op": "increment",
        "path": "pharmacy.cart.itemsById.123.quantity",
        "by": 1
      },
      {
        "op": "set",
        "path": "pharmacy.cart.itemsById.123.title",
        "value": "Panadol"
      },
      {"op": "remove", "path": "pharmacy.cart.itemsById.123"}
    ]
  }
}
```

Supported ops (initial set):
- `set`
- `remove`
- `increment` (numeric only; use negative `by` for decrement)
- `append` (array only)

#### Ops ↔ store methods (implementation contract)
The action dispatcher is intentionally a thin, allowlisted facade over `SchemaStateStore`.

This table is the canonical mapping between schema ops and store methods:

| Schema action/op | Payload shape (within `action.value`) | Dispatcher behavior | `SchemaStateStore` method |
|---|---|---|---|
| `set_state` | `{ "path": "<string>", "value": <json> }` | Interpolate `path`, evaluate+sanitize `value`, set at path | `setValue(path, value)` |
| `patch_state` / `set` | `{ "op": "set", "path": "<string>", "value": <json> }` | Interpolate `path`, evaluate+sanitize `value`, set at path | `setValue(path, value)` |
| `patch_state` / `remove` | `{ "op": "remove", "path": "<string>" }` | Interpolate `path`, remove if present | `removeValue(path)` |
| `patch_state` / `increment` | `{ "op": "increment", "path": "<string>", "by": <num|expr> }` | Interpolate `path`, evaluate `by` to number, increment numeric value (missing→0) | `incrementValue(path, by)` |
| `patch_state` / `append` | `{ "op": "append", "path": "<string>", "value": <json> }` | Interpolate `path`, evaluate+sanitize `value`, append to list (missing→new list) | `appendValue(path, value)` |

Guardrails (must remain true as the surface area grows):
- Hard cap on ops per action via `SecurityBudgets.maxStatePatchOpsPerAction`.
- State value sanitizer enforces JSON-like shape and budgets (depth/node counts, map/list limits).
- Unknown op or malformed payload shapes are ignored (fail-closed, no crash).

#### Guardrails
- Maximum op count per action (e.g. 10).
- Maximum resulting state size (budgeted).
- Reject deep recursion or pathological paths.

---

### 4) Component action delegation (optional but strongly recommended)

Many schema components already accept `actions` maps, but some widgets hardcode behavior.

For cart, `CatalogItemTile` should support:

- `actions.add`: if present, dispatch it; otherwise fallback to telemetry.
- `actions.tap`: if present, dispatch it; otherwise fallback to navigate based on `item.route`.

Example schema:

```json
{
  "type": "CatalogItemTile",
  "props": {
    "titlePath": "name",
    "subtitlePath": "subtitle"
  },
  "actions": { "add": "pharmacy_add_to_cart" }
}
```

With a corresponding screen action:

```json
{
  "actions": {
    "pharmacy_add_to_cart": {
      "type": "patch_state",
      "value": {
        "ops": [
          {
            "op": "increment",
            "path": "pharmacy.cart.itemsById.${item.id}.quantity",
            "by": 1
          }
        ]
      }
    }
  }
}
```

This keeps cart behavior defined in schema rather than app overrides.

---

## Example: Schema-driven pharmacy cart (end-to-end)

### State shape

```json
{
  "pharmacy": {
    "cart": {
      "itemsById": {
        "123": {"id": "123", "title": "Panadol", "quantity": 2, "rxRequired": false}
      },
      "totalQuantity": 2
    }
  }
}
```

`totalQuantity` can be:
- explicitly maintained by ops, or
- computed by a future derived-state mechanism.

For v1, prefer explicit maintenance (simpler).

### Badge

```json
{
  "type": "ActionCard",
  "props": {
    "title": "Cart",
    "subtitle": "Items: ${state.pharmacy.cart.totalQuantity}"
  },
  "actions": { "tap": "go_cart" }
}
```

With a corresponding screen action:

```json
{
  "actions": {
    "go_cart": {
      "type": "navigate",
      "route": "customer.pharmacy.cart"
    }
  }
}
```

### Add to cart

`CatalogItemTile.actions.add` dispatches `patch_state` increment.

### Cart screen
Schema screen renders items from `$state.pharmacy.cart.items` (or `itemsById` values) using `ForEach`.

This requires either:
- a future `values()` helper, or
- storing `items` as an array instead of a map.

For v1 simplicity, store `items` as an array of lines:

```json
{
  "pharmacy": {
    "cart": {
      "items": [
        {"id": "123", "title": "Panadol", "quantity": 2, "rxRequired": false}
      ],
      "totalQuantity": 2
    }
  }
}
```

Then:

```json
{
  "type": "ForEach",
  "props": {
    "itemsPath": "$state.pharmacy.cart.items",
    "itemKeyPath": "id"
  },
  "slots": {
    "item": [
      {
        "type": "Row",
        "slots": {
          "children": [
            {"type": "Text", "props": {"text": "${item.title}"}},
            {"type": "Text", "props": {"text": "${item.quantity}"}},
            {
              "type": "ActionCard",
              "props": {"title": "+"},
              "actions": { "tap": "cart_item_inc" }
            }
          ]
        }
      }
    ]
  }
}
```

With a corresponding screen action:

```json
{
  "actions": {
    "cart_item_inc": {
      "type": "patch_state",
      "value": {
        "ops": [
          {
            "op": "increment",
            "path": "pharmacy.cart.items.${index}.quantity",
            "by": 1
          }
        ]
      }
    }
  }
}
```

Notes:
- This example uses `${index}`; support for an `index` binding is recommended for `ForEach`.
- If we do not want index-based writes, we should introduce an `updateWhere` op keyed by `id`.

---

## Validation and tooling

### Schema-service validation
Add validation rules:
- `$bind` must be a string path with allowed roots (`state`, `item`, `params`, `env`).
- Interpolation placeholders must reference allowed roots.
- `set_state` / `patch_state` must have well-formed paths and JSON-safe values.
- Budget: cap total payload size.

### Runtime diagnostics
Emit structured diagnostics events:
- `runtime.state.read` (path, consumer component)
- `runtime.state.write` (op, path, size deltas)
- `runtime.state.binding_parse_error`

### Security budgets
Integrate with the existing budget framework:
- Reads: count bound-path evaluations per frame.
- Writes: count operations and total serialized state size.
- Fail closed with clear diagnostics in debug.

---

## Backwards compatibility
- Existing schema components continue to read literal strings/numbers as before.
- Bindings are opt-in: only when `$bind` object or interpolation syntax is used.
- `set_state`/`patch_state` are gated by action allowlist policy.

---

## Rollout plan (incremental)

### Phase 1: State store + `set_state`
- Implement runtime store in session.
- Add `set_state` action dispatcher, policy allowlist, budgets, diagnostics.
- Supported mutation methods/ops:
  - `SchemaStateStore.setValue()` via `set_state {path,value}` (canonical)
- No interpolation yet (bindings only via structured `$bind`).

### Phase 2: Interpolation + `patch_state`
- Add interpolation parsing for string props (limited expression set).
- Add `patch_state` operations:
  - `set` → `SchemaStateStore.setValue()`
  - `remove` → `SchemaStateStore.removeValue()`
  - `increment` → `SchemaStateStore.incrementValue()` (negative `by` allowed)
  - `append` → `SchemaStateStore.appendValue()`

### Phase 3: Component action delegation
- Update `CatalogItemTile` (and other interactive widgets) to delegate actions from schema when provided.

### Phase 4 (optional): Persistence plugin
- Add a generic persistence adapter for selected `$state` path prefixes.

Implementation (current):
- App config: `DaryeelRuntimeConfig.statePersistence` (list of dot-paths like `pharmacy.cart`).
- Storage: `SharedPreferences` under a stable key (default: `daryeel_client.state.<product>.<appId>`).
- Restore: once per runtime session (best-effort; corrupt payload is ignored).
- Save: auto-save on `$state` changes with a small debounce; oversized payloads are skipped.

---

## Open questions
- **Path subscriptions**: do we need fine-grained rebuilds immediately, or accept coarse rebuilds for v1?
- **Index writes**: should we allow `${index}` or require ID-based updates?
- **Derived state**: do we add a safe computed/derived layer (e.g. `totalQuantity` computed), or keep explicit for now?
- **Debug tooling**: should the Runtime Inspector show `$state` snapshots and last mutations?

---

## Appendix: Proposed action JSON shapes

### set_state

```json
{
  "type": "set_state",
  "value": {
    "path": "<string>",
    "value": "<any JSON>"
  }
}
```

### patch_state

```json
{
  "type": "patch_state",
  "value": {
    "ops": [
      {"op": "set", "path": "<string>", "value": "<any JSON>"},
      {"op": "remove", "path": "<string>"},
      {"op": "increment", "path": "<string>", "by": 1},
      {"op": "append", "path": "<string>", "value": "<any JSON>"}
    ]
  }
}
```

### bind

```json
{"$bind": "state.<path>", "default": "<optional>"}
```

### interpolation

- Literal strings remain unchanged.
- Strings containing `${...}` placeholders are interpolated.

---

## Decision
If approved, this RFC enables a fully schema-driven cart (and similar flows) without app-specific overrides, while keeping the runtime safe, audited, and reusable across services.
