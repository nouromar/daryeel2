# Pharmacy (Marketplace + Ecommerce) — Development Doc

Date: 2026-04-05

## 0) Goal (V1)
Build a pharmacy marketplace experience where **many pharmacies participate**, but the customer sees:
- a **single unified catalog**
- an **estimated (unconfirmed) price**
- a simple, safe checkout

The backend routes each order to the best pharmacy (availability/price/distance/SLA/etc.), and the system supports:
- OTC shopping
- Prescription (Rx) workflow
- price-change confirmation
- substitution confirmation

This doc captures the UI, runtime, and backend work agreed so far.

---

## 1) Customer flows

### 1.1 Single unified flow (OTC + Rx)
Pharmacy is **one** shopping/checkout flow.

Key idea:
- Rx is **not** a special cart item.
- Rx is a normal product with an `rx_required` flag; the catalog UI clearly labels those products (no chip required).
- The cart/order stays a normal cart/order, but can optionally reference an uploaded prescription (`prescriptionUploadId`).
- A prescription is optional at checkout time; the pharmacist/admin/dispatcher can request it later.

### 1.2 Commerce flow
Catalog → Cart (Danbiil) → Checkout (Bixi) → Order Status

Cart behavior:
- If cart contains any `rx_required` products AND no prescription is attached yet, show CTA: **Attach Prescription**.
- Not attaching does **not** block checkout.

Checkout rule:
- Allowed if the customer has **items** OR an attached **prescription** (or both).

Checkout shows **Estimated total (may change)**.

### 1.4 Confirmations (action required)
If pharmacy/admin changes price or proposes substitutions:
- **Price change** → customer must accept/reject → `waiting_price_change_confirmation`
- **Substitution** → customer must accept/reject → `waiting_substitution_confirmation`

If pharmacy/admin needs a prescription after the order is placed:
- **Prescription required** → order enters `waiting_for_prescription` → customer uploads prescription

---

## 2) Pricing & substitutions

### 2.1 Unified price
- Display a unified **estimated** price (e.g., smallest price / best estimate).
- Treat it as **unconfirmed**.

### 2.2 Price change confirmation
If final price differs from estimate:
- transition to `waiting_price_change_confirmation`
- present old total vs new total
- customer chooses: Accept / Cancel

### 2.3 Substitution confirmation
If item substitution is required:
- propose explicit substitutions (from → to)
- include reason and price delta if applicable
- customer chooses: Accept / Reject

---

## 3) Payments (V1)
Start with cash / “digital cash” (mobile money) with a simple UX:
- `payment.method`: `cash` | `mobile_money`
- `payment.timing`: `before_delivery` | `after_delivery`

---

## 4) UI work: shared Commerce vs Pharmacy-specific

### 4.1 Shared Commerce components (reusable)
These should be reusable beyond Pharmacy (delivery/marketplace later):

**Catalog**
- Search input (debounced)
- Product list/grid + product tile
- Add/remove quantity controls
- Rx-required products clearly labeled (chip or styling)

**Cart**
- Cart items list + qty editing
- Cart summary (estimated total + disclaimer)
- Empty cart state

**Checkout**
- Delivery address (shared Address/Location picker)
- Payment method + timing
- Notes
- Submit order

**Prescription attachment (unified flow)**
- Cart CTA: “Attach Prescription” (only when cart has Rx items and no attachment)
- Checkout can optionally include an attach/replace action

**Order status & action-required**
- Order status panel
- Price change confirmation panel
- Substitution confirmation panel
- Prescription-required panel (upload prompt)
- Timeline/events panel (optional for V1; recommended)

### 4.2 Pharmacy-specific components
Keep this layer minimal.

**Prescription (used by the unified flow)**
- Prescription upload panel (camera/gallery, preview/remove)
- Optional Rx notes + “allow substitutions” toggle (can live in checkout notes or a small Rx section)

**Rx follow-up (optional in V1)**
- Needs-more-info panel (if pharmacy requests clarification)

### 4.3 Screens (schema documents)

