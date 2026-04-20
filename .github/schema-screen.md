# Schema Screen Development Skill

You are helping build a **schema-driven UI screen** for the Daryeel customer app.
Read this entire prompt before acting. Follow its steps in order.

---

## What the user wants

The user invoked `/schema-screen` — they want to design and implement a new (or improved) screen
using the JSON schema UI system. Their request may be:

- A description of a new screen ("build a lab results screen")
- A refinement to an existing screen ("make the checkout screen show a promo code field")
- A question about how to wire up a widget or action

Understand their intent, then proceed through the steps below.

---

## Step 1 — Discover context

Before writing any JSON, run these reads in parallel to understand what already exists:

1. `apps/customer-app/schemas/screens/` — existing screen files (patterns to follow)
2. `apps/customer-app/schemas/fragments/` — reusable fragment subtrees
3. `packages/component-contracts/contracts/` — every available widget and its props/style contract
4. `apps/customer-app/contracts/actions/` — app-level action contracts

If the request touches an existing screen, read that screen file first.

---

## Step 2 — Understand the system

### Document structure

Every screen is a JSON file at `apps/customer-app/schemas/screens/<id>.screen.json`:

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

Fragments live at `apps/customer-app/schemas/fragments/<id>.fragment.json` and have
`"documentType": "fragment"` with a single `"node"` instead of `"root"`.

### Root widget

Almost every screen root is `ScreenTemplate` with three slots:

| Slot | Purpose |
|------|---------|
| `header` | Optional; rare — the app bar is usually provided by the navigator |
| `body` | Main scrollable content |
| `footer` | Sticky bottom area — use `PrimaryActionBar` here |

`ScreenTemplate` accepts:
- `"stateDefaults": { "key": value }` — initialise mutable state keys
- `"bodyScroll": true` (default) / `false`

---

### Widget catalogue

#### Layout
| Widget | Key props | Notes |
|--------|-----------|-------|
| `Column` | `spacing`, `crossAxisAlignment` (`stretch`\|`start`\|`end`\|`center`), `mainAxisSize` (`min`\|`max`) | Default slot: `children` |
| `Row` | `spacing`, `mainAxisAlignment`, `crossAxisAlignment` | Default slot: `children` |
| `Stack` | — | Default slot: `children` |
| `Wrap` | `spacing`, `runSpacing`, `alignment` | Default slot: `children` |
| `Padding` | `top`, `bottom`, `left`, `right`, `horizontal`, `vertical`, `all` | Single slot: `child` |
| `Align` | `alignment` (`center`\|`topLeft`\|`centerRight`\|…) | Single slot: `child` |
| `SizedBox` | `width`, `height` | Single slot: `child` (optional) |
| `Expanded` | — | Single slot: `child` — use inside Row/Column only |
| `Gap` | `height`, `width` | No slots — pure spacing shorthand |
| `BottomTabs` | `tabs` array `[{id, label, icon}]` | Slots named by each tab `id` |

**Section label pattern** (used throughout codebase):
```json
{
  "type": "Padding",
  "props": { "left": 20 },
  "slots": { "child": [{ "type": "Text", "props": { "text": "Section title", "variant": "label", "weight": "semibold", "color": "secondary" } }] }
}
```

#### Typography — `Text`
Props: `text` (supports `${expr}`), `variant`, `weight`, `color`, `align`, `maxLines`, `overflow`, `softWrap`

| token | values |
|-------|--------|
| `variant` | `title` `subtitle` `body` `label` `caption` |
| `weight` | `regular` `medium` `semibold` `bold` |
| `color` | `default` `muted` `primary` `secondary` `error` |
| `overflow` | `ellipsis` `clip` `fade` |

#### Cards
Both `InfoCard` and `ActionCard` share the same typography props (`titleVariant`, `titleWeight`, `titleColor`, `subtitleVariant`, `subtitleWeight`, `subtitleColor`) and surface/density tokens.

| Widget | When to use |
|--------|-------------|
| `InfoCard` | Read-only display — status, summary, empty states, error states |
| `ActionCard` | Tappable — navigates somewhere or triggers an action. Supports `icon`. Event: `tap` |
| `BoundActionCard` | Like `ActionCard` but reads title/subtitle/icon/route from data paths (`titlePath`, `subtitlePath`, `iconPath`, `routePath`). Use inside `ForEach` over API-driven lists |

