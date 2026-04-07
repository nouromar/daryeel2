# Daryeel2 — Backend Design (Reusable Entities)

## Goals
- Support multiple services under one scalable platform.
- Keep a stable “spine” model shared across services.
- Allow managed extensions for service-specific behavior.
- Preserve auditability and operational visibility.
- Treat security as a first-class cross-cutting requirement.
- Prioritize high automated test coverage for Daryeel2 backend code.

## Current repo state (implementation notes)

This document is primarily a conceptual model. The current codebase has two backend services:
- `services/schema-service/`: unified runtime delivery backend (schema/theme/config/telemetry) intended to be cache-friendly and largely public.
- `services/api/`: product/domain APIs.

API route convention (current repo rule): domain routes must be grouped by product service under a stable prefix:
- `/v1/<service>/...` (example: `/v1/pharmacy/...`)

Examples implemented today:
- `GET /v1/service-definitions`
- `GET /v1/pharmacy/catalog`
- `POST /v1/pharmacy/prescriptions/upload`

## Conceptual model

### Core spine
- ServiceDefinition: what a service is.
- ServiceRequest (the “job”): a customer request for a service.
- Assignment/Dispatch: how a request gets a provider.
- Fulfillment: executing the work.
- Events: append-only timeline.
- Payments: standardized representation of money and payers.
- Ratings/Feedback: standardized post-fulfillment signals.

### Managed extensions
- Pricing strategy per service.
- Matching/scoring per service.
- Domain modules when needed (e.g., pharmacy catalog/inventory).

## Entities (proposed)

### 0) Identity (Users, organizations, roles)
The spine entities reference users/providers/staff by stable IDs. Identity data should live in a small, explicit set of tables so it’s not duplicated across service modules.

Recommended model (minimum viable, extensible):
- User
  - id (uuid; primary internal identifier)
  - phone_e164 (nullable; unique when present)
  - phone_verified_at (nullable)
  - email (nullable; unique when present)
  - is_active
  - created_at, updated_at
- Organization
  - id (uuid)
  - name
  - type (e.g., platform, partner, employer, clinic)
  - is_active
- OrganizationMembership
  - id (uuid)
  - org_id
  - user_id
  - role (customer/provider/dispatcher/admin)
  - is_active
  - created_at

Profile tables (optional but common):
- UserProfile (names, preferred language, optional demographic fields)
- ProviderProfile (vehicle/equipment/profession, verification state)
- StaffProfile (department, permissions, audit requirements)

Notes:
- Keep authentication identifiers (phone/email) separate from the immutable internal identifier (`user.id`).
- PII fields (phone, email) should be normalized, access-controlled, and redacted in logs.

### ID generation (row IDs)
Default recommendation: use UUIDs everywhere (Postgres `uuid`), preferably time-sortable UUIDv7.

Why:
- Works well for distributed systems and offline-capable clients.
- Avoids “guessable” sequential IDs in URLs.
- UUIDv7 improves index locality vs random UUIDs.

Guidance:
- Use DB-generated UUIDv7 (preferred) or app-generated UUIDv7/ULID; be consistent.
- If you keep internal bigint IDs for some tables, also expose a non-guessable public identifier for external APIs.

### 1) ServiceDefinition
Represents a service like taxi, delivery, ambulance, pharmacy, home_visit.

Fields (minimum):
- id (uuid; see ID generation above)
- slug (string, stable identifier: "taxi", "delivery")
- display_name
- category (healthcare, commerce, mobility)
- is_active
- capabilities (structured):
  - requires_pickup (bool)
  - requires_dropoff (bool)
  - supports_scheduling (bool)
  - supports_attachments (bool)
  - supports_live_tracking (bool)
  - supports_items (bool) — for commerce-like services

Notes:
- The platform uses `slug` as the stable key.
- Capabilities should be used to drive product behavior and avoid scattered service branching.

### 2) ServiceRequest
The single core record for “something a customer wants fulfilled”.

Fields (minimum):
- id
- service_id
- customer_user_id (references User.id; the stable customer identifier)
- status (core spine status)
- sub_status (optional, service-specific string)
- priority (optional)
- scheduled_at (optional)
- pickup_location (nullable; structured Location object; see below)
- dropoff_location (nullable; structured Location object; see below)
- notes (nullable)
- payload_json (nullable) — service-specific data, validated by service module
- quote_id (nullable)
- assigned_provider_user_id (nullable)
- created_at, updated_at