**Shared Commerce screens**
- `commerce_catalog`
- `commerce_cart`
- `commerce_checkout`
- `commerce_order_status`
- `commerce_action_required` (confirm price/substitution)

**Pharmacy screens**
- `pharmacy_shop` (catalog entry)
- `pharmacy_prescription_upload` (invoked from “Attach Prescription”)

---

## 5) Location picker (shared) + map pin picker
Location picking is a shared capability across ride/ambulance/home visit/delivery/pharmacy.

### 5.1 Architecture
- **MapPinPicker** is a reusable UI widget/component.
- **Address picker (AddressSection)** is the orchestrator:
  - recents
  - saved places
  - current location
  - backend-powered autocomplete
  - a “Choose on map” option that opens MapPinPicker

### 5.2 Map pick option
Add “Choose on map” inside the Address picker:
- open full-screen map with draggable pin
- confirm → reverse-geocode → set bound field

### 5.3 Data binding shape
We standardize the bound location value to the backend’s structured location shape:

```json
{
  "address_text": "Hodan, Mogadishu — near XYZ",
  "country_code": "SO",
  "region_code": "banadir",
  "city_name": "Mogadishu",
  "zone_code": "hodan",
  "lat": 2.046934,
  "lng": 45.318162,
  "accuracy_m": 15,
  "place_id": "optional",
  "location_metadata": {}
}
```

Implementation note:
- the runtime’s form store must support safe JSON-like maps/lists (not only primitives) so we can store the structured location.

---

## 6) Runtime work (schema-driven features)

### 6.1 Better form capability (required)
Enable the form store to hold **bounded JSON-like values** (Map/List/primitives), so components can bind structured values like locations and cart payloads.

### 6.2 Fetching + rendering + pagination (already present; adopt in schemas)
The runtime already includes a bounded query system:
- `SchemaQueryStore` supports `executeGet` and `executePagedGet`.
- Schema components exist to render remote data:
  - `RemoteQuery` (fetch once per key/signature)
  - `RemotePagedList` (pagination + `loadMorePagedGet`)
  - `ForEach` (render local list from data scope)

To use them in an app, ensure they’re registered in that app’s widget registry.

---

## 7) Backend entities (Pharmacy marketplace + routing)

### 7.1 Spine (shared)
Follow the platform spine model:
- `ServiceDefinition` (`slug = pharmacy`)
- `ServiceRequest` (the order)
- `RequestEvent` (append-only timeline)
- `Quote` (optional: estimated vs final)
- `PaymentIntent` / `PaymentRecord`

### 7.2 Marketplace/catalog entities
- `Pharmacy` (or Organization + capability model)
- `Product` (unified catalog)
- `PharmacyOffer`/`PharmacyProduct` (per-pharmacy price + stock)

### 7.3 Routing
- `RoutingAttempt` (request_id, selected pharmacy, scoring metadata)

### 7.4 Confirmations (price/substitution)
- `CustomerConfirmationRequest`
  - type: `price_change` | `substitution` | `prescription_required` | `rx_clarification`
  - status: `pending` | `accepted` | `rejected` | `expired`
  - proposed payload: new total, substitutions list, message

### 7.5 Attachments (Rx)
- `Attachment` (type `prescription_photo`, url, created_by_actor)

---

## 8) Backend endpoints (minimum)

### Catalog
- `GET /v1/pharmacy/catalog` (unified catalog + estimated prices)
  - Include `rx_required: boolean` per product so clients can render the Rx chip.

### Orders
- `POST /v1/pharmacy/orders` (create ServiceRequest)
- `GET /v1/pharmacy/orders/active` (active/current order for the user)

### Confirmations
- `POST /v1/pharmacy/orders/active/confirm_price` (accept/reject)
- `POST /v1/pharmacy/orders/active/confirm_substitution` (accept/reject)

### Prescription upload (unified flow)
- `POST /v1/pharmacy/orders/active/upload_prescription` (attach/replace Rx images)
  - Returns a `prescriptionUploadId` (or similar) that can be referenced by the cart/order.

