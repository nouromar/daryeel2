---
description: "RFC: common request detail screen, request workflow state model, customer actions, and notifications"
status: draft
owner: customer-experience
last_updated: 2026-04-11
---

# RFC: Request Detail, Workflow, and Notifications

## Summary

This RFC defines the next layer above the current Activities list:

1. a common request detail API and screen shell
2. a request workflow model that separates operational status from customer-required actions
3. a notification model for progress updates and customer attention states

The core recommendation is:

- use one common request detail screen shell for all services
- keep service-specific payload rendering inside service-specific detail sections/fragments
- model customer-required work explicitly as `pendingActions`, not as overloaded top-level statuses
- use `RequestEvent` as the canonical timeline spine and the notification source

This design is intended to work with the current repo shape:

- `ServiceRequest` and `RequestEvent` already exist in `services/api`
- the customer app can render a schema-only screen backed by a single detail endpoint
- important service-specific rendering can stay in app schemas under `apps/customer-app`

## Goals

- Provide a user-friendly request detail view for all services.
- Avoid building fully separate detail screens unless a service truly needs it.
- Support explicit customer actions such as confirming changes, uploading documents, or providing missing information.
- Support progress notifications and customer-attention notifications from the same backend model.
- Keep the first implementation app-first and service-oriented without requiring framework changes.

## Non-goals

- Real-time streaming is not required in the first slice.
- This RFC does not require a new generalized workflow engine.
- This RFC does not require package-level runtime changes for the first implementation.
- This RFC does not attempt to design every service workflow in full detail on day one.

## Current Repo State

Current backend spine:

- `ServiceRequest`
  - `service_id`
  - `status`
  - `notes`
  - `payload_json`
  - `delivery_location_json`
  - `payment_json`
- `RequestEvent`
  - `type`
  - `from_status`
  - `to_status`
  - `actor_type`
  - `actor_id`
  - `metadata_json`

Current customer experience:

- Activities list exists via `GET /v1/requests`
- request detail endpoint does not exist yet
- customer action workflow is not yet modeled explicitly
- push/in-app attention states are not yet derived from request events

## Decision 1: Common Detail Screen Shell

Use one common request detail screen shell for all services.

### Why

All request detail screens share the same structural sections:

- header and request identity
- current status
- progress/timeline
- delivery/payment/notes
- pending customer actions
- service-specific details

The part that varies is the service-specific payload.

### Structure

Use this pattern:

- common screen id: `customer_request_detail`
- common detail response from backend
- common schema shell renders shared sections
- service-specific detail fragment chosen by `serviceId`

This avoids duplicating the full screen while still allowing pharmacy, ambulance, and home visit to render different payload details.

### Rendering Rule

The detail screen should render, in this order:

1. request summary header
2. current status panel
3. pending customer actions section
4. service-specific detail section
5. timeline section
6. support/help footer actions

### Service-specific detail sections

Examples:

- pharmacy:
  - ordered items
  - prescription status
  - substitution proposal summary
  - estimated/final price changes
- ambulance:
  - pickup location
  - urgency / dispatch detail
  - unit assigned / ETA
- home visit:
  - requested service type
  - visit window
  - clinician assignment / preparation info

## Decision 2: Separate Operational Status From Customer Attention

Do not encode every customer-facing situation into top-level `status`.

### Problem

A single `status` field becomes ambiguous quickly. For example:

- a request can be operationally accepted, but also waiting on customer confirmation
- a request can be assigned, but also waiting for the customer to upload a prescription
- a request can be in progress, but also have an unread update

If all of these become statuses, the model becomes unstable and hard to reason about.

### Recommended model

Use three separate concepts:

1. `status`
   - the operational lifecycle state
2. `pendingActions`
   - explicit customer-required actions
3. `attentionState`
   - whether the request currently needs customer attention in the list/detail UI

### Core operational statuses

Recommended top-level `status` values:

- `created`
- `accepted`
- `assigned`
- `in_progress`
- `completed`
- `cancelled`
- `failed`
- `rejected`

Optional service-compatible additions if needed later:

- `scheduled`
- `on_hold`

### Customer attention state

Recommended `attentionState` values:

- `none`
- `update_available`
- `action_required`
- `urgent_action_required`

This field is for UX sorting and badges. It should not replace `status`.

### Pending actions

Use explicit action objects instead of hidden service-specific payload rules.

Recommended action types:

- `confirm_change`
- `provide_information`
- `upload_document`
- `choose_option`
- `confirm_schedule`
- `confirm_price`
- `confirm_substitution`
- `contact_support`

Each action should be a first-class backend object in the response, not inferred by the client from raw request payload.

## Decision 3: Use RequestEvent As The Timeline and Notification Spine

`RequestEvent` should be the canonical timeline source and the basis for notification generation.

### Why

This gives one audit-friendly event stream that can power:

- request detail timeline
- Activities sorting/badges
- unread update counters
- push notifications
- support/debugging

### Recommended event types

Core events:

