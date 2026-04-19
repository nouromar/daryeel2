# Theming (Canonical Reference)

This document is the single, stable reference for **how theming works** in Daryeel2 and **where to change what**.

It intentionally avoids duplicating token lists or large theme catalogs. The source of truth for theme documents and token models lives in:
- `packages/theme-contracts/`
- `packages/flutter_themes/`
- `packages/flutter_daryeel_client_app/` (theme loading ladder)

---

## Quick start (for schema authors)

### Selecting a theme

Screens pick a theme via:
- `themeId` (required)
- `themeMode` (optional; typically `light` or `dark`)

Example:

```json
{
  "themeId": "customer-default",
  "themeMode": "light"
}
```

Guidance:
- Prefer stable, product-scoped theme ids (e.g. `customer-default`) over per-screen theme ids.
- If `themeMode` is omitted, the runtime may choose a default mode (from bootstrap/config/app defaults).

---

## Source of truth (implementation entry points)

These are the concrete code locations that define how theming behaves at runtime:

- Theme resolution + inheritance + token mapping:
  - `packages/flutter_themes/lib/src/theme_resolver.dart`
  - `packages/flutter_themes/lib/src/theme_document.dart`

- Theme loading ladder (remote fetch + pinning + fallback):
  - `packages/flutter_daryeel_client_app/lib/src/schema/theme_loader.dart`
  - `packages/flutter_daryeel_client_app/lib/src/schema/pinned_theme_store.dart`
  - `packages/flutter_daryeel_client_app/lib/src/runtime/daryeel_runtime_controller.dart`

- App-provided local fallback themes:
  - Customer app: `apps/customer-app/lib/src/ui/customer_theme.dart`
  - Provider app: `apps/provider-app/lib/src/ui/provider_theme.dart`

---

## Where theme documents live

### Theme contracts and documents

Theme ids, modes, token taxonomy, and theme documents live in:
- `packages/theme-contracts/`
  - `catalog.json`
  - `themes/*.json`

If you are adding or changing a theme document, start here.

---

## Runtime behavior (high-level)

At runtime, a screen resolves a theme using a ladder that aims to be resilient and rollback-safe:

1) Screen declares `themeId` (and optional `themeMode`).
2) The client attempts to load the theme document (remote when enabled/available).
3) The runtime may pin a last-known-good immutable theme docId (theme pinning is controlled by runtime config).
4) If remote theme loading fails or is disabled, the app’s **local theme resolver** provides a fallback `ThemeData`.

Notes:
- Schema/theme HTTP responses are cached where possible (ETag/304) by the shared client shell.
- The client shell emits diagnostics and exposes debug-only inspection UI to make theme resolution visible.

---

## Common tasks

### Add a new theme id

1) Add the theme document under `packages/theme-contracts/themes/`.
2) Register it in `packages/theme-contracts/catalog.json`.
3) Ensure schema-service loads/serves the updated theme catalog (server-side).
4) Optionally update app-local fallback mapping in `apps/*/lib/src/ui/*_theme.dart` so the app has a reasonable local default.

### Change the default theme when schemas omit it

Defaults are determined by a combination of:
- Bootstrap/config defaults (if present)
- App runtime config defaults (`defaultThemeId`, `defaultThemeMode`)

Start by checking:
- `apps/*/lib/src/app/*_app.dart`
- `packages/flutter_daryeel_client_app/lib/src/config/daryeel_client_config.dart`

---

## Debugging theming

Debug-only tools exist in the shared client shell:
- The runtime inspector screen shows the resolved theme id/mode and (when remote) theme docId/source.
- In debug builds, long-pressing the app bar title opens the inspector.

If a screen looks “unstyled”:
- Confirm the schema has the expected `themeId`.
- Check whether the theme loaded remotely vs fell back to local.
- Use the runtime inspector to confirm which theme document was resolved.
