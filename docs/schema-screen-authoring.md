# Schema Screen Authoring Guide

Stable guidance for building and reviewing schema-driven UI screens in the Daryeel customer app.

This guide intentionally avoids a long “widget inventory” list because it becomes outdated quickly.
For the current widget catalogue and repo-specific playbook, use:
- `docs/skills/schema-screen.md`
- `apps/customer-app/lib/src/ui/customer_component_registry.dart` (customer app additions)
- `packages/flutter_components/lib/src/schema_components/core_schema_components.dart` (core widgets)

---

## Document structure

Every screen lives at `apps/customer-app/schemas/screens/<id>.screen.json`:

```json
{
  "schemaVersion": "1.0",
  "id": "my_screen_id",
  "documentType": "screen",
  "product": "customer_app",
  "themeId": "customer-default",
  "themeMode": "light",
  "root": { ... },
  "actions": { ... }
}
```

Theming details (theme ids, modes, inheritance, and where to change what): `docs/theming.md`.

Fragments (`*.fragment.json`) are reusable subtrees. They use `"documentType": "fragment"` with a
single `"node"` key instead of `"root"`. Reference them with:

```json
{ "ref": "fragment:customer_requests_v1" }
{ "ref": "section:customer_welcome_v1" }
```

---

## `ScreenTemplate` — the root of almost every screen

Slots: `header` (rare), `body` (main scrollable content), `footer` (sticky — use `PrimaryActionBar`).

```json
{
  "type": "ScreenTemplate",
  "props": {
    "stateDefaults": { "my.key": "default value" },
    "bodyScroll": true,

    "headerGap": 8,
    "bodyPadding": { "all": 16 },
    "primaryScrollPadding": { "horizontal": 16 },
    "footerPadding": { "left": 16, "top": 0, "right": 16, "bottom": 16 }
  },
  "slots": {
    "body": [ ... ],
    "footer": [ ... ]
  }
}

`ScreenTemplate` is a structural container by default: it applies `SafeArea` for device insets and adds **horizontal gutters** by default, but does **not** add vertical padding or gaps unless you set these props explicitly.
```

---

## Widget catalogue (how to find what’s available)

For “what widgets exist and which props they support”, use these sources (in this order):

1) Repo-specific skill (kept current): `docs/skills/schema-screen.md`
2) Flutter registration code (authoritative):
  - Core widgets: `packages/flutter_components/lib/src/schema_components/core_schema_components.dart`
  - Customer app widgets: `apps/customer-app/lib/src/ui/customer_component_registry.dart`
3) Contracts (what the schema-service validates):
  - Core widget contracts: `packages/component-contracts/contracts/`
  - Customer app widget contracts: `apps/customer-app/contracts/components/`

Rule of thumb: if it’s not registered in the component registries, it’s not renderable.

---

## Expressions and data binding

| Syntax | Resolves to |
|--------|-------------|
| `"${data.field}"` | Value from `RemoteQuery`/`RemotePagedList` scope |
| `"${item.field}"` | Current item inside `ForEach` or list `item` slot |
| `"${index}"` | Current index inside `ForEach` |
| `"$state.path.key"` | Bounded param binding (used in query params; not the expression variable name) |
| `"$route.paramName"` | Bounded param binding (route params) |
| `"$form.formId.fieldKey"` | Bounded param binding (form field value) |

String interpolation in any string prop: `"Hello, ${data.user.name}!"`

For expression syntax (operators, functions, strict boolean rules), use: `docs/skills/expression-engine.md`.

---

## Actions

Actions are declared at the screen root and referenced by name in widgets:

```json
{
  "root": { ... },
  "actions": {
    "go_detail": {
      "type": "navigate",
      "route": "customer.schema_screen",
      "value": { "screenId": "my_screen", "title": "Detail" }
    }
  }
}
```

Widget reference: `"actions": { "tap": "go_detail" }`

### Built-in runtime actions

