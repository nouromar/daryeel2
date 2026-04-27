---
description: "Implementation plan for the v1 entity and workflow designs under docs/feature_docs/."
status: active
owner: backend
last_updated: 2026-04-27
---

# Implementation Plan: `docs/feature_docs/*`

This plan turns the feature docs into an implementation sequence that matches:

- the agreed design docs
- the current `services/api` codebase
- the app/backend contract decisions made during implementation

It replaces the earlier "straight cutover" draft and records the decisions that were made while shipping the first pharmacy/shared-request slices.

## Source docs

- `docs/feature_docs/people-auth-entities-design.md`
- `docs/feature_docs/service-request-events-attachments-pricing-v1.md`
- `docs/feature_docs/pharmacy-catalog-entities-design.md`
- `docs/feature_docs/pharmacy-order-entities-design.md`
- `docs/feature_docs/pharmacy-fulfillment-flow-and-entities-design.md`

## Current baseline

The first shared-request and pharmacy slices are now implemented in `services/api`:

- `service_requests.sub_status`
- standardized `request_events` with `UUIDv7` event IDs plus related-entity refs
- DB-backed `service_definitions`
- `people`
- `customer_profiles`
- `provider_profiles`
- `staff_profiles`
- transitional `users.person_id -> people.id` bridge for the current user-rooted auth flow
- `roles`
- `person_role_assignments`
- `auth_identities`
- `auth_factors`
- `auth_challenges`
- `auth_sessions`
- `auth_policies`
- `organization_memberships`
- generic `attachments` and `request_attachments`
- DB-backed pharmacy catalog tables
- normalized `pharmacy_order_details` and `pharmacy_order_items`
- normalized `pharmacy_order_assignments`
- backend-selected pharmacy assignment at order creation
- pharmacy request detail serialized under `serviceDetails.order`
- customer checkout using canonical `order.items` and `order.prescriptionAttachmentIds`

Still deferred:

- `service_requests.id` remains integer
- `request_events.request_id` remains on the current integer request root
- `request_events.actor_id` remains integer/user-rooted
- auth tokens and request ownership remain user-rooted
- geo-scoped role assignments are not implemented yet
- scopes, permission hardening, and people-root cutover are not yet implemented

## Planning principles

### 1. No hard reset

Do **not** assume a full schema reset, migration collapse, or wholesale replacement of all routes in one step.

Implementation should use:

- additive Alembic revisions
- small, mergeable slices
- explicit app/backend coordination when request or response contracts change

Local developers may still recreate local databases when useful, but that is not the plan's core migration strategy.

### 2. Ship pharmacy + shared request behavior first

The first implementation priority is:

1. shared request spine improvements
2. pharmacy catalog normalization
3. pharmacy order normalization
4. pharmacy fulfillment flows

People/auth should be implemented in parallel where it is low-risk, but the pharmacy backend should not be blocked on a full auth redesign.

### 3. Migrate `request_events.id` early; defer `service_requests.id`

The feature docs use `UUIDv7` for the target entity model.

However, the current backend still uses integer roots for:

- `users`
- `service_requests`
- `request_events.request_id`
- `request_events.actor_id`

Recommended implementation path:

- use `UUIDv7` immediately for **new tables**
- do **not** spend effort converting `users`, because it is being replaced by `people`
- migrate `request_events.id` to `UUIDv7` in an early shared-request slice
- keep `service_requests.id` on the current integer root in the first shipping slices
- add a dedicated later migration phase for the `service_requests` root ID cutover after people/auth is in place

This keeps the first implementation slices realistic while still moving `request_events` toward the target design early.

### 4. `service_definitions.id` stays a string key

`service_definitions.id` is the stable service key, for example:

- `pharmacy`
- `ambulance`
- `home_visit`

It is **not** part of the UUID migration target.

### 5. Keep `payload_json` as the shared cross-service extension field

Keep the name `payload_json` for now.

Reason:

- it is a shared cross-service field, not a pharmacy-only concept
- other services such as ambulance and home visit may still define different uses for it as their flows and entities are designed
- the pharmacy docs narrow its usage, but that narrowing should not be assumed yet for every service

Recommended rule for pharmacy usage of `payload_json`:

Allowed:

- temporary proposed changes awaiting customer confirmation
- unstable or not-yet-normalized service extras
- short-lived workflow context that does not deserve a first-class table yet

Not allowed as the source of truth:

