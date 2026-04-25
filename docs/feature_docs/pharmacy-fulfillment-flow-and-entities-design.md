# Daryeel 2 API design: pharmacy fulfillment flow and entities

## Goal

Define the v1 pharmacy fulfillment flow and the minimum fulfillment-side entities needed in `services/api`.

This document covers:

- the end-to-end fulfillment flow after order creation
- rerouting across pharmacy branches while preserving the customer-facing order price
- manual phone confirmation for pharmacist/admin-proposed changes
- exception handling
- the minimum assignment model needed for branch and delivery ownership

This document does **not** redesign the catalog or top-level order model.

## Related docs

- `docs/feature_docs/pharmacy-catalog-entities-design.md`
- `docs/feature_docs/pharmacy-order-entities-design.md`
- `docs/feature_docs/service-request-events-attachments-pricing-v1.md`

## Current repo baseline

Today pharmacy workflow behavior is largely inferred from:

- `service_requests.status`
- pharmacy-specific interpretation of `payload_json`
- `request_events`
- request-detail helpers that derive pending actions from status plus event metadata

There is no dedicated fulfillment assignment entity yet, and rerouting is not explicitly modeled.

## Decisions

### 1. Keep v1 simple but complete

V1 should support a real pharmacy operational flow without introducing full marketplace routing or quote complexity.

Assumptions:

- product-first shopping
- fixed pricing
- selected pharmacy branch known at order creation
- one branch fulfills the order at a time
- no full substitution workflow
- customer confirmation of pharmacist/admin changes may happen by phone

### 2. Fulfillment stays rooted in the shared request spine

Use:

- `service_requests.status`
- `service_requests.sub_status`
- `request_events`

as the core fulfillment state model.

We do **not** add separate exception entities in v1.

### 3. Rerouting is allowed while preserving order snapshot prices

If the selected pharmacy branch cannot fulfill:

- the system may try another pharmacy branch
- the customer-facing order price remains the snapshotted order price
- the order does not need repricing or quote logic in v1

### 4. One order may have many fulfillment assignments over time

Use multiple assignment rows over time rather than overwriting one row.

This allows:

- initial branch assignment
- branch rerouting
- internal reassignment within a branch
- delivery assignment

Only one assignment of a given active phase should be current at a time.

### 5. Manual customer confirmation is supported in v1

If a pharmacist/provider or admin/dispatcher derives or changes the order contents:

- the system may move the order to `awaiting_customer_confirmation`
- the customer may be called manually
- the pharmacist/provider or admin/dispatcher may record the acceptance/rejection outcome

If the customer rejects the changes:

- the order ends in `rejected` + `customer_rejected_changes`

### 6. Prescription-only and mixed orders are valid

V1 must support:

- prescription-only orders with no initial order items
- mixed orders containing selected items plus a prescription attachment

For these cases:

- accepted/canonical order items stay in `pharmacy_order_items`
- prescription documents stay in `request_attachments`
- pending proposed changes may live temporarily in `service_requests.payload_json` until confirmed

### 7. Provider participation is captured through assignments and events

Provider/staff eligibility still comes from the people/auth/access model.

But per-order operational participation is captured through:

- fulfillment assignment rows
- `request_events.actor_type`
- `request_events.actor_id`

### 8. ID strategy

For the target entity model in this document:

- use `UUIDv7` for new fulfillment entities and foreign keys
- keep current int-based request tables documented only as the current repo baseline

## Recommended v1 fulfillment flow

| Step | Primary actor | `status` | `sub_status` | Notes |
| --- | --- | --- | --- | --- |
| 1. Order submitted | Customer | `created` | `awaiting_prescription` or `awaiting_branch_review` | If Rx is required but missing, wait for prescription; otherwise branch can review immediately. |
| 2. Prescription added | Customer | `created` | `awaiting_branch_review` | Customer uploads required prescription. |
| 3. Branch review | Pharmacist / branch staff | `accepted`, `rejected`, or stays `created` | `preparing`, `rejected_unavailable`, `rejected_invalid_prescription`, or `awaiting_customer_confirmation` | Branch checks prescription, stock, and derived items. |
| 4. Manual customer confirmation if needed | Pharmacist/provider or admin/dispatcher | `created` or `rejected` | `awaiting_customer_confirmation` or `customer_rejected_changes` | Phone-call outcome is recorded by the acting provider/admin. |
| 5. Preparation | Branch staff | `accepted` | `preparing` | Order is packed and readied. |
| 6. Dispatch / handoff | Branch staff / delivery actor | `in_progress` | `out_for_delivery` | Delivery assignment begins. |
| 7. Delivery completed | Delivery actor / system | `completed` | `delivered` | Order is complete. |

## Exception handling

### General rule

For v1, handle exceptions by:

1. updating `service_requests.status`
2. setting an appropriate pharmacy `sub_status`
3. writing a `request_events` row
4. updating/closing the active assignment row

Do not create separate exception entities in v1.

### Recommended exception outcomes

