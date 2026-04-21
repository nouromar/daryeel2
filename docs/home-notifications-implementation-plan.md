---
description: "Implementation plan: Home status + multi-service notifications (primary + chips)"
status: draft
owner: customer-experience
last_updated: 2026-04-21
---

# Implementation Plan: Home Status + Multi-service Notifications (Primary + Chips)

## Summary
We will replace the current Home header placeholder (`section:customer_welcome_v1`) with a compact, always-relevant module that:

1) **always shows the most important in-progress item** (progress or action-needed), and
2) **if more exist, shows a friendly indicator UI** (outlined chips/badge) that navigates the user to Activities / full list.

This plan is intentionally compatible with later **push notifications in production**.
Push becomes a delivery channel; the UI is powered by a canonical backend “notification feed + active summary”.

This plan is **app-first** and avoids changes under `packages/*`.

## Goals
- Always surface the most important current progress on Home (Uber-style).
- Support **multiple active requests** across services without overwhelming the Home screen.
- Support two categories:
  - **FYI updates** (status/progress)
  - **Action required** (upload prescription, accept substitution, etc.)
- Provide a clear path to **push in prod** later.
- Keep bundled/offline fallback schemas in sync.

## Non-goals (v1)
- Real-time streaming (WebSocket/SSE) is not required for v1.
- Inline “Approve/Decline” actions inside the notification card are out of scope for v1.
  (We will deep-link to the correct screen to complete the action.)
- Building a full “Notifications screen” is optional and can be deferred.

## UX Spec (v1)
### Home header module behavior
**When there is at least one active/important item**:
- Show **one primary card** (tap → deep link).
- If there are more relevant items, show an **ActiveSummary** indicator directly under it:
  - Outlined pill(s) with counts.
  - Tap anywhere on the summary → navigates to Activities (or a future “Active” list).

**When there are no items**:
- Render nothing (prefer) OR render a subtle “You’re all caught up” card.

### Priority rule
Primary item selection should follow:
1) `kind=action_required` wins over FYI.
2) Within same `kind`, most recently updated/created wins.

### Multi-service summary indicator
We will show either:
- `+N other active requests` (simple), and optionally
- small service chips: `Pharmacy 2`, `Home visit 1` (only for the top few non-zero services).

## Data Model
We will use one unified notification model across services.

### Notification fields (backend → app)
Required:
- `id: string`
- `kind: "fyi" | "action_required"`
- `type: string` (stable machine identifier)
- `service: string | null` (e.g. `"pharmacy"`, `"home_visit"`, `"ambulance"`)
- `title: string`
- `subtitle: string`
- `createdAt: string` (ISO)

Optional (recommended):
- `priority: "low" | "normal" | "high"`
- `readAt: string | null`
- `resolvedAt: string | null`
- `entity: { kind: "request" | "order" | string, id: string } | null`
- `route: string | { route: string, value?: any } | null`
- `payload: object | null` (for future-proofing; not required for v1 rendering)

### Notes
- `service` is important for grouping and analytics, but UI default is “all”.
- `type` allows forward-compatible handling:
  - unknown `type` still renders as a generic card
  - known `type` can be enriched later (icon, templates, etc.)

## Backend API Design (v1)
We want two endpoints:

### A) Notification feed
`GET /v1/notifications`

Response:
```json
{
  "items": [
    {
      "id": "...",
      "kind": "fyi",
      "type": "request.status_changed",
      "service": "pharmacy",
      "title": "Out for delivery",
      "subtitle": "Pharmacy • Order #1234",
      "createdAt": "2026-04-21T10:00:00Z",
      "route": { "route": "customer_request_detail", "value": { "requestId": "req_123" } }
    }
  ]
}
```

### B) Home summary (optimized for Home)
`GET /v1/notifications/home-summary`

Response:
```json
{
  "primary": { "...notification item..." },
  "moreCount": 2,
  "moreByService": { "pharmacy": 1, "home_visit": 1 },
  "activeCount": 3
}
```

#### Why a dedicated home summary endpoint?
- Keeps schema logic simple (no “pick primary” in JSON schema).
- Lets backend collapse/dedupe noisy events (e.g. delivery progress).
- Improves performance and reduces payload size for the Home header.

### v1 data source strategy (incremental)
We can implement v1 without a full notifications persistence model by deriving items from existing request data.
Suggested v1 derivation:
- From `/v1/requests` active list:
  - If request has pending action signals → emit `kind=action_required`.
  - Else emit `kind=fyi` with current status.