Location structure (what “structured” means here):
- A predictable JSON object with well-known fields (not a single free-text string).
- The main goal is to support mapping, distance calculations, geofencing/region routing, and consistent display across clients.

Suggested shape (API + DB JSONB):
```json
{
  "text": "Hodan, Mogadishu — near XYZ",
  "lat": 2.046934,
  "lng": 45.318162,
  "accuracy_m": 15,
  "place_id": "optional-provider-place-id",
  "region_id": "optional-internal-region-id"
}
```

Notes:
- Store as `jsonb` (fast iteration) or split into columns (e.g., `pickup_lat`, `pickup_lng`, `pickup_text`) if you need indexing/performance; either way, keep the logical schema consistent.
- Validate this object in the API layer (Pydantic) and treat `lat/lng` as the canonical location when present.

Why payload_json even with code-based UI:
- It isolates service-specific fields without adding columns for every new service.
- It enables managed evolution over time.

Primary customer identifier (clarification):
- Internally and in foreign keys: `User.id`.
- For login/contact: typically `User.phone_e164` (verified) and/or email.
- Phone numbers can change/recycle; treat phone/email as login identifiers, not as the immutable identity.

### 3) RequestEvent (append-only)
A normalized timeline for every request.

Fields:
- id
- request_id
- type (string; e.g. "status_changed", "provider_assigned", "proof_captured")
- from_status (nullable)
- to_status (nullable)
- actor_type (customer/provider/dispatcher/system)
- actor_id (nullable)
- metadata_json (nullable)
- created_at

Rules:
- Events are never mutated; corrections are new events.
- The current status in ServiceRequest is derived from latest status event (but can be stored as a denormalized field for fast reads).

### 4) Quote + PricingBreakdown
Quotes are optional (some services are fixed-fee).

Quote fields:
- id
- request_id
- currency
- total_amount
- breakdown_json (list of line items)
- is_estimate (bool)
- created_at

Breakdown line item shape (example):
- code ("base", "distance", "surge", "delivery_fee")
- label
- amount
- metadata (optional)

### 5) Provider + Capability + Availability
Providers can fulfill different services.

Provider fields:
- user_id
- provider_type (person/org)
- verification state (optional)

ProviderCapability:
- provider_user_id
- service_id
- constraints_json (vehicle class, equipment, profession)
- is_active

ProviderAvailability:
- provider_user_id
- status (offline/available/busy)
- note
- last_seen_at
- optional: service toggles per service

### 6) Assignment / Dispatch
Keep dispatch generic; service-specific logic is a scoring plugin.

DispatchAttempt (optional but useful):
- id
- request_id
- strategy ("broadcast", "ranked_offer")
- parameters_json (optional; strategy knobs like radius, max_offers, TTL)
- created_at

ProviderOffer:
- id
- request_id
- dispatch_attempt_id (optional)
- provider_user_id
- status (offered/accepted/declined/expired)
- offered_at
- expires_at
- responded_at (nullable)
- score (nullable; useful for ranked offers)
- metadata_json (nullable; e.g., decline reason)
- created_at

Offer lifecycle (high level):
- System selects eligible providers (capability + availability + basic constraints).
- Create offers with a TTL and deliver them (push notification + in-app polling/stream).
- Provider responds (accept/decline). First valid accept wins; other outstanding offers are cancelled/expired.
- On accept, atomically assign `ServiceRequest.assigned_provider_user_id` (use a DB transaction + status check).

Routing / dispatch “plumbing” notes:
- Treat notification delivery as best-effort; the source of truth is the offer row in DB.
- Support retries by creating a new `DispatchAttempt` and additional offers.
- Emit RequestEvents for dispatch milestones (offer_created, offer_accepted, provider_assigned, dispatch_retry).
- Keep idempotency keys on “accept offer” to avoid double-accept from flaky networks.

### 7) Proofs / Attachments
A generic mechanism for POD, prescription photos, signatures.

Attachment:
- id
- request_id
- type (photo/document/signature)
- url
- created_by_actor
- created_at

### 8) Payments
Separate payment records from service logic.

PaymentIntent / PaymentRecord:
- request_id
- payer_type (customer/org/insurance)
- method (cash/card/wallet/invoice)
- status
- amounts

Where payment details live (important):
- Do NOT store raw credit card numbers, CVV, or bank account/routing numbers in your DB.
- Store only tokenized references returned by a payment processor (Stripe/Adyen/etc.) plus non-sensitive display fields.

