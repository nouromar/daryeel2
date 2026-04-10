---
title: "Expression Engine (Implemented)"
status: "implemented"
audience: ["schema-runtime", "flutter", "typescript"]
lastUpdated: "2026-04-09"
---

# Expression Engine (Implemented)

## 1. Summary
We added a **lightweight, sandboxed expression engine** to the schema runtime to enable:
- One-line expressions inside `${...}` for **math, comparisons, boolean logic, and ternary `?:`**.
- Typed evaluation (returning numbers/bools/maps/lists) when needed by actions and bindings.
- Consistent behavior across **Dart (Flutter)** and **TypeScript** runtimes.

This is explicitly **not** a scripting language.

## 2. Motivation
Schema-driven UI quickly hits limits with string-only interpolation and limited conditionals.
We need:
- `qty > 1`, `totalQuantity + 1`, `rxRequired ? 'Rx' : ''`
- Passing structured values into actions (e.g., setting a bound address object)
- Safer, more expressive visibility and component configuration without app-specific glue

## 3. Goals
### Functional goals
- Support `${expr}` segments inside strings for display text.
- Support **typed** expression evaluation for action payloads and other non-string contexts.
- Support core operators:
  - Arithmetic: `+ - * / %` (with `+` as string concat if either operand is string)
  - Comparisons: `== != < <= > >=`
  - Boolean: `&& || !`
  - Nullish coalescing: `??`
  - Ternary: `cond ? a : b`
- Resolve identifiers against standard runtime scopes:
  - `state`: schema state
  - `data`: schema data scope
  - `item` and `index`: `ForEach` scope
  - `params`: route params
- Missing paths resolve to `null` **silently**; optionally emit **gated debug diagnostics**.

### Non-functional goals
- Deterministic, side-effect free
- Safe under untrusted schemas (budgets + allowlists)
- Fast enough for list rendering (compile/cache expressions)

## 4. Non-goals
- No user-defined functions, loops, assignments, mutation
- No method invocation on arbitrary objects
- No reflection, IO, network, time, randomness
- No bracket indexing syntax in v1 (`x['key']`, `x[index]`) unless proven essential

## 5. Proposed Syntax

### 5.1 Template interpolation (string output)
Any string may include `${expr}` segments.

Examples:
- `"Items: ${state.pharmacy.cart.totalQuantity}"`
- `"${item.title} • ${item.quantity}"`
- `"${state.user.name ?? 'Guest'}"`

**Rule:** template interpolation always returns a **String**.

### 5.2 Typed evaluation (non-string output)
We need a way to evaluate expressions to non-string values.

We support **two mechanisms**:

1) **Exact-placeholder typed rule**
- If a string is exactly a single placeholder (after trimming), e.g.:
  - `"${state.pharmacy.cart.deliveryAddress}"`
- Then the result is the underlying typed value (Map/List/num/bool/null).

2) **Explicit typed expression object (canonical)**
- `{ "$expr": "state.pharmacy.cart.deliveryAddress" }`

Rationale: explicit form is unambiguous and portable; exact-placeholder preserves ergonomics/back-compat.

## 6. Expression Grammar (v1)

### 6.1 Literals
- `null`, `true`, `false`
- numbers: `123`, `12.34`
- strings: `'...'` and `"..."`

### 6.2 Identifiers and paths
- `state.foo.bar`
- `data.result.items`
- `item.id`
- `index`

**No bracket indexing syntax in v1.**

### 6.3 Operators
Ordered low → high precedence:
1. Ternary: `cond ? a : b`
2. `||`
3. `&&`
4. `==`, `!=`
5. `<`, `<=`, `>`, `>=`
6. `??`
7. `+`, `-` (note `+` is also string concat)
8. `*`, `/`, `%`
9. Unary: `!`, unary `-`
10. Grouping: `(expr)`

### 6.4 Functions (allowlist)
To replace bracket indexing and keep the grammar small and secure, v1 includes a tiny allowlist.

Required:
- `len(x)` → length of string/list/map (else 0)
- `toString(x)`
- `toNum(x)`
- `toInt(x)`

Dynamic access helpers (replaces bracket syntax):
- `get(container, key, defaultValue?)`
  - If `container` is a map and `key` is a string, returns value or default/null.
  - Otherwise returns default/null.
- `at(list, index, defaultValue?)`
  - If `list` is a list and `index` is an int, returns element or default/null.
  - Bounds checked.

Optional (can be v1 or v1.1):
- `trim(s)`, `lower(s)`, `upper(s)`
- `min(a,b)`, `max(a,b)`, `abs(n)`, `round(n)`

Security note: functions are the only extensibility surface in v1, and must remain allowlisted.

## 7. Semantics

### 7.1 Type coercion rules
- `+`:
  - If either operand is a string, coerce both operands to string and concatenate.
  - Else numeric addition if both are numbers (or numeric strings via `toNum` behavior).
- Comparisons:
  - Prefer numeric compare for numbers.
  - String compare only if both are strings.
  - If types are incompatible, result is `false` (and optionally gated debug diagnostic).