- Collapse to at most one item per request.

Later, we can move to a persisted notifications inbox model without changing the UI contract.

## Backend Implementation Steps
1) Add a new router/module: `services/api/app/routers/notifications.py` under `/v1/notifications...`.
2) Implement:
   - `GET /v1/notifications` (feed)
   - `GET /v1/notifications/home-summary` (primary + counts)
3) Decide the v1 derivation rules from requests:
   - Map request status → title/subtitle/icon/service.
   - Map “pending actions” (or existing payload heuristics) → action_required types.
4) Ensure the response includes `route` compatible with existing client navigation patterns.
5) Add tests in `services/api/tests/` for both endpoints.

## Customer App Schema Changes
### New fragment
Create `apps/customer-app/schemas/fragments/customer_home_notifications_v1.fragment.json`:
- `RemoteQuery` → key `customer_home.notifications_summary`
- path `/v1/notifications/home-summary`
- loading/error → subtle InfoCard (or render nothing)
- child:
  - If `primary` exists → render primary card
  - If `moreCount > 0` → render `ActiveSummary` component with counts

### Update Home screen
In `apps/customer-app/schemas/screens/customer_home.screen.json`, replace:
- `{ "ref": "section:customer_welcome_v1" }`
with:
- `{ "ref": "fragment:customer_home_notifications_v1" }`

(We keep services capsules below it.)

## Customer App UI Implementation (Option B)
We will implement an **app-level** schema component `ActiveSummary` (small and contained):

### Component behavior
Inputs (props or data scope):
- `moreCount` (int)
- `moreByService` (map)
- optional `activeCount` (int)
- optional `route` (where to navigate on tap; default to Activities)

Rendering:
- Outlined stadium pill style (same vibe as Prescription Upload `OutlinedButton`):
  - left: label like `+2 other active`
  - optionally: small outlined pills for top services, e.g. `Pharmacy 1`, `Home visit 1`

Interactions:
- Tap navigates to Activities tab or screen.

### Files (suggested)
- `apps/customer-app/lib/src/ui/active_summary_widget.dart`
- `apps/customer-app/lib/src/ui/active_summary_schema_component.dart`
- register in `apps/customer-app/lib/src/ui/customer_component_registry.dart`

No changes to `packages/*`.

## Navigation Notes
We want a stable navigation target for "View all".
Options:
- Navigate to the Activities tab directly (preferred).
- Or navigate to a dedicated `customer_notifications` screen later.

If direct tab switching is not available via schema actions today, we can implement a small app action handler `navigate_to_tab` (app-only) OR use a route that opens `customer_home` with a `params.selectedTab=activities` if supported.

## Fallback Parity
Because schemas are bundled/fallback-capable:
- Update `apps/customer-app/lib/src/schema/fallback_fragment_documents.dart` to include the new fragment (and keep it aligned).
- Ensure any new component contract (if you decide to contract it) is included under the customer app contracts.

## Testing & Validation
### Backend
- Unit tests for:
  - ordering (action_required wins)
  - counts (moreCount, moreByService)
  - route shape

### Customer App
- `flutter analyze` must pass.
- Add widget tests for `ActiveSummaryWidget`.
- (Optional) Golden tests if the repo has established patterns.

### Manual smoke checks
- Home header shows primary when there is at least one derived item.
- Multiple actives show “+N other active” indicator.
- Tap primary navigates to correct request detail.
- Tap summary navigates to Activities.

## Rollout Phases
### Phase 1 (v1)
- Derive notifications from existing request state.
- Ship Home header module + summary indicator.

### Phase 2 (push readiness)
- Add persisted notification inbox (DB-backed) OR event-sourced from `RequestEvent` (per RFC).
- App adds device token registration (FCM/APNs) and handles push to refresh query.

### Phase 3 (realtime, optional)
- Add SSE/WebSocket updates for active request changes.
- Fallback to polling while active exists.

## Open Questions
- What is the canonical service id vocabulary (`pharmacy`, `home_visit`, `ambulance`, etc.)?
- Should action_required resolve on action completion (recommended) or on open?
- How should we collapse progress spam (one per request, or last N per request)?
- Do we need a dedicated Notifications screen, or is Activities sufficient for v1?

## Related docs
- RFC: Request Detail, Workflow, and Notifications: `docs/request-detail-workflow-and-notifications-rfc.md`