If a “custom payment method” does NOT provide a reusable token:
- Prefer treating the method as an *ephemeral* payment instruction used only for a single PaymentIntent.
- Accept the required fields at payment time (e.g., mobile money MSISDN, bank transfer reference) and do not persist them beyond what’s needed for reconciliation/support.
- Still do NOT store secrets like PINs, OTPs, USSD session codes, or anything that would let someone charge the customer.
- If you must persist a reusable identifier, store only a non-sensitive identifier (e.g., masked MSISDN) and/or encrypt a minimal “handle” with strict access controls.

Does this support Africa/local payment methods?
- Yes, as long as you model them as a `PaymentMethod` backed by some “processor/rail integration” (often an aggregator) and store only a token/reference + safe display metadata.
- Examples that fit this model: Mobile Money (M-Pesa / MTN MoMo / Airtel Money), bank transfer/virtual account, USSD flows, agent cash collection.
- The core trick is that “custom payment method” usually means a different processor/rail, not a different database shape.

Suggested additional entities:
- PaymentCustomer
  - id (uuid)
  - owner_type (user/org)
  - owner_id
  - processor ("stripe", ...)
  - processor_customer_id
  - created_at
- PaymentMethod
  - id (uuid)
  - payment_customer_id
  - method_type (card/bank/wallet/mobile_money/bank_transfer/ussd/cash)
  - processor_payment_method_id (nullable; token/reference when a processor supports it)
  - details_encrypted_json (nullable; minimal non-secret details only; field-level encryption)
  - display_json (brand, last4, exp_month/year, bank_name, telco, msisdn_masked) — non-sensitive only
  - is_default
  - created_at

Notes:
- For bank payouts to providers (if applicable), also store only tokenized payout/bank references from the processor.
- Treat all payment identifiers as sensitive; encrypt where appropriate and restrict access.
- Keep “details” strictly limited. Example allowed: `msisdn` (phone number) for mobile money (encrypted + masked). Example forbidden: any PIN/OTP/CVV, or full bank account numbers.

### 9) Ratings and feedback
Every service benefits from a consistent, first-class mechanism to capture quality signals.

Design goals:
- One unified rating model across services.
- Support both quick-star ratings and richer structured feedback.
- Support role-aware rating (customer → provider, provider → customer, dispatcher → provider) without hard-coding service logic.
- Support moderation/visibility rules.

RequestRating (core):
- id
- request_id
- service_id (denormalized for filtering)
- rater_actor_type (customer/provider/dispatcher/admin/system)
- rater_actor_id
- ratee_actor_type (provider/customer/organization)
- ratee_actor_id
- rating (int 1–5)
- comment (nullable)
- tags_json (nullable; e.g., ["late", "polite", "careful", "professional"])
- is_anonymous (optional)
- is_public (optional; public testimonials vs internal QA)
- created_at

RequestFeedback (optional, for non-star feedback):
- id
- request_id
- actor_type, actor_id
- category ("bug", "safety", "pricing", "service_quality", "other")
- message
- metadata_json (nullable)
- created_at

Notes:
- For most MVPs, `RequestRating` alone is sufficient; `RequestFeedback` is useful when you want a separate channel for support/safety issues.
- Aggregate ratings (provider average, service average) should be computed asynchronously into summary tables or caches to avoid heavy queries.

## Status model (core)
Core statuses should be consistent across services:
- requested
- assigned
- en_route
- in_service
- completed
- cancelled

Service-specific milestones:
- Represent as RequestEvent types and/or sub_status.

## Service module interface (backend)
Every service implements a narrow interface:

- validate_request_payload(payload_json, core_fields)
- compute_quote(request) (optional)
- eligible_providers(request)
- score_provider(request, provider)
- required_proofs_for_completion(request)

The platform orchestrates the flow; the service module provides the differences.

## API surface (high level)
- GET /services
- GET /services/{slug}
- POST /requests
- GET /requests (role-scoped)
- GET /requests/{id}
- POST /requests/{id}/assign
- POST /requests/{id}/status
- GET /requests/{id}/events
- POST /requests/{id}/attachments
- POST /requests/{id}/rating
- GET /requests/{id}/rating (optional)
- GET /providers/{id}/ratings (optional)

## Security (first-class)

### Threat model (what we assume)
- Attackers may attempt credential stuffing, OTP abuse, scraping, spam, and denial-of-service.
- Users may attempt unauthorized access (IDOR) to other users’ requests.
- Providers and customers may attempt fraud (fake proofs, disputes).
- Malicious inputs may target injection, file upload abuse, and unsafe deserialization.

