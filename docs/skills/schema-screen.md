# Skill — Schema Screen Authoring (Customer App)

This skill is the practical playbook for building or updating schema-driven screens in the Daryeel customer app.

It is intentionally **repo-specific**: the widget list below is based on what is actually registered in the Flutter renderer (core + customer app extensions).

Related docs:
- Widget catalogue + patterns: [docs/schema-screen-authoring.md](../schema-screen-authoring.md)
- Expressions: [docs/skills/expression-engine.md](expression-engine.md)

---

## 1) Before you edit JSON (fast context scan)

Read in parallel:
- `apps/customer-app/schemas/screens/` (similar screens)
- `apps/customer-app/schemas/fragments/` (reusable blocks)
- `apps/customer-app/contracts/actions/` (app action contracts)
- `packages/component-contracts/contracts/` (shared widget contracts)

If you’re changing an existing screen, open that `.screen.json` first.

---

## 2) Screen + fragment structure

### Screen document
Location: `apps/customer-app/schemas/screens/<id>.screen.json`

```json
{
  "schemaVersion": "1.0",
  "id": "my_screen_id",
  "documentType": "screen",
  "product": "customer_app",
  "themeId": "customer-default",
  "themeMode": "light",
  "root": { "type": "ScreenTemplate", "props": {}, "slots": {} },
  "actions": {}
}
```

### Fragment document
Location: `apps/customer-app/schemas/fragments/<id>.fragment.json`

Fragments are reusable subtrees. They use `"documentType": "fragment"` and a single `"node"` key.

---

## 3) Control flow + visibility

- Use `If` when you need a **branch** (`then` vs `else`).
  - `If.props: { "expr": "..." }`
- Use `visibleWhen` when you want to **show/hide a single node**.
  - `visibleWhen: { "expr": "..." }`

Expression guidance and short forms live in: [docs/skills/expression-engine.md](expression-engine.md)

---

## 4) Setting property values with expressions

There are two common cases:

### A) String props (most common)
Many props are strings (e.g. `Text.text`, card titles/subtitles, labels, icon names). These support template interpolation:

- `"text": "Hello, ${data.user.name ?? 'Guest'}"`
- `"title": "Order summary (${len(state.pharmacy.cart.lines)})"`

### B) Typed values (primarily for actions)
Typed expressions (exact placeholder `${...}` or `{ "$expr": "..." }`) are guaranteed in **action payloads** (`set_state`, `patch_state`, etc.).

If you need a non-string prop to be dynamic, confirm that widget supports it (many numeric props are treated as literal numbers).

---

## 5) Widget catalogue (registered today)

This list reflects what’s registered in:
- `packages/flutter_components` (core)
- `apps/customer-app/lib/src/ui/customer_component_registry.dart` (customer app additions/overrides)

### Layout
- `Column`, `Row`, `Stack`, `Wrap`
- `Padding`, `Align`, `SizedBox`, `Expanded`
- `Gap`
- `BottomTabs`

### Typography
- `Text`
- `TextButton`

### Interaction
- `TapArea`
- `Icon`, `IconButton`

### Shell / screen structure
- `ScreenTemplate`

### Cards / sections
- `InfoCard`
- `ActionCard`
- `BoundActionCard`
- `SectionCard` (customer app)

### Control flow / lists
- `If`
- `ForEach`

### Data fetching
- `RemoteQuery`
- `RemotePagedList`

### Checkout / commerce
- `CartItem`
- `CartSummary`
- `CatalogItemTile` (customer app override)
- `PaymentOptionsSection`

### Request detail / timelines
- `StatusTimelinePanel`

### Pharmacy app-specific composites
- `PharmacyCartItems`
- `PharmacyPrescriptionUpload`
- `PharmacyRequestDetailCartItem`

---

## 6) Actions (what schema can trigger)

Actions are defined at the screen root under `actions`, and widgets reference them by name:

```json
"actions": {
  "tap": "go_detail"
}
```

### Core runtime actions
- `navigate` — push a schema screen route (`customer.schema_screen`)
- `set_state` — set a value at a state path (typed evaluation supported)
- `patch_state` — ops: `set`, `remove`, `increment`, `append` (typed evaluation supported)
- `submit_form` — validates + submits the form identified by `formId`

### Customer app actions (examples)
Common customer-app action types include:
- `pharmacy_cart_upsert`, `pharmacy_cart_increment`, `pharmacy_cart_decrement`, `pharmacy_cart_clear`, `pharmacy_cart_refresh_summary`
- `customer_request_action`

Treat app actions as contract-driven: confirm the exact shape in `apps/customer-app/contracts/actions/`.

---

## 7) Quality bar checklist

- Prefer composition over new widgets.
- Keep apps thin: schema + app-level components/actions; avoid touching `packages/*` unless explicitly approved.
- Every remote fetch (`RemoteQuery`/`RemotePagedList`) must have `loading` and `error` slots.
- Use `PrimaryActionBar` in `ScreenTemplate.footer` for primary CTAs.
- Use `len(x) > 0` for non-empty list/map checks.