- order items
- order totals
- selected pharmacy
- request attachments
- status / sub-status
- fulfillment assignment state

For pharmacy, adopt these semantics immediately even if the column name stays unchanged.

### 6. Keep `payment_json` for v1

Do **not** replace `payment_json` yet.

The agreed order design keeps `payment_json` as the v1 payment selection snapshot and leaves redesign as a follow-up.

### 7. Backend selects the pharmacy until routing exists

We explicitly decided that the customer app should **not** choose a pharmacy during checkout in v1.

Current v1 rule:

- the backend assigns `pharmacy_order_details.selected_pharmacy_id` when the order is created
- it resolves that branch from `API_DEFAULT_PHARMACY_ID` when configured
- otherwise it falls back to the first active pharmacy row

This is a temporary routing policy, not the long-term marketplace/routing design.

### 8. The normalized app contract is already in place

The earlier compatibility period is over for the pharmacy request-detail and checkout flows.

Current v1 contract:

- checkout sends canonical `order.items` and `order.prescriptionAttachmentIds`
- pharmacy request detail reads from normalized rows
- pharmacy request detail is returned under `serviceDetails.order`
- the old `serviceDetails.payload.*` compatibility fields are no longer part of the pharmacy contract

Future slices should preserve this normalized contract unless a paired app/backend change explicitly replaces it.

### 9. Contract changes must be paired with app changes

The old draft treated app changes as out of scope. That is not accurate.

This plan assumes paired changes when we alter:

- catalog item IDs
- checkout request fields
- request-detail payload shape
- auth response/token contracts

## Recommended workstreams

### Workstream A — Shared request spine + pharmacy

This is the first delivery path.

### Workstream B — People/auth/access

This can run partly in parallel, but it should not force a full rewrite of pharmacy flows before pharmacy ships.

### Workstream C — Shared-root UUID cutover

This is the final target-alignment phase after Workstreams A and B have stabilized.

---

## Workstream A — Shared request spine + pharmacy

## Phase A1 — Shared request spine stabilization

Source docs:

- `service-request-events-attachments-pricing-v1.md`
- `pharmacy-order-entities-design.md`

### PR A1.1 — Standardize request events and add missing shared fields

**Migration**

- add `service_requests.sub_status`
- migrate `request_events.id` from integer PK to `UUIDv7`
- add `request_events.related_entity_type`
- add `request_events.related_entity_id`

**Code**

- introduce shared request-event constants/helpers
- start using the agreed shared vocabulary:
  - `request_created`
  - `request_status_changed`
  - `customer_confirmation_requested`
  - `customer_confirmation_resolved`
  - `assignment_created`
  - `assignment_closed`
  - `attachment_added`
  - `attachment_removed`
  - `payment_recorded`
- stop adding new workflow meaning only through ad hoc event names

**Notes**

- keep current integer `service_requests.id` for now
- do not defer `request_events.id`; migrate it in this slice
- `request_events.request_id` can continue pointing at the current integer request root until the later `service_requests` cutover

### PR A1.2 — Narrow `payload_json` semantics

**Migration**

**Code**

- keep `service_requests.payload_json` as the shared cross-service field
- document and enforce that canonical pharmacy data will move out of this column
- keep `payload_json` available for temporary, non-authoritative pharmacy extras only

### PR A1.3 — Generic attachments + request attachments

**Migration**

- add `attachments`
- add `request_attachments`

Use UUIDv7 for these new tables immediately.

**Code**

- switch pharmacy upload persistence from `prescription_uploads` storage semantics to shared `attachments`
- keep the existing upload endpoint path for now:
  - `POST /v1/pharmacy/prescriptions/upload`
- keep returning an `id` for the uploaded file
- treat that returned `id` as the attachment identifier

This gives us a low-disruption bridge:

- upload first
- link to a request later via `request_attachments`

### PR A1.4 — Request detail reads prescriptions from normalized attachment links

**Code**

- update `requests.py` detail serialization to load prescription documents from:
  - `request_attachments`
  - `attachments`
- stop treating `payload_json.prescription_upload_ids` as the source of truth

**Compatibility**

- continue serializing the current pharmacy detail payload shape expected by the app
- the backend should derive that response shape from normalized rows

---

## Phase A2 — Shared service and organization foundations for pharmacy

Source docs:

- `people-auth-entities-design.md`
- `pharmacy-catalog-entities-design.md`

