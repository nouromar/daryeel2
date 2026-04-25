# Daryeel 2 API design: pharmacy order entities

## Goal

Define the v1 pharmacy order entity model for `services/api`.

This document covers:

- how pharmacy orders relate to the shared `service_requests` spine
- pharmacy-specific order extension data
- normalized order items
- selected pharmacy timing
- fixed-pricing snapshots
- request attachment linkage for prescriptions
- pharmacy status and sub-status guidance

This document does **not** cover catalog entities, provider dispatch, or fulfillment operations after order acceptance.

## Related docs

- `docs/feature_docs/service-request-events-attachments-pricing-v1.md`
- `docs/feature_docs/pharmacy-catalog-entities-design.md`
- `docs/feature_docs/pharmacy-fulfillment-flow-and-entities-design.md`

## Current repo baseline

Today pharmacy order creation in `services/api/app/routers/pharmacy.py`:

- creates a shared `service_requests` row
- stores pharmacy-specific order data inside `payload_json`
- stores pricing inside UI-oriented payload fields such as `summary_lines` and `summary_total`
- stores prescription references inside `payload_json.prescription_upload_ids`
- writes a `request_events` row with type `created`

Current request detail rendering in `services/api/app/routers/requests.py` also derives pharmacy behavior from:

- `service_requests.service_id == "pharmacy"`
- `payload_json.cart_lines`
- `payload_json.summary_total`
- `payload_json.prescription_upload_ids`
- request `status` plus event metadata

This works for demos, but it leaves important order state inside blobs instead of first-class order entities.

## Decisions

### 1. Use `service_requests` as the canonical pharmacy order row

Pharmacy orders use the shared request spine.

That means:

- `service_requests` remains the canonical order/request record
- we do **not** create a duplicate top-level `pharmacy_orders` entity
- pharmacy-specific fields live in a 1:1 extension table

### 2. Add a 1:1 pharmacy extension table

Use a `pharmacy_order_details` table for pharmacy-specific order data that does not belong on every service request.

This keeps the shared spine clean without pushing pharmacy order state into `payload_json`.

### 3. Normalize order items

Use `pharmacy_order_items` for ordered lines.

Each order line references the canonical catalog product through `product_id`.

For v1 simplicity:

- `pharmacy_order_items` should reference `product_id`
- snapshot fields on the order item preserve what was actually purchased at that time

### 4. Fixed pricing for v1

We are not using quotes in v1.

That means:

- `pharmacy_products.price_amount` is the source unit price
- checkout computes the final order pricing
- final pricing is snapshotted onto the order

### 5. Selected pharmacy is set at order creation

For v1 fixed pricing, the selected branch/store should be known when the order is created.

So:

- `pharmacy_order_details.selected_pharmacy_id` should be populated at order creation
- it may later change only if fulfillment reroutes to another branch while preserving the customer-facing order snapshot price

### 6. Prescriptions use shared request attachments

Pharmacy prescription uploads use the shared attachment model:

- `attachments`
- `request_attachments`

For pharmacy:

- `request_attachments.attachment_type = 'prescription'`

### 7. Shared status, pharmacy sub-status

Use:

- `service_requests.status` for the cross-service shared lifecycle
- `service_requests.sub_status` for pharmacy-specific workflow detail

This keeps core request logic portable while still allowing pharmacy-specific operational states.

### 8. ID strategy

For the target entity model in this document:

- use `UUIDv7` for new pharmacy business entities and foreign keys
- keep the current int-based request tables documented only as the current repo baseline
- keep `service_id = 'pharmacy'` as the stable service key

## Recommended v1 entity set

### 1. `service_requests`

Canonical shared order/request row.

Pharmacy v1 should continue to use the shared request spine, but evolve it with a few shared fields:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Target design uses `UUIDv7` |
| `service_id` | varchar(64) | `pharmacy` |
| `customer_person_id` or `customer_user_id` | uuid FK | Depends on broader people/auth migration timing |
| `status` | varchar(64) | Shared request lifecycle |
| `sub_status` | varchar(64) nullable | Pharmacy-specific lifecycle detail |
| `notes` | varchar(500) nullable | Customer note |
| `delivery_address_text` | varchar(255) nullable | Structured request location |
| `delivery_country_code` | varchar(2) nullable | Structured request location |
| `delivery_region_code` | varchar(64) nullable | Structured request location |
| `delivery_city_name` | varchar(128) nullable | Structured request location |
| `delivery_zone_code` | varchar(64) nullable | Structured request location |
| `delivery_lat` | numeric(10,7) nullable | Structured request location |
| `delivery_lng` | numeric(10,7) nullable | Structured request location |
| `delivery_place_id` | varchar(255) nullable | Structured request location |
| `delivery_location_metadata_json` | json/jsonb nullable | Optional extra provider payload |
| `payment_json` | json/jsonb nullable | Payment selection snapshot for now |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

Notes:

- this remains the top-level order identity
- avoid storing pharmacy order lines and pricing totals only in `payload_json`
- for pharmacy/ecommerce, `payload_json` may still be used as a service-extension field for optional or unstable service-specific extras
- `payload_json` is **not** the source of truth for core order state such as selected pharmacy, order items, totals, attachments, or lifecycle state

### 2. `pharmacy_order_details`

1:1 pharmacy extension row for a request.

| Field | Type | Notes |
| --- | --- | --- |
| `request_id` | uuid PK/FK -> `service_requests.id` | One-to-one with request |
| `selected_pharmacy_id` | uuid FK -> `pharmacies.id` | Branch chosen for fulfillment |
| `currency_code` | varchar(3) | ISO currency code |
| `subtotal_amount` | numeric(12,2) | Sum of order-line subtotals before order-level adjustments |
| `discount_amount` | numeric(12,2) | Total order-level discount |
| `fee_amount` | numeric(12,2) | Delivery/service/payment fees combined for v1 |
| `tax_amount` | numeric(12,2) | Total order-level tax |
| `total_amount` | numeric(12,2) | Final customer-visible total |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

