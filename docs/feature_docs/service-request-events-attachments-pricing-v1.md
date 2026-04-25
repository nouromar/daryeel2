# Daryeel 2 API design: request events, request attachments, and pricing v1

## Goal

Define the near-term API design for three shared request-spine concerns:

- standardized `RequestEvent` records
- generic request-scoped attachments
- fixed pricing for v1 without a `Quote` entity

This document is intentionally scoped to shared request behavior. Pharmacy-specific catalog, product, and fulfillment entities are covered separately.

## Current repo baseline

Today `services/api` already has the following:

- `service_requests`
  - integer PK
  - `service_id`
  - `customer_user_id`
  - `status`
  - `notes`
  - `payload_json`
  - `delivery_location_json`
  - `payment_json`
  - `created_at`, `updated_at`
- `request_events`
  - integer PK
  - `request_id`
  - `type`
  - `from_status`
  - `to_status`
  - `actor_type`
  - `actor_id`
  - `metadata_json`
  - `created_at`
- `prescription_uploads`
  - pharmacy-only upload record
  - currently referenced from `service_requests.payload_json.prescription_upload_ids`
- pricing data for pharmacy orders is currently carried inside request payload blobs such as `summary_lines` and `summary_total`

The current model is sufficient for local demos, but it mixes important workflow state into service-specific payloads and metadata.

## Decisions

### 1. Standardize `RequestEvent`

`RequestEvent` remains the append-only historical log for request activity.

`service_requests.status` remains the current denormalized request state for cheap reads.

Rule:

- every request state transition updates `service_requests.status`
- the same transaction also writes a `RequestEvent`

This gives us fast list/detail reads while keeping a complete audit timeline.

### ID strategy for target design

For the target entity model in this document:

- use `UUIDv7` for core business entity primary keys
- keep current integer IDs described above only as the **current repo baseline**
- keep string service keys such as `pharmacy` on `service_id`

That means the long-term target is:

- `service_requests.id` -> `UUIDv7`
- `request_events.id` -> `UUIDv7`
- `attachments.id` -> `UUIDv7`
- `request_attachments.id` -> `UUIDv7`

### 2. Use generic request-scoped attachments

We will replace the pharmacy-only `prescription_uploads` concept with a generic attachment model for request workflows.

For this design, attachments are strictly request-scoped.

This document does **not** cover person-level identity verification documents. Those should be modeled separately from request attachments.

### 3. Skip `Quote` for v1

We will use fixed pricing for v1.

That means:

- no `quotes` table yet
- no quote versioning/approval workflow yet
- no quote-specific request events yet

Customer-visible pricing should be persisted directly on the request side as a final pricing snapshot.

## Recommended v1 entity set

### 1. `request_events`

Append-only shared request timeline.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `request_id` | uuid FK -> `service_requests.id` | Owning request |
| `type` | varchar(64) | Shared event type |
| `actor_type` | varchar(32) | `customer`, `provider`, `staff`, `system` |
| `actor_id` | uuid nullable | Acting user/person when known |
| `from_status` | varchar(64) nullable | Previous request status |
| `to_status` | varchar(64) nullable | New request status |
| `related_entity_type` | varchar(64) nullable | e.g. `attachment`, `confirmation`, `payment` |
| `related_entity_id` | varchar(128) nullable | Related record identifier |
| `metadata_json` | json/jsonb nullable | Extra event context only |
| `created_at` | timestamptz | Audit |

### Shared event type set

Use a small shared vocabulary across services:

- `request_created`
- `request_status_changed`
- `customer_confirmation_requested`
- `customer_confirmation_resolved`
- `assignment_created`
- `assignment_closed`
- `attachment_added`
- `attachment_removed`
- `payment_recorded`
- later: `provider_assigned`, `fulfillment_started`, `fulfillment_completed`

### Event rules

1. `metadata_json` may add context, but it must not be the only source of business meaning.
2. Status-changing events should populate both `from_status` and `to_status`.
3. Related records should be linked through `related_entity_type` and `related_entity_id` instead of hidden only in metadata.
4. Events are never updated in place; corrections create new events.

### Mapping from current ad hoc events