### PR A2.1 — DB-backed `service_definitions`

**Migration**

- add `service_definitions`
- seed current service keys:
  - `pharmacy`
  - `ambulance`
  - `home_visit`

**Code**

- replace in-memory `_SERVICE_DEFINITIONS`
- keep `/v1/service-definitions` contract stable

### PR A2.2 — Shared `organizations`

**Migration**

- add `organizations`

This table is shared across pharmacy and the later people/auth workstream.

### PR A2.3 — Add `pharmacies`

**Migration**

- add `pharmacies`

Use the structured location fields agreed in the catalog doc.

### PR A2.4 — Seed a minimal dev catalog ownership model

**Migration / seed**

- seed at least one organization
- seed at least one pharmacy branch for local/dev flows

This is only to replace the current fixture-backed behavior and unblock later catalog/order work.

---

## Phase A3 — Pharmacy catalog normalization

Source doc:

- `pharmacy-catalog-entities-design.md`

### PR A3.1 — Add product and category tables

**Migration**

- add `products`
- add `product_images`
- add `product_categories`
- add `product_category_assignments`

Use UUIDv7 for these new tables.

### PR A3.2 — Add branch offer table

**Migration**

- add `pharmacy_products`

Keep the agreed composite PK:

- `(pharmacy_id, product_id)`

Do **not** add a surrogate `id`.

### PR A3.3 — Seed catalog data from current fixtures

**Seed**

- convert existing catalog fixtures into normalized rows

Important:

- do **not** describe seeded IDs as "deterministic UUIDv7"
- if deterministic seeded identity is needed for repeatable local seeds, use stable mapping logic, but the IDs themselves are still ordinary generated UUIDs

### PR A3.4 — Replace catalog endpoint with DB-backed queries

**Code**

- replace `_PHARMACY_CATALOG` with DB queries over:
  - `products`
  - `pharmacy_products`
  - `pharmacies`

**Contract decision**

Before or during this PR, explicitly decide one of these paths:

1. expose `products.id` UUIDs directly and update the apps in the same slice
2. add a dedicated external/public product code and let the apps keep using that

Do **not** silently switch API IDs without the paired app changes.

### PR A3.5 — Support checkout source context

Current implemented decision:

- the customer app does **not** send a pharmacy/branch identifier during checkout
- the backend resolves a default branch internally and writes `selected_pharmacy_id`

Follow-up:

- replace the default resolver with a routing engine later without changing the v1 customer-facing checkout contract

---

## Phase A4 — Pharmacy order normalization

Source doc:

- `pharmacy-order-entities-design.md`

### PR A4.1 — Structured order entities

**Migration**

- keep `delivery_location_json`
- keep `payment_json`
- add `pharmacy_order_details`
- add `pharmacy_order_items`

### PR A4.2 — Rewrite pharmacy order creation

**Code**

Update `POST /v1/pharmacy/orders` so that:

1. the request row remains rooted in `service_requests`
2. `selected_pharmacy_id` is set at order creation by backend routing/default-pharmacy selection
3. order items are written into `pharmacy_order_items`
4. pricing is computed from `pharmacy_products`
5. authoritative totals are stored in `pharmacy_order_details`
6. prescriptions are linked through `request_attachments`
7. the request and event rows use the shared event vocabulary
8. the customer app does not send a pharmacy identifier in this slice

### PR A4.3 — Support both prescription-only and mixed orders

**Code**

- allow prescription-only orders with no initial canonical order items
- allow mixed orders with order items plus prescription attachments
- keep `payload_json` available for temporary review state only:
  - `submittedOrder` for the original customer-selected order lines
  - `pendingConfirmation` for temporary proposed changes awaiting confirmation

### PR A4.4 — Request detail serialization from normalized order tables

**Code**

- load pharmacy request detail from:
  - `pharmacy_order_details`
  - `pharmacy_order_items`
  - `request_attachments`
- serialize the normalized app contract under `serviceDetails.order`
- stop depending on JSON blobs as the authoritative source for these values

### PR A4.5 — Remove pharmacy-only legacy storage paths

After the normalized order path is stable:

- stop writing canonical order data into `payload_json`
- remove the old pharmacy compatibility payload fields and old checkout summary payload submission path
- delete `prescription_uploads` once uploads are fully retired everywhere

---

## Phase A5 — Pharmacy fulfillment and operations

Source doc:

