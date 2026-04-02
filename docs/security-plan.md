# Daryeel2 schema-driven UI — Security plan (Milestone D1)

## Scope
This document covers security guardrails for schema/theme delivery and schema-driven runtime execution.

Assumptions:
- **Schemas, fragments, and themes are untrusted input** (even when served by our own services).
- The client must be safe under malicious or accidental inputs (DoS, cycles, invalid structures).
- The server must validate and reject unsafe documents during authoring/CI.

## Threat model (summary)
### Primary risks
- **Denial-of-service**
  - Oversized JSON payloads (memory/CPU spikes during download, decode, and validation)
  - Pathological reference graphs (deep chains, fan-out, cycles)
  - Excessive node counts (render/parse cost)
- **Unsafe external interactions**
  - Schema-driven `open_url` actions could exfiltrate users to arbitrary hosts
  - Future remote assets could be used for tracking or content injection

### Non-goals (for this milestone)
- Full sandboxing of component execution (we only render allowlisted components).
- Formal verification of schema constraints.

## Hard budgets
Budgets are intentionally conservative. They are enforced on both the server (authoring validation) and client (runtime safety).

| Budget | Value | Client enforcement | Server enforcement |
|---|---:|---|---|
| Max schema JSON bytes | 256 KiB | `SecurityBudgets.maxSchemaJsonBytes` + HTTP loaders check `response.bodyBytes.length` | `MAX_JSON_BYTES` in `services/schema-service/app/validate_all.py` |
| Max nodes per document | 5,000 | `parseScreenSchemaWithDiagnostics(..., maxNodes: ...)` | `MAX_NODES_PER_DOCUMENT` in `services/schema-service/app/validate_all.py` |
| Max ref resolution depth | 32 | `resolveScreenRefs(..., maxDepth: ...)` / `resolveScreenRefsWithDiagnostics` | `MAX_REF_DEPTH` in `services/schema-service/app/validate_all.py` |
| Max fragments per screen | 200 | `resolveScreenRefs(..., maxFragments: ...)` / `resolveScreenRefsWithDiagnostics` | `MAX_FRAGMENTS_PER_SCREEN` in `services/schema-service/app/validate_all.py` |

Client budget constants live in `packages/flutter_runtime/lib/src/security/security_budgets.dart`.

## Guardrails
### 1) Treat schema input as untrusted
- Never assume remote JSON is valid or small.
- Fail closed: invalid or over-budget documents must not be rendered.
- Emit diagnostics with stable reason codes for support/debug.

### 2) Limit payload sizes
Client:
- All schema/fragment HTTP fetch paths must check `response.bodyBytes.length <= SecurityBudgets.maxSchemaJsonBytes` before `jsonDecode`.

Server:
- CI/validation must enforce `MAX_JSON_BYTES` for all example documents.

### 3) Limit reference resolution complexity
- Enforce maximum ref depth and maximum unique fragments per screen.
- Detect and report cycles.

### 4) Prohibit remote URLs unless whitelisted
- The runtime supports schema-driven `open_url`, but it MUST be gated behind an allowlist policy (scheme + host) and fail closed.
- Apps should configure a restrictive `SchemaActionPolicy` + `UriPolicy` (default is allow-all for legacy).

## Diagnostics expectations
On budget violations, clients should emit:
- `runtime.schema.budget_exceeded` with `budgetName`, `limit`, and `actual`.

On parse/ref failures:
- `runtime.schema.parse_failed`
- `runtime.schema.ref_resolution_failed`

## Operational checklist
- Keep budgets consistent across server and client.
- Update this doc when budgets change.
- Add/extend tests when introducing new schema capabilities that could increase runtime cost.