| Current event | Recommended event |
| --- | --- |
| `created` | `request_created` |
| `price_change_confirmed` / `price_change_rejected` | `customer_confirmation_resolved` |
| `substitution_confirmed` / `substitution_rejected` | `customer_confirmation_resolved` |
| `prescription_uploaded` | `attachment_added` |

For confirmation events, store details such as `confirmationType`, `decision`, and `channel` in `metadata_json`.

For assignment events, use `related_entity_type` / `related_entity_id` to point at the active assignment row.

### 2. `attachments`

Generic uploaded file/blob metadata.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `storage_key` | varchar(512) | Storage reference/path |
| `filename` | varchar(255) nullable | Safe display name |
| `content_type` | varchar(128) nullable | MIME type |
| `size_bytes` | integer nullable | File size |
| `checksum_sha256` | varchar(64) nullable | Optional integrity field |
| `created_at` | timestamptz | Upload time |

Notes:

- This is the shared file record.
- It is intentionally not tied directly to identity verification in this design.
- Storage can remain local-path backed initially, but the model should not assume local disk forever.

### 3. `request_attachments`

Links attachments to a request and gives them request-specific meaning.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `request_id` | uuid FK -> `service_requests.id` | Owning request |
| `attachment_id` | uuid FK -> `attachments.id` | File record |
| `attachment_type` | varchar(64) | `prescription`, `supporting_document`, `photo`, `signature`, `proof_of_delivery` |
| `purpose` | varchar(64) nullable | Optional finer-grained use |
| `status` | varchar(32) | `active`, `removed`, `replaced` |
| `uploaded_by_actor_type` | varchar(32) | `customer`, `provider`, `staff`, `system` |
| `uploaded_by_actor_id` | uuid nullable | Actor reference |
| `created_at` | timestamptz | Link creation time |
| `removed_at` | timestamptz nullable | Removal time |
| `metadata_json` | json/jsonb nullable | Optional service-specific context |

Notes:

- `attachments` stores file facts.
- `request_attachments` stores request workflow meaning.
- Request detail should load attachments via `request_attachments`, not from `payload_json`.

## Pricing decision for v1

Because pricing is fixed in v1:

- keep the final customer-visible pricing snapshot on the request side
- do not add a `quotes` table
- do not add quote approval or quote versioning logic

### Recommended request-side pricing snapshot

For v1, the request should persist final pricing in a structured way that is not dependent on UI-only payload fields.

Recommended fields or structured subdocument:

- `currency_code`
- `subtotal_amount`
- `discount_amount`
- `fee_amount`
- `tax_amount`
- `total_amount`
- optional line-item breakdown snapshot

The exact storage shape can be finalized with the pharmacy entity work, but the rule is:

- pricing is a persisted request/order snapshot
- pricing is not modeled as a separate quote workflow in v1

## Non-goals for this document

- person-level identity verification documents
- provider dispatch/assignment entities
- pharmacy catalog/product/pharmacy inventory entities
- quote/versioning workflows

## Implementation impact on current API

### Request events

- keep `request_events`
- migrate target schema IDs to `UUIDv7`
- add `related_entity_type` and `related_entity_id`
- migrate request/event writing code toward shared event names
- stop relying on custom event names as the only workflow signal

### Attachments

- replace `prescription_uploads` with `attachments`
- add `request_attachments`
- use `UUIDv7` IDs for new attachment entities
- stop reading request documents from `payload_json.prescription_upload_ids`
- emit standardized attachment events

### Pricing

- keep fixed pricing on the request side
- remove dependence on UI-specific `summary_lines` / `summary_total` as the only persisted pricing record
- defer `quotes` until a service actually needs revised, proposed, or approved pricing

## Recommended implementation order

1. Standardize `request_events` vocabulary and add related-entity references.
2. Introduce `attachments` and `request_attachments`.
3. Migrate pharmacy prescription uploads to request attachments.
4. Persist fixed pricing snapshots on the request side in a structured form.
5. Remove remaining payload-only workflow references where request-side entities now exist.

## Open follow-ups

- Decide whether `service_requests` should get dedicated pricing columns or a structured pricing JSON field in the short term.
- Define a standardized confirmation entity if customer approvals become more common across services.
- When dynamic pricing arrives, add a separate `Quote` design instead of overloading request payloads.
