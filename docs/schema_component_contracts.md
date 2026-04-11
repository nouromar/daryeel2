# Schema Component Contracts

## 1. Purpose

This document defines how renderable UI components are exposed to the schema-driven platform.

The goal is to make every component:
- reusable
- typed
- configurable
- versioned
- testable
- safe to render from schema

## 2. Design Rules

### 2.1 High-level but reusable
Components should be meaningful product building blocks, not only low-level layout primitives.

Preferred examples:
- `AddressSection`
- `ContactInfoSection`
- `ProviderCard`
- `QuoteSummaryCard`
- `StatusTimelinePanel`
- `PaymentOptionsSection`

### 2.2 Service-specific only when necessary
Create service-specific components only when the domain cannot be represented cleanly by shared or domain components.

Acceptable service-specific examples:
- `PrescriptionUploadPanel`
- `AmbulanceUrgencyPanel`
- `MedicationSubstitutionPanel`

### 2.3 Safe customization
Schema can customize a component only through declared props, slots, and actions.

### 2.4 Strong defaults
Every component must render sensibly with minimal configuration.

## 3. Component Taxonomy

### 3.1 Shared components
Reusable across many products and services.

Examples:
- `TextField`
- `PhoneField`
- `PrimaryButton`
- `Badge`
- `InfoCard`
- `EmptyState`
- `StatusChip`

### 3.2 Shared sections and panels
Reusable in complete product flows.

Examples:
- `AddressSection`
- `PaymentOptionsSection`
- `RequestSummarySection`
- `QuoteBreakdownSection`
- `TrackingPanel`
- `RatingSection`

### 3.3 Domain components
Reusable within a domain family.

Examples:
- Mobility: `DriverArrivalPanel`, `RideVehicleCard`
- Commerce: `CartItemsSection`, `RecipientSection`
- Healthcare: `ClinicalVisitReasonSection`, `PrescriptionReviewPanel`

### 3.4 Service-specific components
Only for truly unique service workflows.

## 4. Contract Shape

In this repo snapshot, component contracts are defined as JSON documents under:
- `packages/component-contracts/contracts/*.contract.json`
and registered via:
- `packages/component-contracts/catalog.json`

Current extension model (Apr 2026):
- shared/runtime-owned component contracts still live under `packages/component-contracts/`
- app-owned component contracts now live under `apps/<product>/contracts/components/`
- the schema-service merges shared + app component contracts by `product` during validation and contract serving

This lets app-specific widgets stay outside `packages/*` while still participating in the same backend validation model.

Each contract defines:
- `name` (component type string used in schemas)
- `category`
- `version`
- `propsSchema` (prop name -> kind: `string` | `number` | `boolean` | `enum`)
- `defaults` (optional)
- `styleContract` (optional enums for styling-related props)
- `slots` (list of allowed slot names)
- `events` (optional)
- `actions` (optional)
- `fallbackBehavior` (e.g. `omit`, `reject_subtree`)

Concrete example (from `Text`):

```json
{
  "name": "Text",
  "category": "typography",
  "version": "1.0",
  "propsSchema": {
    "text": "string",
    "variant": "enum",
    "size": "number",
    "weight": "enum",
    "color": "enum",
    "align": "enum",
    "maxLines": "number",
    "overflow": "enum",
    "softWrap": "boolean"
  },
  "defaults": {
    "variant": "body",
    "align": "left",
    "maxLines": 1,
    "overflow": "ellipsis",
    "softWrap": false
  },
  "styleContract": {
    "variant": ["body", "label", "caption", "subtitle", "title"],
    "weight": ["regular", "medium", "semibold", "bold"],
    "color": ["default", "muted", "primary", "secondary", "error"],
    "align": ["left", "center", "right"],
    "overflow": ["ellipsis", "clip", "fade"]
  },
  "slots": [],
  "events": [],
  "actions": [],
  "fallbackBehavior": "omit"
}
```