Notes:

- this table holds order-wide pharmacy totals
- if fee types need to be split later, add dedicated fee fields or a pricing-breakdown table

### 3. `pharmacy_order_items`

Normalized ordered product lines.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `request_id` | uuid FK -> `service_requests.id` | Owning request |
| `product_id` | uuid FK -> `products.id` | Canonical ordered product |
| `quantity` | integer | Ordered quantity |
| `product_name` | varchar(200) | Snapshot display name |
| `form` | varchar(64) nullable | Snapshot |
| `strength` | varchar(64) nullable | Snapshot |
| `rx_required` | boolean | Snapshot |
| `seller_sku` | varchar(64) nullable | Snapshot branch/seller code |
| `unit_price_amount` | numeric(12,2) | Unit price at order time |
| `line_subtotal_amount` | numeric(12,2) | `quantity * unit price` before line adjustments |
| `line_discount_amount` | numeric(12,2) nullable | Optional line-specific discount |
| `line_tax_amount` | numeric(12,2) nullable | Optional line-specific tax |
| `line_total_amount` | numeric(12,2) | Final line total |
| `created_at` | timestamptz | Audit |

Notes:

- `product_id` remains stable even if fulfillment later reroutes to another pharmacy branch
- snapshot fields preserve what was actually purchased even if catalog data later changes
- customer-facing prices remain authoritative from the order snapshot, not from live catalog rows
- branch/source history should be read from `pharmacy_order_details.selected_pharmacy_id`, `pharmacy_order_assignments`, and `request_events`

## Special v1 order composition cases

### Prescription-only orders

V1 should allow a pharmacy order to start with:

- no `pharmacy_order_items` yet
- prescription `request_attachments`
- zero/nullable order totals until branch review completes

Rule:

- the order must not advance into normal fulfillment until branch review materializes canonical order items and totals

### Mixed orders

V1 should also allow a mixture of:

- canonical submitted `pharmacy_order_items`
- prescription `request_attachments`

If pharmacist/provider or admin/dispatcher propose changes after reviewing the prescription:

- pending proposed changes may live temporarily in `service_requests.payload_json`
- canonical order items and totals remain authoritative until the customer accepts the proposed changes
- if the customer accepts, apply the proposal into canonical order tables
- if the customer rejects, end the order with `rejected` + `customer_rejected_changes`

## Pricing guidance for v1

Because pricing is fixed in v1:

- source price comes from `pharmacy_products.price_amount`
- checkout computes the order total
- the final result is snapshotted across:
  - `pharmacy_order_items` for line-specific amounts
  - `pharmacy_order_details` for order-wide totals

### Item-level amounts

Use `pharmacy_order_items` for:

- `unit_price_amount`
- `line_subtotal_amount`
- optional `line_discount_amount`
- optional `line_tax_amount`
- `line_total_amount`

### Order-level amounts

Use `pharmacy_order_details` for:

- `subtotal_amount`
- `discount_amount`
- `fee_amount`
- `tax_amount`
- `total_amount`

Rule:

- line-specific amounts live on the order line
- shared order-wide amounts live on the order header/extension row

## Attachments

Prescriptions and similar order documents should be linked through:

- `attachments`
- `request_attachments`

Recommended pharmacy usage:

- `request_attachments.request_id` -> the pharmacy order request
- `request_attachments.attachment_type = 'prescription'`
- `request_attachments.uploaded_by_actor_type = 'customer'` for customer-submitted Rx uploads

This replaces `payload_json.prescription_upload_ids` as the source of truth.

## Status guidance

### Shared `service_requests.status`

Keep the shared set small:

- `created`
- `accepted`
- `in_progress`
- `completed`
- `cancelled`
- `rejected`
- `failed`

### Pharmacy `service_requests.sub_status`

Use pharmacy-specific detail here, for example:

- `awaiting_prescription`
- `awaiting_branch_review`
- `awaiting_customer_confirmation`
- `awaiting_stock_confirmation`
- `preparing`
- `ready_for_dispatch`
- `out_for_delivery`
- `delivered`
- `rejected_unavailable`
- `rejected_invalid_prescription`
- `customer_rejected_changes`
- `delivery_failed`
- `unable_to_fulfill`

Notes:

- shared status powers cross-service request lists and summaries
- sub-status gives pharmacy operational detail without bloating the shared status model
- manual phone-confirmation outcomes should be reflected through `awaiting_customer_confirmation` and `customer_rejected_changes` where applicable

## Constraints and indexes

- unique PK/FK on `pharmacy_order_details(request_id)`
- index on `pharmacy_order_details(selected_pharmacy_id)`
- index on `pharmacy_order_items(request_id)`
- index on `pharmacy_order_items(product_id)`

## Implementation impact on current API

- keep pharmacy order creation rooted in `service_requests`
- replace `payload_json.cart_lines` with `pharmacy_order_items`
- replace UI-oriented `summary_lines` / `summary_total` persistence with structured pricing fields
- replace `payload_json.prescription_upload_ids` with `request_attachments`
- evolve request detail rendering to load order lines and pricing from order entities instead of payload blobs

## Non-goals for this document

- pharmacy catalog entities
- dispatch and delivery execution
- substitution workflow design
- inventory reservation strategy
- quote/versioning workflows

## Open follow-ups

- whether `payment_json` should stay on `service_requests` or move to a pharmacy-specific payment selection table later
- whether v1 needs a dedicated field split for fee types instead of one combined `fee_amount`
- whether substitution outcomes should update existing order lines or create explicit replacement line semantics