- `pharmacy-fulfillment-flow-and-entities-design.md`

### PR A5.1 — Add `pharmacy_order_assignments`

**Migration**

- add `pharmacy_order_assignments`

Use the agreed fields, including:

- `assignment_kind`
- `attempt_no`
- `reason_code`
- `status`
- `started_at`
- `ended_at`

### PR A5.2 — Add pharmacy status/sub-status transition helper

**Code**

- centralize allowed pharmacy transition logic
- use:
  - shared `status`
  - pharmacy `sub_status`
  - standardized `request_events`

### PR A5.3 — Branch assignment, acceptance, rejection, reroute

**Code**

Introduce provider/admin operations routes for:

- assignment creation
- assignment acceptance
- assignment rejection
- reroute to another branch

**Rule**

- reroute must preserve the customer-facing order snapshot price

### PR A5.4 — Manual customer confirmation flow

**Code**

Add operations for:

- branch review of prescription-only and mixed orders
- requesting confirmation
- resolving confirmation

**Rule**

- additive prescription-derived changes may auto-apply without customer confirmation
- changing customer-selected lines requires confirmation
- store the original customer-selected lines in `payload_json.submittedOrder`
- store temporary proposals in `payload_json.pendingConfirmation`
- canonical order tables change only after confirmation acceptance
- rejection ends the request with `rejected` + `customer_rejected_changes`
- `phone_call` confirmations are recorded by staff; only `in_app` confirmations should surface a customer action

### PR A5.5 — Delivery assignment and terminal delivery outcomes

**Code**

- open delivery assignments
- mark out-for-delivery
- mark delivered
- mark delivery failed

This should continue using `pharmacy_order_assignments` in v1 unless a later explicit redesign says otherwise.

---

## Workstream B — People/auth/access

Source doc:

- `people-auth-entities-design.md`

This workstream should follow the people/auth doc's own internal ordering, while reusing any shared tables already introduced in Workstream A.

## Phase B1 — People and roles foundation

### PR B1.1 — `people` and profile tables

**Migration**

- add `people`
- add `customer_profiles`
- add `provider_profiles`
- add `staff_profiles`

**Current status**

- implemented
- the current backend also carries a transitional `users.person_id` bridge so existing user-rooted OTP auth can link customers to `people` without changing token or request ownership contracts yet

### PR B1.2 — Roles and role assignments

**Migration**

- add `roles`
- add `person_role_assignments`

**Current status**

- implemented
- `person_role_assignments` currently supports person, role, organization, service, and assigning-person references
- `geo_scope_id` is intentionally deferred to PR B1.3 so the roles slice does not reference `geo_scopes` before that table exists

### PR B1.3 — Service and geography scopes

If `service_definitions` already landed in Workstream A, reuse it here.

**Migration**

- add `person_service_scopes`
- add `geo_scopes`
- add `person_geo_scopes`

**Current status**

- deferred by product decision for now
- this slice is not required for current shipped pharmacy or dev auth behavior
- `geo_scope_id` remains deferred on `person_role_assignments` until this slice is resumed
- the next implementation slice moves to `PR B3.1 — Auth tables`

## Phase B2 — Organizations and memberships

If `organizations` already landed in Workstream A, do **not** recreate it.

**Migration**

- add `organization_memberships`

**Current status**

- implemented
- `organization_memberships` now links `people` to existing `organizations` with membership type, status, title, and effective dates

## Phase B3 — Auth foundation

### PR B3.1 — Auth tables

**Migration**

- add `auth_identities`
- add `auth_factors`
- add `auth_challenges`
- add `auth_sessions`
- add `auth_policies`

**Current status**

- implemented
- this slice adds the auth foundation schema used by the current dev OTP/session flow

### PR B3.2 — Replace dev OTP flow with real auth tables

**Code**

- move OTP challenge state into auth tables
- create/link people records on first verified customer sign-in
- return session-backed auth instead of the current minimal dev-only behavior

**Current status**

- implemented
- `/dev/auth/otp/start` now creates pending `auth_challenges`
- `/dev/auth/otp/verify` now completes challenges, verifies phone identities/factors, and creates `auth_sessions`
- dev auth remains user-rooted at the token contract level until the later `users` -> `people` cutover

## Phase B4 — Permission hardening

**Migration**

- add `permissions`
- add `role_permissions`

**Code**

