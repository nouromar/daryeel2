# Codebase improvement checklist

Tracked improvements for the `packages/` codebase. We will implement these one at a time.

## Checklist

- [x] Add core component registrar
  - Goal: reduce app-level footguns by providing a single helper to register the standard schema components (layout + common widgets) from `flutter_components`.
  - Done:
    - Key files:
      - `packages/flutter_components/lib/src/schema_components/core_schema_components.dart`
      - `packages/flutter_components/lib/flutter_components.dart`
      - `apps/customer-app/lib/src/ui/customer_component_registry.dart`
    - Tests: `cd packages/flutter_components && flutter test`

- [x] Deduplicate schema component utils
  - Goal: consolidate repeated parsing/slot-building logic (`_asDouble`, slot rendering, visibility checks) used across schema components.
  - Done:
    - Key files:
      - `packages/flutter_components/lib/src/schema_components/schema_component_utils.dart`
      - (refactors) `packages/flutter_components/lib/src/schema_components/*`
    - Tests: `cd packages/flutter_components && flutter test`

- [x] Align action model contracts
  - Goal: eliminate drift between runtime-supported action types/fields and the schema contracts + schema-service models.
  - Done:
    - Key files:
      - `packages/schema-contracts/schemas/action-definition.schema.json`
      - `packages/schema_runtime_dart/lib/src/schema/schema_models.dart`
      - `packages/schema_runtime_dart/lib/src/schema/schema_parser.dart`
      - `packages/schema_runtime_ts/src/schema/schema_models.ts`
      - `packages/schema_runtime_ts/src/schema/schema_parser.ts`
      - `services/schema-service/app/schemas.py`
    - Tests:
      - `cd packages/flutter_runtime && flutter test`
      - `cd packages/flutter_components && flutter test`
      - `cd packages/schema_runtime_ts && npm test`
      - `cd services/schema-service && pytest`

- [x] Unify lint + SDK constraints
  - Goal: align Dart/Flutter SDK floors and lint packages across `packages/*` to reduce inconsistent analyzer behavior.
  - Done:
    - Key files:
      - `packages/*/pubspec.yaml` (SDK floors + lint dev deps)
      - `packages/*/analysis_options.yaml` (consistent lint includes)
      - `packages/schema_runtime_dart/lib/schema_runtime_dart.dart` (lint cleanup)
    - Checks:
      - `cd packages/flutter_runtime && flutter test`
      - `cd packages/flutter_schema_renderer && flutter test`
      - `cd packages/flutter_daryeel_client_app && flutter pub get`
      - `cd packages/schema_runtime_dart && dart analyze`

- [x] Tighten public barrel exports
  - Goal: shrink public API surface by curating `lib/*.dart` exports and keeping internals in `src/` non-exported unless needed.
  - Done:
    - Key files:
      - `packages/flutter_daryeel_client_app/lib/flutter_daryeel_client_app.dart`
      - (test-only internal imports) `apps/customer-app/test/*`
    - Notes: kept `LoadedScreen`/`ScreenLoadSource` public via `daryeel_runtime_view_model.dart` export because they appear in public callback signatures.
    - Tests: `cd apps/customer-app && flutter test`

- [x] ScreenTemplate spacing configurability
  - Goal: avoid hard-coded layout constants in shared widgets by making spacing/padding configurable (props or theme tokens).
  - Done:
    - Widget params (defaults preserved): `headerGap`, `bodyPadding`, `primaryScrollPadding`, `footerPadding`
    - Schema props (optional): `headerGap`, `bodyPadding`, `primaryScrollPadding`, `footerPadding`
    - Key files:
      - `packages/flutter_components/lib/src/widgets/screen_template_widget.dart`
      - `packages/flutter_components/lib/src/schema_components/screen_template_schema_component.dart`
      - `packages/flutter_components/test/screen_template_widget_test.dart`
    - Tests: `cd packages/flutter_components && flutter test`

- [x] TS runtime build artifacts cleanup
  - Goal: ensure `schema_runtime_ts` only publishes/uses build outputs intentionally; document and/or enforce build output hygiene.
  - Done:
    - Key files:
      - `packages/schema_runtime_ts/package.json` (add `clean`, run `clean` before `build`, narrow `files`)
      - `packages/schema_runtime_ts/README.md` (document `dist/` expectations)
    - Tests: `cd packages/schema_runtime_ts && npm test`

## Notes

- When starting an item, add a short “Plan” section under it.
- When done, add: links to key files touched, tests run, and any follow-ups.
