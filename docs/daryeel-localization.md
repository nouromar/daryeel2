# Daryeel Localization (E2E)

## 1. Purpose

Daryeel’s UI is schema-driven and delivered remotely. Localization must support:

- Remote UI copy (labels, hints, titles, button text, empty states) without app releases
- In-app language switching independent of device locale
- Offline-safe behavior using Last-Known-Good (LKG) caches
- Minimal overhead and bounded inputs (safe-by-default)

This document describes the end-to-end design: schema format, bundle format, backend delivery, client runtime integration, caching, budgets, migration, and verification.

## 2. Scope

### In scope (must localize)

User-facing UI copy:
- Schema-provided strings: titles, labels, hints, tab labels, button labels, helper text, empty states, etc.
- Form validation errors shown to users (field-level messages)

### Out of scope (do NOT localize)

- System/debug/diagnostic text
- Developer tooling / internal telemetry messages
- Backend log strings

## 3. Target languages

- English (`en`)
- Somali (`so`)

## 4. Key decision: keys + bundles (default)

We standardize on **translation keys in schema** and **external i18n bundles** fetched by the runtime.

### Why keys (vs translation blocks in schema)

Keys + bundles are the best fit for:

- In-app language switching (swap bundle, re-render; no schema refetch)
- Small schema payloads
- Better caching (copy changes don’t invalidate entire schemas)
- Reuse across fragments/screens (one key, many usages)
- Centralized translation workflow and QA

### When translation blocks are allowed (exception)

Only for rare, intentional cases:

- A one-off experimental schema where shipping a fully self-contained document is required
- Temporary bootstrapping during migration

Even then, plan to migrate to keys.

## 5. Schema wire format

Any schema “text prop” must accept either legacy string or a localized value object.

### 5.1 Localized text value (recommended)

```json
{
  "key": "customer.tabs.home",
  "fallback": "Home"
}
```

Rules:
- `key` is required and must be non-empty.
- `fallback` is optional but strongly recommended for migration safety.
- If `key` is missing/invalid, fall back safely.

### 5.2 Legacy string (supported for backwards compatibility)

```json
"Home"
```

Runtime behavior:
- Use the string as-is (no lookup).

### 5.3 Optional exception: inline translations (allowed but discouraged)

```json
{
  "i18n": { "en": "Home", "so": "Bogga Hore" },
  "fallback": "Home"
}
```

Runtime behavior:
- If `i18n[activeLocale]` exists, use it.
- Else use locale fallback chain.
- Else use `fallback`.

## 6. Bundle format

Bundles are immutable JSON documents delivered per `(product, locale)`.

### 6.1 Bundle document shape

```json
{
  "bundleVersion": 1,
  "product": "customer_app",
  "locale": "so",
  "createdAt": "2026-04-05T00:00:00Z",
  "strings": {
    "customer.tabs.home": "Bogga Hore",
    "customer.tabs.account": "Akoon",
    "form.error.required": "Waa loo baahan yahay"
  }
}
```

### 6.2 Constraints / normalization

- Keys are trimmed, non-empty, and length-bounded.
- Values are strings and length-bounded.
- Duplicate keys are rejected (preferred) or last-write-wins (only if necessary).
- Render as plain text (no markup execution).

## 7. Locale selection & switching (client)

### 7.1 Locale sources (priority order)

1. User override (persisted; selected in-app)
2. Device locale (used only if no user override)
3. Default fallback: `en`

### 7.2 Locale fallback chain

When resolving a key:
- If locale is region-specific (e.g. `so-SO`), try:
  - `so-SO` → `so` → `en` → `fallback` → key itself

### 7.3 In-app switching behavior

When user changes language:
- Update persisted override
- Trigger a bundle load for the new locale (use cache first)
- Re-render schema UI with the new bundle

## 8. Backend delivery

### 8.1 Endpoints (schema-service)

Add a bundle fetch endpoint:
- `GET /i18n/bundles?product=customer_app&locale=so`

Response:
- Bundle JSON
- Caching headers:
  - `ETag`
  - `Cache-Control: public, max-age=..., stale-while-revalidate=...`
  - Optional: `x-daryeel-doc-id`

### 8.2 Compilation responsibility (where bundles are “compiled”)

Bundles are compiled in CI/server-side, not by Flutter build tooling.

“Compile” means:
- Validate translation source files
- Normalize keys/values
- Enforce budgets
- Produce deterministic JSON bundles
- Publish as immutable assets served by schema-service

