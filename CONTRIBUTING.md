# Contributing

Thanks for your interest in contributing.

## Before you start

- Keep changes focused and incremental.
- Prefer adding tests when changing behavior.
- Avoid committing secrets (see `.env.example`; do not commit `.env`).

## Local development

### Backend (schema-service)

```bash
cd services/schema-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pytest
```

### TypeScript runtime

```bash
cd packages/schema_runtime_ts
npm ci
npm test
```

### Flutter/Dart

Run package tests from within each package/app folder:

```bash
cd apps/customer-app
flutter pub get
flutter test
```

## Pull requests

- Use a clear title and summary.
- Link issues where applicable.
- Ensure CI is green.
