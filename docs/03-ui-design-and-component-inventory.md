# Daryeel2 — UI Design Philosophy & Component Inventory

## Goals
- Highly reusable code-based UI across ~10 services.
- Fast implementation via shared flows and shared building blocks.
- Service-specific UI should be small and isolated (modules).
- Consistent, appealing UX across customer and provider experiences.
- Ratings and feedback are a shared capability across services.
- Security and privacy are first-class UX requirements across services.
- Target high automated test coverage for Daryeel2 UI code (treat 100% as an aspirational goal, not a current enforced gate).

Current implementation note (this repo snapshot):
- Schema-driven UI is validated against strict component contracts (`packages/component-contracts/`) and rendered in Flutter via the schema runtime packages.
- A core schema `Text` component exists for titles/labels/one-line text with bounded styling props.

Security UX principles:
- Least privilege: show only what a user needs at each step.
- Minimize exposure of phone numbers and addresses.
- Clear consent for sensitive capabilities (location, camera, medical attachments).
- Safe defaults and friction only where it reduces real risk (OTP, proofs, confirmations).

## Reuse strategy (layers)

### Layer 1 — Atoms (most reusable)
Small primitives used everywhere.

Customer + Provider atoms:
- Primary/secondary buttons, destructive buttons
- Text fields, text areas, numeric fields
- Choice chips, toggle tiles, radio/select lists
- Loading/empty/error states
- Status pill/badge
- Section headers, dividers
- Icon + label tiles

### Layer 2 — Reusable widgets
- RequestCard (service badge + pickup/dropoff summary + status)
- Timeline widget (events list)
- Contact actions (call/chat/WhatsApp)
- Price breakdown widget
- Attachment picker + preview grid
- Map preview / open-in-maps button
- ETA widget (time/distance)
- Live location indicator (sharing on/off)
- RatingStars widget (1–5)
- FeedbackTags widget (predefined selectable chips)
- FeedbackComment box
- PrivacyNotice / ConsentNotice widget
- PiiMaskedText widget (phone/address masking)
- SecureCodeEntry widget (OTP/PIN)

### Layer 3 — Sections (compose into forms and details)
Sections are the default unit of reuse for request creation and request details.

Shared sections (customer app):
- LocationSection (pickup, dropoff, saved places)
- ScheduleSection (ASAP vs scheduled)
- NotesSection
- ContactSection (confirm patient, pickup/dropoff contacts)
- OptionsSection (service options as toggles/choices)
- AttachmentSection (photos/docs)
- PriceSummarySection
- Consent/SafetySection (healthcare)
- RatingSection (stars + tags + optional comment; post-completion)
- TrackingSection (composed; see Tracking model below)
- Privacy/ConsentSection (location/camera/medical attachments disclosures)

Shared sections (provider app):
- RouteSection (pickup/dropoff, open maps)
- CustomerContactSection
- NotesSection
- ChecklistSection (steps and required proofs)
- ProofCaptureSection (photo, OTP, signature)
- StatusActionBar (next action buttons)
- RatingSection (optional; can be internal-only)
- TrackingSection (provider-side; route + live sharing)
- SecuritySection (re-auth prompts for sensitive actions where needed)

### Layer 4 — Flows (shared pages)
The platform should prefer a small set of shared flows.

Customer app shared flows:
- Service picker / home
- Request builder (single page or stepper)
- Request confirmation
- Active request tracking (map + timeline + actions)
- Request history
- Request detail (generic)
- Rating & feedback prompt (post-completion)
- Support entry points
- Account security (optional): sign out, device sessions, delete account (policy-driven)

Provider app shared flows:
- Availability (offline/available/busy)
- Job feed (offers/assigned)
- Job detail (route, notes, checklist)
- Execution (status updates, proof capture)
- History/earnings (optional)
- Rating & feedback (optional, role-based)
- Account security (optional): sign out, device sessions, re-auth on sensitive actions

### Layer 5 — Service modules (minimal custom UI)
Each service contributes the smallest necessary UI module(s), built from shared sections.

## Component inventory by app

## Tracking model (first-class, reusable)
Request tracking is intentionally modeled as two layers that compose together:

1) Status tracking (timeline/state)
- Always available for all services.
- Driven by request status + request events.

2) Location tracking (movement/ETA)
- Optional per service and per request.
- May be map-based or non-map-based (ETA-only).

Capability flags (from service meta/config) used by the shared tracking screens:
- supports_live_tracking: bool
- tracking_mode: none | eta_only | map
- show_provider_contact: bool (privacy/security dependent)

Shared tracking panels:
- StatusTimelinePanel (events list + current status pill)
- LiveMapTrackingPanel (vehicle/courier/ambulance position + route preview)
- EtaOnlyTrackingPanel (ETA + textual updates without map)
- ProviderCardPanel (provider info + contact actions, if allowed)
- SupportActionsPanel (WhatsApp/call/email)
- LocationSharingConsentPanel (explicit consent when required)