**Surface tokens** (shared by all cards):
- `raised` — default card with shadow (primary content)
- `flat` — no elevation (inline, borderless)
- `subtle` — slight tint, no shadow (secondary info, empty states)

**Density tokens**: `comfortable` (default, more padding) | `compact` (tighter)

#### Inputs
| Widget | Bind target | Notes |
|--------|-------------|-------|
| `TextInput` | `"bind": "state.key"` | `label`, `hint`, `testId` |
| `AddressSection` | `"bind": "$state.delivery.address"` | Configured via `sources` object |
| `PaymentOptionsSection` | `methodBind` + `timingBind` props | Reads methods/timings from data path |

#### Control flow
| Widget | Props | Slots |
|--------|-------|-------|
| `If` | `valuePath` + `op` **or** `expr` (CEL) | `then`, `else` |
| `ForEach` | `itemsPath` | `item` — use `item.field` and `index` inside |

`op` values for `If`: `isTrue` `isFalse` `isNotEmpty` `isEmpty` `isNull` `isNotNull`

`visibleWhen` — inline conditional on any node:
```json
"visibleWhen": { "expr": "data.count > 0 and data.label != ''" }
```
or
```json
"visibleWhen": { "valuePath": "items", "op": "isNotEmpty" }
```

#### Data fetching
| Widget | Use for |
|--------|---------|
| `RemoteQuery` | Single GET — fetched once, cached by `key` |
| `RemotePagedList` | Cursor-paginated list with auto-load-more |

`RemoteQuery` props: `key`, `path`, `params` (values support `$route.param`, `$state.key`)
Slots: `loading`, `error`, `child` (data is in scope as `data.*`)

`RemotePagedList` props: `key`, `path`, `params`, `itemsPath`, `nextCursorPath`, `cursorParam`, `itemKeyPath`
Slots: `loading`, `error`, `empty`, `item` (item in scope as `item.*`, index as `index`)

#### Commerce / specialty
| Widget | Notes |
|--------|-------|
| `CartItem` | Single cart line row with quantity controls |
| `CartSummary` | Order summary card; reads `linesPath` + `totalPath` from state |
| `CatalogItemTile` | Product row with Add button; event: `add` |
| `PharmacyCartItems` | Full cart list; app-level composite widget |
| `PharmacyCheckout` | App-level checkout form composite |

#### Navigation / chrome
| Widget | Notes |
|--------|-------|
| `PrimaryActionBar` | Sticky footer button(s). Props: `primaryLabel`, `secondaryLabel`, `expand`, `tone`, `size`. Events: `primary`, `secondary` |
| `Icon` | Material icon by name. Prop: `name`, `size`, `color` |
| `IconButton` | Tappable icon. Props: `name`, `size`, `color`, `semanticLabel`. Event: `tap` |
| `TextButton` | Inline text link. Prop: `label`. Event: `tap` |

---

### Expressions and data binding

| Syntax | Resolves to |
|--------|-------------|
| `"${data.field}"` | Value from RemoteQuery/ForEach scope |
| `"${item.field}"` | Current item inside ForEach |
| `"${index}"` | Current index inside ForEach |
| `"$state.path.key"` | Mutable schema state |
| `"$route.paramName"` | Route parameter |
| `"$form.fieldKey"` | Form field value (TextInput bind target) |
| CEL expr in `visibleWhen` | `data.x`, `state.x`, `item.x`, `index`, `len(list)` |

String interpolation inside `props.text` etc: `"Hello, ${data.user.name}!"`

---

### Actions

Actions are defined at the screen root under `"actions": { "actionId": { ... } }`.
Widgets reference them by name: `"actions": { "tap": "my_action_id" }`.

#### Built-in runtime actions

| type | Required fields | What it does |
|------|----------------|--------------|
| `navigate` | `route`, `value.screenId`, optional `value.title`, `value.params`, `value.chromePreset` | Push a schema screen |
| `patch_state` | `value.ops` — array of `{op, path, value?}` | Mutate schema state (add/remove/replace) |
| `submit_form` | `value.formId` (or `formId` directly) | Submit form data |