## 9. Client runtime integration

### 9.1 Runtime components (conceptual)

- `LocaleController`
  - Holds active locale, persists user override, notifies on change
- `I18nBundleStore`
  - Loads bundle from: bundled fallback (optional) → LKG cache → remote
  - Exposes `resolve(key)` lookup
- `I18nScope`
  - Inherited access for schema components and shared widgets

### 9.2 Text resolution API

Define one resolver used everywhere schema text appears.

Inputs:
- raw schema value: `string | {key,fallback} | {i18n,...}`

Output:
- resolved `String`

Rules:
- Legacy string: return it
- Key object: resolve from store, use fallback chain
- Inline block: pick best match, use fallback chain
- Always return some string (never crash UI for missing translations)

### 9.3 Where resolution happens

- Prefer resolving in schema component builders (central helper) so widgets receive plain strings.
- Avoid passing raw schema maps deep into widgets.

## 10. Form validation localization

Validation messages shown to users are UI copy and must be localized.

### 10.1 Replace raw English strings with error codes

Instead of returning strings like `"Required"`, return codes:
- `required`
- `too_short`
- `too_long`
- `invalid_format`
- `invalid_selection`
- `invalid_number`
- `too_small`
- `too_large`

### 10.2 Map codes to i18n keys

Examples:
- `required` → `form.error.required`
- `too_short` → `form.error.too_short`

## 11. Caching & offline behavior (LKG)

### 11.1 LKG rules

On app start / screen render:
1. Load bundled baseline bundle (optional)
2. Load persisted LKG for active locale (if present)
3. Fetch remote best-effort; if newer, replace LKG

### 11.2 Cache keys

Persist LKG by:
- product
- locale
- (optional) bundle doc-id/version

### 11.3 Failure behavior

If remote fetch fails:
- Keep using LKG (or bundled fallback)
- Do not block UI

## 12. Relationship to Flutter `gen-l10n`

`flutter gen-l10n` generates `AppLocalizations` from ARB files for app-compiled strings.

Use it for:
- Non-schema app screens (e.g. settings / login if hardcoded)
- Flutter framework widget localization
- Labels for language picker UI

Do not use it as the primary mechanism for schema-delivered UI copy.

## 13. Security & budgets

Bundles are untrusted inputs when delivered remotely. Enforce budgets:

- Max bundle JSON bytes
- Max number of keys
- Max key length
- Max value length

Fail-safe behavior:
- If bundle exceeds budgets, reject it and keep LKG/bundled fallback

## 14. Migration strategy

1. Add runtime i18n support (store, resolver, switching)
2. Start serving bundles with a minimal key set
3. Update high-impact components first:
   - tabs
   - primary action bars / buttons
   - text inputs (label/hint)
4. Convert form validation to error codes + localized messages
5. Migrate schemas gradually from literal strings → `{key,fallback}`

During migration:
- Always include `fallback` so missing keys don’t break UX.

## 15. Testing strategy

### Unit tests (Dart)

- Resolver behavior:
  - legacy string returns unchanged
  - key lookup success
  - key missing uses fallback
  - locale fallback chain works (`so` → `en`)
- Bundle budget enforcement
- Validation error code mapping

### Widget tests (Flutter)

- Switching locale triggers re-render and UI text changes
- Form errors display localized strings after validation

### Backend tests (Python)

- Bundle endpoint returns stable ETag/doc-id
- Budget enforcement + invalid payload handling
- Locale parameter validation (`en`, `so`)

## 16. Operational checklist (release readiness)

- Bundles are immutable and cacheable (`ETag` set, doc-id stable)
- LKG is stored and survives restart
- Switching language does not require schema refetch
- Missing key behavior is safe (fallback)
- No crashes from malformed bundle payloads
- Diagnostics remain English-only (by design) and do not block UI

---

# Implementation checklist (copy into PR description)

- [ ] Decide key namespace (e.g. `customer.*`, `provider.*`, `form.error.*`)
- [ ] Add locale controller (user override + persistence)
- [ ] Add bundle loader (remote + LKG + bundled fallback)
- [ ] Add i18n resolver (`string | {key,fallback} | {i18n,...}`)
- [ ] Update top components to use resolver (tabs, primary actions, inputs)
- [ ] Convert form validation to error codes + localized messages
- [ ] Add backend bundle endpoint with `ETag` + budgets
- [ ] Add unit/widget tests for switching + resolver + validation
- [ ] Add translator workflow notes (source format, required keys, QA process)