### Location services
- `GET /locations/autocomplete?q=…&biasLatLng=…`
- `GET /locations/details?placeId=…`
- `GET /locations/reverse_geocode?lat=…&lng=…`

---

## 9) Open decisions
- Allow multiple active pharmacy orders per customer vs “one active at a time”.
- V1 map provider choice (Google Maps vs alternatives) and key management strategy.

---

## 10) Tracked checklist (milestones)

Use this as the living, tickable plan for V1. Keep items small enough to ship and verify.

### M0 — Runtime enablement (schema can build real commerce)
- [x] Form store supports bounded structured values (Map/List) for location/cart payloads.
  - Done when: structured values persist through form updates without stringifying.
  - Tests: `cd packages/flutter_runtime && flutter test`
- [x] Register data components in the customer app component registry: `RemoteQuery`, `RemotePagedList`, `ForEach`.
  - Done when: a schema screen can fetch and render a paged list end-to-end.
  - Tests: `cd apps/customer-app && flutter test && flutter analyze`

### M1 — Backend foundation (catalog + orders)
- [x] `GET /v1/pharmacy/catalog` returns unified catalog with cursor pagination and estimated prices.
  - Done when: supports `q`, `cursor`, `limit`; stable ordering; returns next cursor.
  - Tests: `cd services/api && pytest -q` (add focused tests for pagination + filtering)
- [x] `POST /v1/pharmacy/orders` creates a pharmacy ServiceRequest (OTC) and emits initial RequestEvents.
  - Done when: request contains cart lines, delivery location object, payment choice, notes.
  - Tests: `cd services/api && pytest -q` (request creation + validation)

### M2 — Commerce UI (OTC shopping)
### M2 — Commerce UI (OTC + Rx unified)
- [x] Pharmacy shop entry routes to a single catalog-first experience.
  - Done when: reachable from home and shows catalog.
  - Tests: `cd apps/customer-app && flutter test && flutter analyze`
- [x] Catalog screen renders from backend using `RemotePagedList` (search + infinite scroll).
  - Done when: typing in search triggers refetch; scrolling loads more.
- [x] Product tiles clearly label Rx-required products when `rx_required` is true.
  - Done when: Rx products are clearly labeled in catalog results (styling or chip).
- [ ] Cart (Danbiil) supports OTC-only and mixed carts, with conditional CTA: “Attach Prescription”.
  - Done when: CTA appears only if Rx items exist and no prescription is attached; checkout still works.
  - Done when: cart lives in form state as structured JSON-like payload.

### M3 — Checkout submit (real networking)
- [ ] Checkout screen collects address + payment method/timing + notes and submits an order.
  - Done when: `submit_form` is handled by a real submit handler for this flow.
  - Tests: add a widget test for submit wiring (happy path + error state)

### M4 — Order status + action-required confirmations
- [ ] Order status screen renders current order + event timeline.
  - Done when: polling or refresh updates status transitions correctly.
- [ ] Price change confirmation UI + endpoint wiring.
  - Done when: accept/reject updates order state and events.
- [ ] Substitution confirmation UI + endpoint wiring.
  - Done when: accept/reject updates line items and totals.

### M5 — Rx workflow (upload prescription)
### M5 — Rx workflow (attachment + waiting state)
- [ ] Prescription upload screen (camera/gallery, preview/remove) binds attachments to a `prescriptionUploadId`.
  - Done when: the app can attach/replace/remove the prescription before or after checkout.
- [ ] Order status supports `waiting_for_prescription` and prompts the customer to upload.
  - Done when: pharmacist/admin can request Rx and the customer can attach it post-checkout.
- [ ] Backend supports post-checkout Rx upload (`upload_prescription`) and links it to the order.
  - Done when: uploaded Rx is visible in the order payload and emits a RequestEvent.

### M6 — Location picker (Uber-like) + map pin picker
- [ ] Address picker supports: autocomplete, recents, saved, current location, “Choose on map”.
  - Done when: selecting any source produces the standardized location object in form state.
- [ ] Map pin picker supports: drag pin, confirm, reverse-geocode.
  - Done when: reverse-geocode endpoint populates `text` and lat/lng accurately.
