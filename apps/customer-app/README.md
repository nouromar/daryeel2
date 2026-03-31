# customer-app

Customer-facing Daryeel2 Flutter shell for the schema-driven runtime.

Current scope:
- renders the bundled `customer_home` schema from the shared runtime packages
- can fetch the same screen from `schema-service` when `SCHEMA_BASE_URL` is provided
- falls back safely to the bundled schema when remote loading fails

Run locally:

```bash
cd Daryeel2/apps/customer-app
flutter pub get
flutter run
```

Run against the schema service:

```bash
cd Daryeel2/apps/customer-app
flutter run --dart-define=SCHEMA_BASE_URL=http://127.0.0.1:8000
```

The first vertical slice intentionally stays narrow: compatibility checks, schema loading, component registry mapping, theme resolution, and safe fallback behavior.