| Scenario | `status` | `sub_status` | Notes |
| --- | --- | --- | --- |
| Customer cancels before acceptance | `cancelled` | `customer_cancelled` | Order stops before branch acceptance. |
| Selected branch cannot fulfill | `created` or `rejected` | `awaiting_branch_review` on reroute, or `rejected_unavailable` if no branch remains | Reroute if another provider is available; otherwise reject. |
| Prescription invalid or insufficient | `rejected` | `rejected_invalid_prescription` | Terminal in v1 unless a new prescription is submitted through a separate retry path. |
| Customer rejects pharmacist/admin changes | `rejected` | `customer_rejected_changes` | Terminal v1 path. |
| Accepted order later cannot be fulfilled | `failed` | `unable_to_fulfill` | Use when fulfillment fails after acceptance. |
| Delivery fails | `failed` | `delivery_failed` | Final delivery exception state in v1. |

## Rerouting model

V1 rerouting is allowed for provider-related fulfillment failure, with one important constraint:

- the order price snapshot remains authoritative

That means:

- `selected_pharmacy_id` may change during fulfillment
- `pharmacy_order_items.product_id` stays stable
- order item/header price snapshots remain unchanged
- reroute history is recorded in assignments and events

### Reroute flow

1. current branch assignment becomes `rejected` or `failed`
2. write a `request_events` record for the branch failure
3. update `pharmacy_order_details.selected_pharmacy_id`
4. create a new active branch assignment
5. if the new branch accepts, continue fulfillment
6. if no more branches accept, terminate the order

## Manual confirmation flow

When pharmacist/provider or admin/dispatcher review changes require customer approval:

1. put the order into `created` + `awaiting_customer_confirmation`
2. write `customer_confirmation_requested`
3. contact the customer by phone
4. record the result through `customer_confirmation_resolved`
5. if accepted, apply the proposed changes into canonical order tables
6. if rejected, set `rejected` + `customer_rejected_changes`

### Event metadata guidance

Recommended `customer_confirmation_resolved.metadata_json` shape:

```json
{
  "confirmationType": "derived_order_change",
  "decision": "accept",
  "channel": "phone_call",
  "recordedByRole": "pharmacist"
}
```

## Prescription-only and mixed-order handling

### Prescription-only orders

Prescription-only orders may start with:

- a `service_requests` row
- a `pharmacy_order_details` row with zero/nullable totals initially
- no `pharmacy_order_items` yet
- prescription `request_attachments`

Before branch acceptance:

- branch review must derive the actual order items and final totals
- accepted order items/totals are then written into canonical order tables

### Mixed orders

Mixed orders may start with:

- selected customer items already in `pharmacy_order_items`
- prescription `request_attachments`

If branch review proposes changes:

- proposed changes may live temporarily in `service_requests.payload_json`
- canonical order items/totals are updated only after manual customer acceptance
- customer rejection ends the order with `customer_rejected_changes`

## Recommended v1 fulfillment entity

### `pharmacy_order_assignments`

Tracks branch/delivery ownership and fulfillment attempts over time.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `request_id` | uuid FK -> `service_requests.id` | Owning order/request |
| `pharmacy_id` | uuid FK -> `pharmacies.id` nullable | Branch context when relevant |
| `assignment_kind` | varchar(64) | `branch_fulfillment`, `delivery` |
| `assigned_person_id` | uuid nullable | Specific pharmacist/staff/rider when known |
| `assigned_role_code` | varchar(64) nullable | e.g. `pharmacist`, `branch_staff`, `delivery_rider`, `dispatcher` |
| `status` | varchar(32) | `active`, `accepted`, `rejected`, `completed`, `cancelled`, `failed` |
| `attempt_no` | integer | Per-request sequence number |
| `reason_code` | varchar(64) nullable | Why this assignment ended or changed |
| `started_at` | timestamptz | Assignment start time |
| `ended_at` | timestamptz nullable | Assignment end time |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

Notes:

- one request may have many assignment rows over time
- rerouting creates a new branch assignment rather than overwriting the old one
- only one active `branch_fulfillment` assignment should exist at a time
- delivery can be modeled as a later assignment phase on the same request

## Request-event usage in fulfillment

Recommended event types used heavily by fulfillment:

- `request_status_changed`
- `customer_confirmation_requested`
- `customer_confirmation_resolved`
- `assignment_created`
- `assignment_closed`
- `fulfillment_started`
- `fulfillment_completed`

### Example event uses

- branch review begins -> `assignment_created`
- branch rejects due to no stock -> `assignment_closed` + `request_status_changed`
- branch rerouted -> new `assignment_created`
- order packed and handed to delivery -> `fulfillment_started`
- delivered -> `fulfillment_completed`

## Constraints and indexes

- index on `pharmacy_order_assignments(request_id, assignment_kind, status)`
- unique partial index for one active branch fulfillment assignment per request
- unique partial index for one active delivery assignment per request
- index on `pharmacy_order_assignments(pharmacy_id, status)`
- index on `pharmacy_order_assignments(assigned_person_id, status)`

## Non-goals for this document

- catalog design
- top-level order identity design
- quote/versioning workflows
- full substitution entity design
- inventory reservation strategy

## Open follow-ups

- whether v1 delivery should use the same assignment entity or a separate delivery-assignment table
- whether invalid-prescription cases should support resubmission on the same request or require a new request
- whether a dedicated confirmation entity is needed once manual phone confirmation becomes common across services