Registration rules:
- When adding a new contract file, add its path to `packages/component-contracts/catalog.json`.
- The schema-service loads the catalog + contracts at runtime and uses them for strict validation before serving schemas.

App-level registration rules:
- When adding an app-specific component contract, add it to `apps/<product>/contracts/components/catalog.json`.
- Keep app contracts product-scoped; do not add service-specific product widgets to the shared package catalog unless they are truly cross-product runtime capabilities.

## 5. Prop Design Guidelines

### 5.1 Prefer enums over free strings
Good:
- `variant: compact | detailed | emphasized`
- `tone: default | success | warning | danger`
- `surface: flat | subtle | raised`

Avoid:
- arbitrary string values that change behavior unpredictably

### 5.2 Prefer bounded objects
Complex props must still be typed and bounded.

### 5.3 Prefer composition over flag explosion
If a component needs too many booleans to express variants, it may need to be split into separate components or use slots.

### 5.4 Safe defaults required
Every prop should either have a default or be clearly required.

## 6. Styling and Theming Contract

Styling should be driven primarily by semantic tokens plus bounded presentation props.

### 6.1 Component styling fields
Every schema-renderable component should define which styling props it supports, such as:
- `variant`
- `tone`
- `size`
- `surface`
- `density`

These props must be enums or other bounded values.

### 6.2 Theme tokens
Components should consume semantic tokens instead of raw style values.

Examples:
- `color.surface.primary`
- `color.text.primary`
- `color.action.brand`
- `space.md`
- `radius.md`
- `elevation.card`

### 6.3 Theme inheritance
Components should behave correctly under inherited themes such as:
- base theme
- product theme
- service theme
- `light` / `dark` mode
- accessibility mode

### 6.4 Bounded overrides only
Components may expose limited styling intent, but should not accept arbitrary style objects as a primary API.

Avoid contract shapes like:
- unrestricted `style` blobs
- arbitrary colors
- arbitrary padding/margin values on every node
- arbitrary font overrides

## 7. Slots

Slots allow composition without making prop shapes unmanageable.

Examples:
- `ScreenTemplate`
  - `header`
  - `body`
  - `footer`
- `SummaryCard`
  - `title`
  - `metadata`
  - `actions`

Slots must be typed:
- what children are allowed
- cardinality rules
- ordering rules

## 8. Actions and Events

Components may emit known events and trigger known actions.

Examples:
- `PrimaryButton` emits `pressed`
- `AddressSection` emits `address_selected`
- `PaymentOptionsSection` emits `payment_method_changed`

Actions must be selected from a platform-defined list.
Components do not invent new action semantics on the fly.

## 9. State Model

Components should define supported visual/interaction states.

Common states:
- `default`
- `loading`
- `empty`
- `error`
- `disabled`
- `success`

This keeps schemas predictable and testable.

## 10. Accessibility and Analytics

Every component contract should define:
- accessibility expectations
- screen reader labels when applicable
- focus behavior
- analytics events emitted by default or optionally

These concerns should not be bolted on later.

## 11. Versioning and Deprecation

Components need lifecycle management.

Rules:
- every contract has a version
- prop changes must be backward compatible unless version is bumped
- deprecated props must have a migration window
- deprecated components should have replacements documented

## 12. Testing Requirements

Each schema-renderable component should have:
- contract validation tests
- rendering tests
- state tests
- theming/variant tests
- accessibility tests
- fallback tests for invalid props
- action/event behavior tests

## 13. Practical Examples

### Shared reusable component
`QuoteSummaryCard`
- Used by taxi, delivery, pharmacy, home visit.

### Domain component
`DriverArrivalPanel`
- Used by mobility services, not necessarily pharmacy.

### Service-specific component
`PharmacyPrescriptionUpload`
- Specific to healthcare/pharmacy workflows.

## 14. Rule of Thumb

Use this decision test:
- If the component can serve multiple services with a clean contract, keep it shared.
- If it fits one domain family well, make it domain-level.
- If it encodes one unique workflow that cannot be generalized cleanly, allow it to be service-specific.