## A) Customer (Patient) app — inventory

### Shared screens
- ServiceHomeScreen (service cards)
- RequestBuilderScreen (composes sections)
- RequestConfirmationScreen
- RequestTrackingScreen (timeline, map, contact/support, cancel)
- RequestHistoryScreen
- RequestDetailScreen (generic)
- RequestRatingScreen/Sheet (shared)

### Shared sections
- PickupDropoffSection
- ScheduleSection
- NotesSection
- ContactSection
- OptionsSection
- AttachmentsSection
- PriceSummarySection
- SafetyGuidanceSection
- RatingSection
- TrackingSection (StatusTimelinePanel + optional LiveMapTrackingPanel/EtaOnlyTrackingPanel)

### Service-specific modules
Taxi/ride:
- RideOptionsModule (ride class, passengers, accessibility)

Delivery/courier:
- PackageDetailsModule (size/weight/fragile)
- ProofPreferenceModule (photo/OTP/signature)
- MultiStopModule (optional; later)

Ambulance:
- UrgencyModule (severity)
- SymptomsModule (triage questions)
- EquipmentNeedsModule (oxygen/stretcher)

Pharmacy:
- CatalogModule (browse/search)
- CartModule
- PrescriptionModule
- CheckoutModule
- PharmacyOrderDetailsPanel (inside generic tracking/detail)

Home care/visit:
- VisitTypeModule (nurse/doctor)
- IntakeModule (symptoms, preferences)
- AttachmentsModule (labs/photos)

## B) Provider app — inventory

### Shared screens
- ProviderAvailabilityScreen
- ProviderJobFeedScreen
- ProviderJobDetailScreen
- ProviderJobExecutionScreen (status + proofs)
- ProviderHistoryScreen
- ProviderRatingScreen/Sheet (optional)

### Shared sections
- JobHeaderSection (service badge, priority, status)
- RouteSection (pickup/dropoff, open maps)
- CustomerContactSection
- NotesSection
- ChecklistSection
- ProofCaptureSection
- StatusActionBar
- RatingSection (optional)
- TrackingSection (RouteSection + optional live-sharing controls)

### Service-specific modules
Taxi/ride:
- PickupFlowModule (arrived/waiting)
- RideStartStopModule

Delivery/courier:
- PickupProofModule
- DropoffProofModule

Ambulance:
- EquipmentChecklistModule
- HandoffModule

Pharmacy delivery:
- OrderPickupChecklistModule (if needed)
- Standard DropoffProofModule

Home visit:
- VisitChecklistModule
- VisitNotesModule (role/scoped)

## Service UI contracts (how code stays reusable)
Rather than scattering service branching across screens, define a registry.

Each service implements:
- ServiceMeta: label/icon/category
- CustomerRequestSectionsBuilder: returns sections for the request builder
- CustomerDetailPanelsBuilder: optional extra panels for tracking/detail
- ProviderChecklistBuilder: steps + proofs
- StatusPolicy: allowed transitions (optional)
- RatingPolicy: who can rate whom, which tags to show, when to prompt

The shared flows call the registry and render the composed sections.

## UX rules to keep consistency
- Common navigation model across services.
- Common tracking timeline UI across services.
- Common phrasing for statuses.
- Ratings/feedback should be low-friction (stars + a few tags) with optional comment.
- Avoid exposing full PII unless necessary (mask phone/address; reveal on action).
- Confirm sensitive actions (cancel, complete, refunds, assignment overrides) with clear language.
- Prefer in-app contact relay (if available) over raw phone exposure.
- Avoid one-off UI components unless they become shared.

## Practical guidance: build order
To implement quickly:
1) Build shared customer request builder with Location/Schedule/Notes/Options.
2) Build shared tracking page with Timeline + Contact + Cancel.
3) Build the rating prompt and storage path (post-completion).
4) Add Taxi and Delivery first (they validate the spine).
5) Add Ambulance and Home Visit (adds triage + scheduling emphasis).
6) Plug pharmacy fulfillment tracking into the generic tracking page; keep catalog/cart as domain UI.

## Testing and coverage (UI)

### Coverage policy
- Target: 100% automated coverage for Daryeel2 UI code where tooling allows.
- Exclusions: generated localization files, generated API clients, and third-party.
- Enforce coverage gates in CI.

### Customer/Provider app test strategy
- Unit tests: state/controllers, validators, mapping functions.
- Widget/component tests: shared sections (LocationSection, StatusActionBar, RatingSection).
- Integration tests: end-to-end request flow (create → track → complete → rate).
- Golden/snapshot tests (optional): key shared screens to prevent UI regressions.

### Security/privacy UX testing (minimum)
- PII masking behavior
- Consent prompts shown for location/camera
- Sensitive actions require confirmation