### Identity and authentication
- Use a standard, short-lived access token (JWT) plus refresh token, or opaque tokens backed by server sessions.
- Tokens must include issuer/audience, expiry, and subject.
- Rotate signing keys and support key IDs (kid) for rollover.
- Support device identifiers for provider presence and abuse detection.

### Authorization (role + resource scoped)
Core rule: every request access is checked by BOTH role and resource scope.

Examples:
- Customer: can read/write only their own requests.
- Provider: can read/write only requests assigned to them (or offered to them).
- Dispatcher/Admin: can access requests in allowed org/region scopes.

Implementation guidance:
- Centralize authorization in reusable dependencies/helpers (not scattered in routes).
- Use explicit permission verbs (read_request, assign_request, update_status, view_pii).
- Prefer server-side checks; never trust client-provided role/service.

### Data classification and minimization
Classify fields:
- Public/low sensitivity: service slug, status, timestamps.
- Sensitive: phone numbers, addresses, precise GPS, medical notes, prescriptions.
- Highly sensitive: credentials, tokens, key material.

Guidelines:
- Store only what is needed to deliver the service and provide support/audit.
- Define retention windows (e.g., precise GPS for X days; keep coarse summaries longer).
- PII should be masked/redacted in logs and analytics by default.

### Encryption and secrets
- TLS everywhere.
- Encrypt sensitive blobs at rest (attachments, prescriptions) using KMS-managed keys.
- Never store secrets in source control; use secret managers and environment injection.
- Hash/verify OTP codes; never store raw OTP.

### Auditability
- All writes that change state (status changes, assignments, payouts, refunds) emit immutable events with actor attribution.
- Admin/dispatcher actions must be recorded with reason notes.
- Rating/feedback moderation actions are audited.

### Abuse prevention and rate limiting
- Rate limit OTP and login flows aggressively.
- Rate limit request creation and attachment uploads.
- Add per-IP and per-account quotas.
- Add idempotency keys for create endpoints to prevent accidental duplicates.

### Input validation and safe parsing
- Validate payload_json per service module.
- Validate files (type, size, virus scan, content sniffing).
- Reject unknown fields where appropriate (or ignore safely with versioning).
- Use parameterized DB queries (ORM-safe patterns).

### File uploads
- Use pre-signed upload URLs to object storage when possible.
- Store metadata in DB; keep access controlled (signed URLs with short TTL).
- Scan uploads (malware), limit size and mime types.

### Operational security
- Least-privilege database roles and network segmentation.
- Structured logs with PII redaction.
- Monitoring/alerts on abnormal rates (OTP attempts, request spam, assignment overrides).
- Backups and disaster recovery tested.

### Extension security
Managed extensions (pricing/matching/domain modules) must obey:
- No direct access to secrets unless explicitly granted.
- Stable interfaces; validate inputs and outputs.
- Audit side effects via events.

## Testing and coverage (first-class)

### Coverage policy
- Target: 100% automated coverage for Daryeel2 backend code.
- Exclusions: generated code, migrations auto-generated boilerplate, vendored/third-party.
- Prefer branch coverage in addition to line coverage when feasible.
- Enforce coverage gates in CI (build fails if below threshold).

### Test pyramid (backend)
1) Unit tests (fast, deterministic)
- Service module validation logic
- Status transition policy
- Pricing calculators
- Matching/scoring functions
- Permission checks (authorization policy)

2) Integration tests (DB + API)
- Request create/read/list (role-scoped)
- Assignment flows and offers
- Status updates produce events with correct actor attribution
- Ratings/feedback endpoints and permissions
- Attachment metadata creation and access control

3) Contract tests (clients)
- Validate API response shapes for critical endpoints (requests, events, ratings)
- Ensure backwards compatibility and safe evolution

### Security testing (minimum)
- Authorization tests for IDOR prevention (cross-user request access)
- Rate limit tests for OTP/login and request creation
- Input validation tests (invalid payload_json, unknown fields)
- Attachment upload constraints (size/mime)

### Determinism guidelines
- Inject clock for time-dependent logic.
- Avoid global randomness; inject RNG if required.
- Use idempotency keys for create operations and test idempotency behavior.

Service-specific APIs remain possible (pharmacy catalog), but fulfillment should still map back to ServiceRequest.

## Scalability notes
- Keep request reads fast via denormalized current status + indexed service_id/status/assigned_provider.
- Events enable async workers (notifications, dispatch retries) via event stream.
- Partitioning by date/region can be introduced later without changing the conceptual model.