| type | Key fields | Purpose |
|------|-----------|---------|
| `navigate` | `route`, `value.screenId`, `value.title`, `value.params`, `value.chromePreset` | Push a schema screen |
| `set_state` | `value.path`, `value.value` | Set a value in runtime state |
| `patch_state` | `value.ops` — array of `{op, path, value?}` | Mutate schema state (add / remove / replace) |
| `submit_form` | `formId` | Submit form data to the registered form handler |

Navigate route for all schema screens: `"route": "customer.schema_screen"`

### App-level actions (customer app)

Customer-app-specific action types are defined by:
- Dispatcher: `apps/customer-app/lib/src/actions/customer_action_dispatcher.dart`
- Contracts: `apps/customer-app/contracts/actions/`

Prefer reading the contracts as the schema-author “source of truth” for fields and types.

---

## Design principles

1. **Prefer composition** — exhaust the widget catalogue before proposing a new widget.
2. **Section label pattern** — use `Padding left:20` + `Text variant:label weight:semibold color:secondary` before any grouped list.
3. **Consistent spacing** — `Gap` for vertical rhythm: 8 px (tight), 12 px (normal), 20 px (between sections).
4. **Always cover data states** — every `RemoteQuery`/`RemotePagedList` must have `loading` and `error` slots, even if minimal (`InfoCard surface:subtle`).
5. **Surface hierarchy** — primary content `raised`, supporting info `subtle`, inline/borderless `flat`.
6. **Typography hierarchy** — page/section titles: `variant:title weight:semibold`; body copy: `variant:body`; metadata: `variant:caption color:muted`.
7. **Actions belong in the footer** — form submissions and primary CTAs go in `PrimaryActionBar` in the `footer` slot.
8. **`visibleWhen` vs `If`** — use `visibleWhen` on a node for single-node show/hide; use the `If` component only when you need a multi-node `then`/`else` branch.
9. **Namespace state keys** — always use dotted paths like `pharmacy.cart.notes`, never flat keys.
10. **Extract fragments for reuse** — if the same subtree appears in 2+ screens, extract it to a `.fragment.json`.

---

## When to add a new widget

Work through this decision tree first:

```
Can I compose the UI from existing widgets?
  YES → Do it. No new widget needed.
  NO ↓

Is this pattern reusable across multiple apps / products?
  YES → Add a CORE widget to packages/flutter_components:
    1. Widget Dart class in packages/flutter_components/lib/src/widgets/
    2. Schema component in packages/flutter_components/lib/src/schema_components/
    3. Register in registerCoreSchemaComponents() in core_schema_components.dart
    4. Contract JSON in packages/component-contracts/contracts/
    (Requires explicit user approval before touching packages/*)
  NO ↓

Is this business logic specific to the customer app?
  YES → Add an APP-LEVEL widget:
    1. Widget Dart class in apps/customer-app/lib/src/services/<domain>/ui/
    2. Schema component registration in apps/customer-app/lib/src/ui/customer_component_registry.dart
    3. Contract JSON in apps/customer-app/contracts/components/
  NO ↓

Is this a new action (state mutation or API call)?
  YES → Add to CustomerActionDispatcher in customer_action_dispatcher.dart
        + action contract in apps/customer-app/contracts/actions/
```

**Core package rule**: any change to `packages/*` requires explicit user approval. Always offer a
pure app-layer alternative first.

---

## Key file locations

| What | Where |
|------|-------|
| Screen schemas | `apps/customer-app/schemas/screens/` |
| Fragment schemas | `apps/customer-app/schemas/fragments/` |
| Core widget contracts | `packages/component-contracts/contracts/` |
| App component contracts | `apps/customer-app/contracts/components/` |
| App action contracts | `apps/customer-app/contracts/actions/` |
| Core Flutter widgets | `packages/flutter_components/lib/src/widgets/` |
| Core schema components | `packages/flutter_components/lib/src/schema_components/` |
| Core component registry | `packages/flutter_components/lib/src/schema_components/core_schema_components.dart` |
| Customer app component registry | `apps/customer-app/lib/src/ui/customer_component_registry.dart` |
| App action dispatcher | `apps/customer-app/lib/src/actions/customer_action_dispatcher.dart` |
