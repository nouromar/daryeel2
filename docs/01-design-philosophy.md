# Daryeel2 — Design Philosophy (Reusable, Scalable, Flexible)

## Purpose
Daryeel2 is a greenfield redesign of Daryeel with one overriding goal:

- Maximize reuse and speed of implementation without compromising scale, flexibility, or product appeal.

We do this by:
- Standardizing on a small number of core patterns.
- Building reusable components at multiple levels (atoms → sections → flows).
- Supporting managed extensions where domain-specific behavior is unavoidable.
- Designing for testability from day 1 and prioritizing high automated test coverage.

## Current repo focus

The current Daryeel2 repo is in a framework-first phase:
- A bounded schema-driven UI runtime (Flutter) plus shared components.
- A unified runtime delivery backend (`schema-service`) for schema/theme/config/telemetry.

The “one spine, many services” model remains the long-term target, but most domain-service work is intentionally deferred until the schema-driven framework is stable.

This document captures the philosophy and the “shape” of the system; subsequent docs specify backend entities and UI component inventory.

## Core principles

### 1) One spine, many services
All services (mobility/taxi, courier delivery, ambulance, pharmacy, home visit) fit into a common lifecycle:

- Request → Quote (optional) → Assign/Dispatch → Execute/Fulfill → Complete/Cancel → Pay/Invoice → Rating/Feedback → Support/Audit

The core platform owns the spine.
Services plug into it.

### 2) Schema-driven UI, bounded and safe
We intentionally invest in a schema-driven UI runtime so we can ship new screens and iterate quickly without app releases.

Constraints that keep it safe and maintainable:
- No arbitrary scripting / expression language.
- Only a bounded action set.
- Strict schema + component contract validation.

Code still matters: the schema runtime renders a closed set of native Flutter widgets (components) that remain testable, themeable, and versionable.

### 3) Reuse at multiple levels
We design reuse as a layered system:

- Atoms: buttons, inputs, chips, tiles, status pill.
- Sections: location, schedule, notes, contact, attachments, price summary.
- Flows: request builder, request tracking, provider job execution.
- Modules (service-specific): the smallest necessary custom sections/pages for a service.

Small reusable components compose into bigger reusable but customizable components.

### 4) Managed extensions over forks
When a service needs special logic, we prefer a narrow extension point over custom end-to-end flows.

Examples:
- Pricing calculators are pluggable per service.
- Dispatch scoring is pluggable per service.
- Domain subsystems (pharmacy catalog/inventory) can be separate modules, but they must converge back to the common fulfillment spine.

### 5) Events are first-class
Every meaningful change should be representable as an event in an append-only timeline.

Benefits:
- Auditing and traceability.
- Consistent “timeline UI” across services.
- Easy debugging and analytics.
- Supports asynchronous processing (notifications, matching retries).

Rating and feedback are also first-class “after completion” signals and should be recorded in a way that supports:
- Quality monitoring (provider/service performance).
- Trust and safety signals.
- Product iteration (what users liked/disliked).

### 6) Versioning and backwards compatibility
Even with code-based UI, backend contracts must evolve safely.

We adopt:
- Versioned service definitions/config.
- Stable identifiers (service slugs, option keys).
- “Ignore unknown fields” client posture.

### 7) Operational clarity and role-aware views
The same underlying entities should power role-scoped experiences:
- Customer app: request creation, tracking, history, support.
- Provider app: availability, job feed, job execution, proofs.
- Ops/admin web: dispatch, monitoring, configuration.

### 8) Security is a first-class product requirement
Security is not a checklist item at the end; it is a design constraint that shapes:
- Data modeling (what we store, how long we store it, and how it is accessed).
- APIs (auth, authorization, rate limits, validation, idempotency).
- Clients (secure storage, privacy, consent, safe UX).
- Operations (audit trails, incident response, least privilege, secrets).

We default to:
- Least privilege and explicit permissions.
- Minimize PII retention.
- Defense-in-depth (multiple layers, no single point of failure).

### 9) Testability is a first-class architecture constraint
We aim for high automated test coverage from the start.

Definitions and guardrails:
- Coverage is measured at least at the line level; prefer branch coverage where tools support it.
- Generated code and third-party code are excluded from coverage calculation.
- Coverage gates may be added per package/service as the repo stabilizes.
- High-risk areas (auth, authorization, payments, status transitions, dispatch) must have both unit tests and integration tests.
- “Hard to test” is treated as a design smell; we refactor to make code testable.

## What we are NOT doing (non-goals)
- We are not building a general-purpose scripting engine in schema/config.
- We are not encoding arbitrary UI logic (scripts) in configuration.
- We are not building separate runtime-delivery backends per product; delivery is centralized.

## Design constraints and guardrails
- Closed set of shared statuses for the fulfillment spine.
- Service-specific details live in:
  - managed extensions (pricing/matching), and/or
  - service modules (UI sections), and/or
  - domain subsystems (pharmacy catalog).
- Avoid hard-coded service branching scattered across the codebase.
  - Put service-specific branching behind a registry/adapter interface.

Security guardrails:
- Role/permission checks are centralized and testable.
- Every write operation is attributable (actor + audit event).
- Rate limiting and abuse controls exist for all public endpoints.
- Sensitive data is encrypted at rest where appropriate and protected in transit.
- Logs never contain secrets; PII logging is minimized.

Testing guardrails:
- Pure business logic is kept in testable modules (no framework dependencies).
- Side effects are behind interfaces (DB, network, clocks, randomness, queues).
- Deterministic time via injected clock.
- Deterministic IDs via injectable ID generator where needed.
- Strict linting and static analysis are part of the quality gate.

## The “add a new service” standard
Adding a new service should be a bounded checklist:

1. Define the service: slug, name, capabilities.
2. Implement minimal service modules:
   - customer request sections (if needed)
   - provider execution checklist/proofs (if needed)
3. Configure pricing strategy.
4. Configure dispatch eligibility/scoring.
5. Ensure tracking timeline is complete and consistent.
6. Ensure rating/feedback capture and reporting are enabled.
7. Ensure analytics/ops dashboards can filter by service.
8. Ensure security posture is defined: data classification, permissions, abuse/rate limits.

If adding a new service requires touching many unrelated files, the architecture needs another layer of reuse.
