# provider-app

Provider-facing Daryeel2 Flutter client.

This app is intentionally a thin wrapper around the shared client shell in `packages/flutter_daryeel_client_app`. Provider-specific configuration lives under `lib/src/` (fallback schema/fragments, theme resolver, registry, and schema compatibility rules).

## Run

- `flutter pub get`
- `flutter run`

## Tests

- `flutter test`