- `created`
- `status_changed`
- `assigned`
- `started`
- `completed`
- `cancelled`
- `failed`

Customer-attention events:

- `customer_action_requested`
- `customer_action_completed`
- `customer_action_expired`

Pharmacy examples:

- `price_change_proposed`
- `price_change_confirmed`
- `price_change_rejected`
- `substitution_proposed`
- `substitution_confirmed`
- `substitution_rejected`
- `prescription_requested`
- `prescription_uploaded`

General update examples:

- `eta_updated`
- `note_added`
- `provider_arriving`
- `provider_delayed`

### Event metadata rule

Event-specific detail should live in `metadata_json`, but only as structured, typed payload.

Examples:

- price delta
- old/new total
- proposed substitutions
- uploaded document requirement
- reason for change

Avoid storing freeform UI text as the primary source of truth.

## Recommended Detail API Shape

Add a detail endpoint:

- `GET /v1/requests/{requestId}`

Recommended response:

```json
{
  "request": {
    "id": "123",
    "serviceId": "pharmacy",
    "status": "assigned",
    "statusLabel": "Assigned",
    "attentionState": "action_required",
    "title": "Pharmacy order",
    "subtitle": "Requested Apr 11",
    "createdAt": "2026-04-11T15:00:00Z",
    "updatedAt": "2026-04-11T15:10:00Z",
    "notes": "Leave at door",
    "deliveryLocation": {
      "text": "Hodan"
    },
    "payment": {
      "method": "cash",
      "timing": "after_delivery"
    }
  },
  "pendingActions": [
    {
      "id": "act_confirm_substitution_1",
      "type": "confirm_substitution",
      "title": "Approve substitution",
      "description": "The pharmacy suggested a different medicine.",
      "priority": "high",
      "deadlineAt": "2026-04-11T18:00:00Z",
      "payload": {
        "fromItem": "Item A",
        "toItem": "Item B",
        "priceDeltaText": "+$1.00"
      },
      "actions": [
        {"id": "approve", "label": "Approve"},
        {"id": "reject", "label": "Reject"}
      ]
    }
  ],
  "serviceDetails": {
    "serviceId": "pharmacy",
    "summary": {
      "items": [
        {"title": "Paracetamol", "quantity": 2}
      ],
      "totals": {
        "estimatedTotalText": "$5.00"
      },
      "prescriptionRequired": false,
      "prescriptionUploaded": false
    }
  },
  "timeline": [
    {
      "id": "evt_1",
      "type": "created",
      "title": "Order placed",
      "description": "Your order was created.",
      "createdAt": "2026-04-11T15:00:00Z"
    },
    {
      "id": "evt_2",
      "type": "customer_action_requested",
      "title": "Substitution approval needed",
      "description": "Please review the proposed substitution.",
      "createdAt": "2026-04-11T15:10:00Z"
    }
  ],
  "notificationState": {
    "hasUnreadUpdates": true,
    "lastNotifiedEventId": "evt_1"
  }
}
```

## Recommended Customer Action API Shape

The detail endpoint should not only describe pending actions. The backend also needs a write path.

Recommended action endpoint:

- `POST /v1/requests/{requestId}/actions/{actionId}`

Recommended request body:

```json
{
  "decision": "approve",
  "payload": {
    "note": "Accepted"
  }
}
```

Recommended response:

- updated `pendingActions`
- updated `status` / `attentionState`
- newly appended timeline event(s)

## Common Detail Screen Schema Structure

Use one schema screen:

- `customer_request_detail.screen.json`

The screen should be fully schema-driven.

### High-level structure

```json
ScreenTemplate
  body:
    RemoteQuery(/v1/requests/${params.requestId})
      loading
      error
      child:
        Column
          Request header section
          Pending actions section
          Service detail section
          Timeline section
```

### Suggested schema sections

1. Header section
- request title
- current status label
- created date
- optional attention badge

2. Pending actions section
- visible only when `pendingActions` is not empty
- each action rendered as an `ActionCard` or structured card
- approve/reject / provide-info routes or action handlers

3. Shared request info section
- delivery location
- payment method/timing
- notes

4. Service-specific section
- chosen by `serviceDetails.serviceId`
- render through service-specific fragments or `If` blocks

5. Timeline section
- `ForEach` over `timeline`
- render title, description, timestamp

### Service-specific rendering recommendation

Prefer fragments, not separate full screens.

Examples:

- `fragment:request_detail_pharmacy_v1`
- `fragment:request_detail_ambulance_v1`
- `fragment:request_detail_home_visit_v1`

The common detail screen decides which one to render using `If` on `serviceDetails.serviceId`.

## Notifications Model

Notifications should be generated from request events and pending actions, not from ad hoc business logic scattered across services.

### Two notification surfaces

1. Push notifications
- request accepted
- provider assigned
- provider arriving
- action required
- delay/update requiring attention

2. In-app notification state
- unread updates on a request
- request requires customer action
- badge/count in Activities or Inbox