Navigate route for schema screens: `"route": "customer.schema_screen"`

#### App-level actions (CustomerActionDispatcher)

| type | Key value fields |
|------|-----------------|
| `pharmacy_cart_upsert` | `id`, `name`, `subtitle`, `rx_required`, `price`, `icon` |
| `pharmacy_cart_increment` | `id` |
| `pharmacy_cart_decrement` | `id` |
| `pharmacy_cart_clear` | — |
| `pharmacy_cart_refresh_summary` | `immediate` (bool), `debounceMs` (number) |
| `customer_request_action` | `mode` (`submit`\|`navigate_upload`), `requestId`, `actionId`, `decision`, `screenId`, `title` |

All value fields support `"${expr}"` interpolation.

---

### Fragments and refs

Reuse a fragment inline:
```json
{ "ref": "fragment:customer_requests_v1" }
```
or a section:
```json
{ "ref": "section:customer_welcome_v1" }
```

---

## Step 3 — Design principles (apply these)

1. **Prefer existing widgets** — exhaust the catalogue above before considering a new widget.
2. **Section label pattern** — use `Padding left:20` + `Text variant:label weight:semibold color:secondary` before any grouped list.
3. **Consistent spacing** — use `Gap` for vertical rhythm (8px tight, 12px normal, 20px section).
4. **States always covered** — every `RemoteQuery` / `RemotePagedList` must have `loading` and `error` slots, even if minimal (`InfoCard surface:subtle`).
5. **Surface hierarchy** — primary content `raised`, supporting info `subtle`, inline/borderless `flat`.
6. **Typography hierarchy** — page/section titles: `variant:title weight:semibold`. Body copy: `variant:body` (default). Metadata/timestamps: `variant:caption color:muted`.
7. **Actions in footer** — form submissions and primary CTAs belong in `PrimaryActionBar` in the `footer` slot, not inline in the body.
8. **`visibleWhen` not `If` for simple toggles** — use `visibleWhen` on a node for single-node show/hide; use `If` component only when you need a multi-node `then`/`else` branch.
9. **State keys are namespaced** — use dotted paths like `pharmacy.cart.notes`, never flat `notes`.
10. **Fragments for reuse** — if the same subtree appears in 2+ screens, extract to a fragment.

---

## Step 4 — When to add a new widget

Work through this decision tree before proposing new Flutter code:

```
Can I compose the UI from existing widgets?
  YES → Do it. No new widget needed.
  NO ↓

Is this pattern reusable across multiple apps / products?
  YES → Add a core widget to packages/flutter_components:
           1. Create widget Dart class in lib/src/widgets/
           2. Create schema component in lib/src/schema_components/
           3. Register in registerCoreSchemaComponents() in core_schema_components.dart
           4. Add contract JSON in packages/component-contracts/contracts/
  NO ↓

Is this business logic specific to the customer app?
  YES → Add an app-level widget:
           1. Create widget Dart class in apps/customer-app/lib/src/services/<domain>/ui/
           2. Create schema component (register it alongside registerCoreSchemaComponents call in main.dart)
           3. Add contract JSON in apps/customer-app/contracts/components/
  NO ↓

Is this a new action (state mutation or API call)?
  YES → Add to CustomerActionDispatcher in customer_action_dispatcher.dart
        + add action contract in apps/customer-app/contracts/actions/
```

**Rule**: always prefer composition. A new widget is justified only when the Flutter-level
behaviour cannot be achieved by combining existing widgets (e.g. custom gesture, animation,
native capability, complex stateful widget with its own controller).

---

## Step 5 — Deliver

1. **Show the complete screen JSON** (or the changed portion) — never partial/placeholder snippets.
2. If adding a new widget, show:
   - The contract JSON
   - The schema component Dart registration
   - The widget Dart class
   - The line to add in `registerCoreSchemaComponents` or the app setup
3. If adding a new action, show the action contract and the dispatcher code.
4. Keep explanations brief — the user can read the code.
5. Validate your output mentally: every widget references only props it declares in its contract;
   every action `type` is registered; every `ref` points to an existing fragment id.
