# Schema Screen Authoring Guide

Reference for building and reviewing schema-driven UI screens in the Daryeel customer app.
Read this before writing or modifying any `.screen.json` or `.fragment.json` file.

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

## Widget catalogue

### Layout

| Widget | Key props | Slot(s) |
|--------|-----------|---------|
| `Column` | `spacing`, `crossAxisAlignment` (`stretch`/`start`/`end`/`center`), `mainAxisSize` (`min`/`max`) | `children` |
| `Row` | `spacing`, `mainAxisAlignment`, `crossAxisAlignment` | `children` |
| `Stack` | — | `children` |
| `Wrap` | `spacing`, `runSpacing`, `alignment` | `children` |
| `Padding` | `top`, `bottom`, `left`, `right`, `horizontal`, `vertical`, `all` | `child` |
| `Align` | `alignment` (`center`/`topLeft`/`centerRight`/…) | `child` |
| `SizedBox` | `width`, `height` | `child` (optional) |
| `Expanded` | — | `child` — use inside `Row`/`Column` only |
| `Gap` | `height`, `width` | none — pure spacing shorthand |
| `BottomTabs` | `tabs: [{id, label, icon}]` | one slot per tab `id` |

### Typography — `Text`

Props: `text` (supports `${expr}`), `variant`, `weight`, `color`, `align`, `maxLines`, `overflow`, `softWrap`, `size`

| token | values |
|-------|--------|
| `variant` | `title` `subtitle` `body` `label` `caption` |
| `weight` | `regular` `medium` `semibold` `bold` |
| `color` | `default` `muted` `primary` `secondary` `error` |
| `overflow` | `ellipsis` `clip` `fade` |

### Cards

Both `InfoCard` and `ActionCard` share the same typography override props and surface/density tokens.

| Widget | When to use | Tappable? |
|--------|-------------|-----------|
| `InfoCard` | Read-only — status, summary, empty state, error state | No |
| `ActionCard` | Navigates somewhere or triggers an action; supports `icon` | Yes — event: `tap` |
| `BoundActionCard` | Like `ActionCard` but reads title/subtitle/icon/route from data paths. Use inside `ForEach` over API-driven lists | Yes — event: `tap` |

**BoundActionCard props**: `titlePath`, `subtitlePath`, `iconPath`, `routePath`

**Surface tokens** (shared by all cards):

| value | appearance |
|-------|-----------|
| `raised` | Card with shadow — primary content |
| `flat` | No elevation — inline, borderless |
| `subtle` | Slight tint, no shadow — secondary info, empty/error states |

**Density tokens**: `comfortable` (default, more padding) | `compact` (tighter)

**Typography override props** (all cards): `titleVariant`, `titleWeight`, `titleColor`,
`subtitleVariant`, `subtitleWeight`, `subtitleColor` — same token sets as `Text` above.

### Inputs

| Widget | `bind` target | Notes |
|--------|-------------|-------|
| `TextInput` | `"bind": "state.key"` | Props: `label`, `hint`, `testId` |
| `AddressSection` | `"bind": "$state.delivery.address"` | Configured via `sources` object |
| `PaymentOptionsSection` | separate `methodBind` + `timingBind` props | Reads methods/timings from data path |

### Control flow

| Widget | Props | Slots |
|--------|-------|-------|
| `If` | `valuePath` + `op`, or `expr` (CEL expression) | `then`, `else` |
| `ForEach` | `itemsPath` | `item` — use `item.field` and `index` inside |

`op` values for `If`: `isTrue` `isFalse` `isNotEmpty` `isEmpty` `isNull` `isNotNull`

`visibleWhen` — inline conditional on any single node:

```json
"visibleWhen": { "expr": "data.count > 0 and data.label != ''" }
"visibleWhen": { "valuePath": "items", "op": "isNotEmpty" }
```

### Data fetching

| Widget | Use for |
|--------|---------|
| `RemoteQuery` | Single GET, fetched once, cached by `key`. Slots: `loading`, `error`, `child` |
| `RemotePagedList` | Cursor-paginated list with auto-load-more. Slots: `loading`, `error`, `empty`, `item` |

`RemoteQuery` props: `key`, `path`, `params` (values support `$route.param`, `$state.key`)

`RemotePagedList` props: `key`, `path`, `params`, `itemsPath`, `nextCursorPath`, `cursorParam`, `itemKeyPath`

Data from `RemoteQuery` is in scope as `data.*` inside the `child` slot.
Current item in `ForEach` / `RemotePagedList` item slot is `item.*`, current index is `index`.

### Commerce / specialty

| Widget | Notes |
|--------|-------|
| `CartItem` | Single cart line row with quantity controls |
| `CartSummary` | Order summary card; reads `linesPath` + `totalPath` from state |
| `CatalogItemTile` | Product row with Add button; event: `add` |
| `PharmacyCartItems` | Full cart list; app-level composite |
| `PharmacyCheckout` | App-level checkout form composite |

### Navigation / chrome

| Widget | Notes |
|--------|-------|
| `PrimaryActionBar` | Sticky footer buttons. Props: `primaryLabel`, `secondaryLabel`, `expand`, `tone`, `size`. Events: `primary`, `secondary` |
| `Icon` | Material icon by name. Props: `name`, `size`, `color` |
| `IconButton` | Tappable icon. Props: `name`, `size`, `color`, `semanticLabel`. Event: `tap` |
| `TextButton` | Inline text link. Prop: `label`. Event: `tap` |

---

## Expressions and data binding

| Syntax | Resolves to |
|--------|-------------|
| `"${data.field}"` | Value from `RemoteQuery`/`RemotePagedList` scope |
| `"${item.field}"` | Current item inside `ForEach` or list `item` slot |
| `"${index}"` | Current index inside `ForEach` |
| `"$state.path.key"` | Mutable schema state |
| `"$route.paramName"` | Route parameter |
| `"$form.fieldKey"` | Form field value (`TextInput` bind target) |

String interpolation in any string prop: `"Hello, ${data.user.name}!"`

CEL expressions in `visibleWhen`/`If`: `data.x`, `state.x`, `item.x`, `index`, `len(list)`

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
| `patch_state` | `value.ops` — array of `{op, path, value?}` | Mutate schema state (add / remove / replace) |
| `submit_form` | `formId` | Submit form data to the registered form handler |

Navigate route for all schema screens: `"route": "customer.schema_screen"`

### App-level actions (customer app)

| type | Key value fields |
|------|-----------------|
| `pharmacy_cart_upsert` | `id`, `name`, `subtitle`, `rx_required`, `price`, `icon` |
| `pharmacy_cart_increment` | `id` |
| `pharmacy_cart_decrement` | `id` |
| `pharmacy_cart_clear` | — |
| `pharmacy_cart_refresh_summary` | `immediate` (bool), `debounceMs` (number) |
| `customer_request_action` | `mode` (`submit`/`navigate_upload`), `requestId`, `actionId`, `decision`, `screenId`, `title` |

All value fields support `"${expr}"` interpolation.

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
    2. Schema component registered alongside registerCoreSchemaComponents in main.dart
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
| App action dispatcher | `apps/customer-app/lib/src/actions/customer_action_dispatcher.dart` |