- add permission helpers/dependencies
- gate provider/admin pharmacy ops routes with the new permission model

**Current status**

- implemented
- added `permissions` and `role_permissions`
- added a reusable permission dependency over active `person_role_assignments`
- gated pharmacy fulfillment routes with `pharmacy.manage_orders` and `pharmacy.complete_delivery`
- seeded baseline pharmacy role/permission mappings for `admin`, `dispatcher`, `specialist`, `pharmacist`, `branch_staff`, `delivery_rider`, and `driver`

---

## Workstream C — Bridge from current users/int roots to target people/UUID roots

This is the final alignment workstream and should happen only after Workstreams A and B are stable.

## Phase C1 — Move shared business references from `users` to `people`

**Migration**

- add `customer_person_id` to `service_requests`
- add person-based actor references where needed

**Code**

- move request ownership and auth resolution from `users` to `people`
- backfill relationships from the current user/auth records

## Phase C2 — Retire `users`

Only after request ownership and auth flow are fully person-based:

- stop reading from `users`
- remove remaining direct dependencies on `users`

## Phase C3 — Shared-root UUID cutover

This is where we align the old shared root tables with the target UUID design.

Candidates:

- `people`
- `service_requests`

Recommended approach:

1. introduce UUID columns
2. backfill values
3. move foreign keys and route handling
4. update apps and backend contracts together
5. remove legacy integer keys

Do **not** try to combine this with the earlier pharmacy normalization slices.

---

## Resolved contract decisions

These decisions were made during implementation and should now be treated as part of the v1 plan.

### 1. Pharmacy product identifier contract

Decision:

- the app/API uses canonical `products.id` UUIDs directly in v1
- no separate public product code was added in this slice

### 2. Selected pharmacy at checkout

Decision:

- checkout does not include a pharmacy identifier
- the backend assigns the branch internally using the default-pharmacy resolver
- a future routing engine can replace that resolver later

### 3. Upload identifier contract

Decision:

- prescription upload returns an attachment `id`
- checkout sends those IDs through `order.prescriptionAttachmentIds`
- request detail exposes them as `serviceDetails.order.prescriptionAttachments`

### 4. `payload_json` semantics by service

Decision:

- pharmacy should treat `payload_json` as non-authoritative once normalized entities land
- other services may continue using `payload_json` until their own entity and flow designs are defined
- no service should silently use `payload_json` as a permanent substitute for canonical entities once those entities exist
- pharmacy v1 currently uses:
  - `submittedOrder` for the original customer-selected lines
  - `pendingConfirmation` for temporary confirmation-required proposals

### 5. Pharmacy request-detail contract

Decision:

- pharmacy request detail uses `serviceDetails.order`
- the older pharmacy `serviceDetails.payload.*` compatibility fields were removed together with the app update

---

## Validation expectations by slice

Each slice should include:

- Alembic revision(s)
- focused SQLAlchemy/model tests
- route tests for changed endpoints
- updated request-detail tests when response synthesis changes

Also add at least one Postgres-backed migration/integration path for features SQLite cannot validate well, especially:

- partial unique indexes
- complex FK sequencing
- migration backfills

---

## Acceptance criteria

### Shared request spine

- shared request event vocabulary is in use
- `request_events.id` uses `UUIDv7`
- `request_events` supports related-entity references
- request documents are linked through `request_attachments`

### Pharmacy

- catalog is DB-backed
- canonical pharmacy order state lives in normalized order tables
- request detail is rendered from normalized rows under `serviceDetails.order`
- rerouting preserves order price snapshots
- manual customer confirmation is supported through status/sub-status/events/assignments

### People/auth

- people, roles, scopes, auth, and permissions are first-class tables
- service definitions are DB-backed
- pharmacy ops routes can rely on person/role/permission data

### Final target alignment

- for pharmacy, `payload_json` is non-authoritative once normalized entities exist
- `service_definitions.id` remains a stable string key
- `service_requests` still has a dedicated migration path to the UUID target instead of being ignored or hand-waved

---

## Open follow-ups carried from the feature docs

- whether `payment_json` should later move to a dedicated payment selection model
- whether `fee_amount` stays combined or gets split into fee-specific fields
- whether invalid-prescription flows allow resubmission on the same request
- whether delivery should always stay inside `pharmacy_order_assignments`
- whether manual customer confirmation later needs a dedicated entity
- when to replace the backend default-pharmacy resolver with a real routing engine
