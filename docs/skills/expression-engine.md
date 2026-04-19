# Skill — Expression Engine (Schema Runtime)

This skill teaches you how to **write safe, readable expressions** for the Daryeel schema runtime.

It’s intentionally **not** a scripting language: expressions are one-line, deterministic, side-effect free, and run in a sandbox.

Sources of truth:
- The feature set and intent are described in [docs/expression-engine-rfc.md](../expression-engine-rfc.md).
- The Dart implementation lives in `packages/flutter_runtime/lib/src/bindings/schema_expression_engine.dart`.

---

## 1) Where expressions are used

### A) Template interpolation inside strings
Any string prop can contain `${...}` segments.

Examples:
- `"Items: ${state.pharmacy.cart.totalQuantity}"`
- `"${item.title} • ${item.quantity}"`
- `"${data.user.name ?? 'Guest'}"`

Rule: template interpolation always produces a **String**.

### B) Setting component property values (most commonly strings)
In practice, the expression engine is also how you make many **props dynamic**.

- If a prop is a **string** (e.g., `text`, `title`, `subtitle`, `label`, `semanticLabel`, many icon names), you can use `${...}` inside it.
- The runtime will evaluate those `${...}` segments and produce the final string.

Examples:
- `"title": "Order summary (${len(state.pharmacy.cart.lines)})"`
- `"text": "Hello, ${data.user.name ?? 'Guest'}"`

Important limitation:
- The runtime does **not** automatically evaluate expressions for *all* props.
  - Many non-string props (e.g., `size` numbers) are read as literal numbers; putting `${...}` there usually won’t work unless the component explicitly supports it.

### C) Control flow (`If`)
Prefer expression form:

- `If.props: { "expr": "..." }`

### D) Visibility gating (`visibleWhen`)
Use `visibleWhen` when you want to conditionally show/hide a single node.

- `visibleWhen: { "expr": "..." }`

### E) Typed values (actions, payloads, non-string values)
Use typed evaluation when you need a **Map/List/num/bool** (not a string):

1) Exact placeholder typed rule:
- If a string is exactly `${...}` (after trimming), it evaluates to the **typed** value.
  - Example: `"${state.pharmacy.cart.deliveryAddress}"` evaluates to the underlying object.

2) Explicit typed object (canonical):
- `{ "$expr": "state.pharmacy.cart.deliveryAddress" }`

---

## 2) Scopes (what names mean)

Expressions resolve identifiers against these roots:

- `state` — schema runtime state store (`$state.*` paths in schema bindings)
- `data` — `RemoteQuery` / `RemotePagedList` result scope
- `item` and `index` — inside `ForEach` / list item slots
- `params` — route params

Missing paths resolve to `null` (silently in prod).

---

## 3) Operators and semantics (the safe mental model)

Supported operators:
- Arithmetic: `+ - * / %`
- Comparisons: `== != < <= > >=`
- Boolean: `&& || !`
- Nullish: `??`
- Ternary: `cond ? a : b`

Important semantics:
- **Strict booleans**: only the literal `true` is treated as true in `&&`, `||`, and ternary conditions.
  - Prefer `flag == true` for optional booleans.
- `??` only checks for `null`.
  - It will **not** treat `''` (empty string) as missing.

---

## 4) Function allowlist (implemented)

These functions are supported in Dart runtime (and intended to match TS runtime behavior):

### Null and emptiness
- `isNull(x)` → `true` iff `x == null`
- `isNotNull(x)`

- `isEmpty(x)`
  - Strings: empty string is empty
  - Lists/Maps: `.isEmpty`
  - **Note:** `isEmpty(null)` is `false`

- `isNotEmpty(x)`
  - **Note:** `isNotEmpty(null)` is `true` (because `isEmpty(null)` is `false`)

- `isBlank(x)`
  - Strings: trims whitespace and checks empty
  - Lists/Maps: empty
  - **Note:** `isBlank(null)` is `true`

- `isNotBlank(x)`
  - **Note:** `isNotBlank(null)` is `false`

### Length and conversion
- `len(x)` → length of `String`/`List`/`Map`, otherwise `0`
- `toString(x)` → `''` for null, else `x.toString()`
- `toNum(x)` → numeric conversion (or `null` if not numeric)
- `toInt(x)` → integer conversion (or `null`)

### Safe access helpers (instead of bracket indexing)
- `get(container, key, defaultValue?)`
  - Map + string key → value (or `defaultValue` / `null`)
- `at(list, index, defaultValue?)`
  - List + int index → element (or `defaultValue` / `null`), bounds-checked

---

## 5) Best-practice patterns (copy/paste)

### 5.1 “Non-empty list” (recommended)
Use `len(x) > 0`.

Why: `len(null) == 0`, so it’s null-safe and short.

Examples:
- `"expr": "len(state.pharmacy.cart.lines) > 0"`
- `"expr": "len(timeline) > 0"`

Avoid:
- `x != null && len(x) > 0` (verbose)
- `isNotEmpty(x)` (can behave surprisingly for `null`)

### 5.2 Optional string with fallback label
Use blank-aware checks:

- `isNotBlank(data.request.notes) ? data.request.notes : '—'`

Use `??` only when empty-string is a valid value:

- `(data.user.name ?? 'Guest')`

### 5.3 Optional boolean flags
Prefer explicit compare:

- `serviceDetails.isPharmacy == true`

Avoid:
- `serviceDetails.isPharmacy` (if it might be `null`, it won’t behave like JS truthiness)

### 5.4 Safe map/list access
When API payload shape may vary:

- `get(data.request, 'subtitle', '')`
- `at(data.items, 0, null)`

### 5.5 Composing display strings
Prefer one string with template segments:

- `"text": "Total: ${data.total ?? 0}"`

Or use ternary for conditional segments:

- `"text": "${len(data.badges) > 0 ? 'Has badges' : ''}"`

### 5.6 Typed payloads in actions
When you need to set state to a whole object:

```json
{
  "type": "set_state",
  "value": {
    "path": "pharmacy.cart.deliveryAddress",
    "value": { "$expr": "data.selectedAddress" }
  }
}
```

When you need a typed list/map nested inside a larger object, prefer `$expr` at the specific leaf.

---

## 6) Debugging & safety tips

### Debug diagnostics (dev only)
The engine can emit debug diagnostics when missing paths or eval errors occur.

- Compile-time flag: `DARYEEL_SCHEMA_EXPR_DIAGNOSTICS` (defaults to `false`)

### Keep expressions readable
- Prefer one-liners that read like English.
- Use `len(x) > 0`, `isNotBlank(s)`, and `flag == true` to avoid subtle null behavior.
- If an expression gets long, consider splitting UI: a small `If` + two simple branches is often clearer than a huge ternary.

---

## 7) Quick review checklist

Before shipping a schema change that uses expressions:
- Does it handle `null` safely?
- If checking “non-empty list/map/string”, is it using the right primitive (`len` / `isNotBlank`)?
- Are booleans compared explicitly (`== true`) when the value might be nullable?
- If the expression feeds a non-string prop/action payload, is it using `$expr` or exact-placeholder typing?
- Is the expression short enough that another person can maintain it?