- Truthiness:
  - For `&&`, `||`, `?:` conditions: only `true` is truthy; `false`/`null`/others are falsy.
  - This avoids surprising JS-style truthiness.
- `??`:
  - Returns right-hand side only when left-hand side is `null`.

### 7.2 Missing paths
- Any missing path resolves to `null` silently.
- Optional gated debug diagnostics:
  - enabled by a runtime flag in dev builds
  - includes expression text + missing symbol/path

### 7.3 Errors
- Parse error:
  - In template strings: keep literal text and replace failed `${...}` segment with empty string
  - In typed contexts: return `null`
  - Emit gated debug diagnostic
- Evaluation error (e.g., invalid op types):
  - Template: empty string
  - Typed: `null`
  - Emit gated debug diagnostic

## 8. Runtime Integration

### 8.1 Engine API (conceptual)
We add two core APIs:

- `compileTemplate(String)` → TemplateProgram
- `compileExpr(String)` → ExprProgram

Evaluation:
- `evalTemplate(TemplateProgram, Env) -> String`
- `evalExpr(ExprProgram, Env) -> Object?`

`Env` provides read-only accessors:
- `state` (schema state store)
- `data` (schema data scope)
- `item`, `index` (ForEach scope)

### 8.2 Where the engine is used

**(A) Template interpolation in components**
- Any prop that is a string may be treated as a template.

**(B) Actions**
- `set_state`:
  - interpolate `path` as today
  - evaluate `value` using typed rules:
    - strings are templates
    - exact `${...}` returns typed
    - `{ "$expr": "..." }` returns typed
    - maps/lists are recursively traversed for nested templates/exprs

- `patch_state`:
  - interpolate `path` as today
  - for ops `set` and `append`: evaluate the `value` recursively
  - for `increment`: allow `by` to be expression (typed numeric result)

**(C) Conditionals / visibility**
- Extend `If` component to support `props.expr` (string expression expected to yield bool)
  - If `expr` is present, it takes priority over `valuePath/op`.
  - Backward compatible with current `If`.

`visibleWhen.expr` is supported (bounded boolean expression).

### 8.3 Backward compatibility
- Existing `${state.foo}` string interpolation continues to work.
- Existing `If(valuePath/op)` continues to work.
- Typed behavior only triggers for exact single-placeholder strings or `$expr` objects.

## 9. Security Budgets
The engine must enforce budgets to prevent abuse:
- Max expression length (bytes/chars)
- Max tokens / AST nodes
- Max template segments
- Max total output string length
- Max recursion depth for recursive value traversal (actions)

All functions are allowlisted; no reflection; no method calls.

## 10. Performance
- Cache compiled templates and expressions by exact source string (LRU).
- Avoid caching resolved values (they depend on state).
- Use lightweight AST nodes and iterative evaluation where possible.

## 11. Implementation Plan (Phased)

### Phase 0: RFC acceptance
- Review and lock v1 grammar + coercion + function allowlist.

### Phase 1: Dart runtime (authoritative)
- Implement parser (Pratt parser) + evaluator + caching.
- Integrate into:
  - action dispatcher (`set_state`, `patch_state`)
  - `If.props.expr`
- Add unit tests:
  - parsing precedence, ternary behavior, coercion rules
  - missing path behavior
  - budgets
  - `get`/`at` helpers

### Phase 2: TS parity
- Implement same grammar + semantics in `schema_runtime_ts`.
- Cross-check test vectors shared between Dart/TS.

### Phase 3: Schema authoring guidance
- Add docs/examples for `$expr`, `If.expr`, `get/at`.
- Add lints/diagnostics in schema-service (optional).

## 12. Examples

### 12.1 If with expression
```json
{
  "type": "If",
  "props": {
    "expr": "state.pharmacy.cart.totalQuantity > 0 && state.pharmacy.cart.hasRxItem == true"
  },
  "slots": {
    "then": [{ "type": "Text", "props": { "text": "Rx item in cart" } }],
    "else": []
  }
}
```

### 12.2 patch_state with typed increment
```json
{
  "type": "patch_state",
  "value": {
    "ops": [
      { "op": "increment", "path": "pharmacy.cart.totalQuantity", "by": "${toInt(item.delta) ?? 1}" }
    ]
  }
}
```

### 12.3 set_state storing typed object
```json
{
  "type": "set_state",
  "value": {
    "path": "pharmacy.cart.deliveryAddress",
    "value": { "$expr": "state.profile.defaultAddress ?? null" }
  }
}
```

### 12.4 Dynamic access without bracket syntax
```json
{
  "type": "Text",
  "props": {
    "text": "${get(state.user, 'name', 'Guest')}"
  }
}
```

## 13. Open Questions
- Exact set of v1 functions (keep minimal; prefer adding functions over expanding grammar)
- Whether `toNum` should accept localized formats (recommend no)
- Whether comparisons should coerce numeric strings automatically or require `toNum` (recommend conservative)

---

Appendix: Test vector format (recommended)
- Define a shared JSON test vector suite consumable by both Dart and TS implementations:
  - `expr`, `env`, `expected`, `kind` (string/template/typed), and optional `notes`.