### Recommended backend fields for list/detail

Add these summary fields to list/detail responses:

- `attentionState`
- `hasUnreadUpdates`
- `lastCustomerVisibleEventAt`
- `pendingActionCount`

This allows Activities to sort and badge requests without complex client-side derivation.

## Detailed Implementation Slices

## Slice 1: Request Detail Read API + Common Screen Shell

Goal:

- make request detail readable for all services
- no customer actions yet
- no push changes yet

Backend changes:

- add `GET /v1/requests/{requestId}`
- return:
  - `request`
  - `serviceDetails`
  - `timeline`
  - `pendingActions` as an empty list for now

Suggested files:

- `services/api/app/routers/requests.py`
- `services/api/tests/test_requests.py`

App changes:

- add `customer_request_detail.screen.json`
- add detail fragments for pharmacy first
- add navigation from Activities item tap into detail screen

Suggested files:

- `apps/customer-app/schemas/screens/customer_request_detail.screen.json`
- `apps/customer-app/schemas/fragments/request_detail_pharmacy.fragment.json`
- `apps/customer-app/lib/src/schema/fallback_schema_bundle.dart`
- `apps/customer-app/lib/src/schema/fallback_fragment_documents.dart`

Validation:

- request detail opens from Activities
- pharmacy request renders common shell + pharmacy detail section
- timeline renders from `RequestEvent`

## Slice 2: Customer Attention Model in List + Detail

Goal:

- surface whether a request needs the customer’s attention

Backend changes:

- add derived list/detail fields:
  - `attentionState`
  - `pendingActionCount`
  - `hasUnreadUpdates`

List changes:

- sort action-required requests ahead of normal active requests
- optionally show a badge or stronger subtitle treatment

Suggested files:

- `services/api/app/routers/requests.py`
- `apps/customer-app/schemas/fragments/customer_requests.fragment.json`
- `apps/customer-app/lib/src/schema/fallback_fragment_documents.dart`

Validation:

- Activities clearly distinguishes active vs action-required requests
- detail header shows attention state consistently

## Slice 3: Pending Actions API + Schema Rendering

Goal:

- allow explicit customer-required work to be shown in the detail screen

Backend changes:

- represent pending actions in the detail response
- for pharmacy, first support:
  - `confirm_price`
  - `confirm_substitution`
  - `upload_document`

App changes:

- render pending actions section in common detail screen
- use app-owned action routes or schema action endpoints for customer decisions

Suggested files:

- `services/api/app/routers/requests.py`
- `apps/customer-app/schemas/screens/customer_request_detail.screen.json`
- service-specific fragments under `apps/customer-app/schemas/fragments/`

Validation:

- pending action section appears only when needed
- action cards are explicit and understandable

## Slice 4: Customer Action Write Endpoint

Goal:

- let the customer complete a pending action from the app

Backend changes:

- add `POST /v1/requests/{requestId}/actions/{actionId}`
- record a `RequestEvent`
- update request-derived attention state
- clear or replace the completed pending action

First pharmacy actions:

- approve/reject price change
- approve/reject substitution
- upload required prescription

Suggested files:

- `services/api/app/routers/requests.py`
- `services/api/tests/test_requests.py`

App changes:

- navigate to upload screen when action type is `upload_document`
- use schema-driven buttons/cards for approve/reject actions where possible

Validation:

- completing an action updates the detail screen state
- Activities reflects changed attention state

## Slice 5: In-app Notification State

Goal:

- show the customer when there are unseen updates

Backend changes:

- add `hasUnreadUpdates`
- define unread semantics, for example:
  - compare latest customer-visible event timestamp against last acknowledged timestamp

Client changes:

- badge Activities tab or request rows
- clear unread marker when detail is opened or acknowledged

Suggested files:

- `services/api/app/routers/requests.py`
- customer Activities schema/fragment
- detail screen schema

Validation:

- unread indicators are stable across app restart
- opening detail clears or acknowledges updates according to policy

## Slice 6: Push Notifications

Goal:

- notify the user outside the app when progress is made or action is required

Backend changes:

- emit push jobs from new customer-visible `RequestEvent`s
- only notify on meaningful events:
  - assigned
  - arriving
  - action required
  - completed

Constraints:

- push delivery must be best-effort
- request detail endpoint remains the source of truth

Validation:

- push payload deep-links to request detail screen
- opening the detail screen reflects the latest backend truth even if push arrived late

## Recommended Order of Delivery

Recommended implementation order:

1. Slice 1
2. Slice 2
3. Slice 3
4. Slice 4
5. Slice 5
6. Slice 6

This gives value early without forcing workflow or push complexity before the read model exists.

## Explicit Recommendation

For the current repo, the recommended near-term path is:

- build one common request detail screen
- implement pharmacy as the first service-specific detail section
- model customer-required work through `pendingActions`
- use `RequestEvent` as the timeline and notifications spine
- add notifications only after the detail read/write model is stable

This keeps the first version coherent and avoids painting the product into a service-specific corner.