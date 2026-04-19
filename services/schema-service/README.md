# schema-service (unified runtime service)

Unified runtime delivery backend service for Daryeel2.

Current scope (framework phase):
- `GET /health`
- schema delivery:
	- `GET /schemas/bootstrap`
	- `GET /schemas/screens/{screen_id}`
	- `GET /schemas/fragments/{fragment_id}`
- product bootstrap config:
	- `GET /config/bootstrap?product=customer_app`
- theme delivery:
	- `GET /themes/catalog`
	- `GET /themes/{theme_id}/{theme_mode}`

Config and theme delivery were merged into this service to reduce moving pieces early on. In Docker, this service is also the config-service endpoint exposed on port `8011`.

## Local development (pyenv)

This repo pins Python via `.python-version`.

Create a venv and run tests:

```bash
cd Daryeel2/services/schema-service
pyenv exec python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m pytest -q
```

Run the service:

```bash
cd Daryeel2/services/schema-service
source .venv/bin/activate
uvicorn app.main:app --reload --port 8011
```

## Schema validation (A2)

Validate all schema-contract examples (JSON Schema + component contract lint + ref checks):

```bash
cd Daryeel2/services/schema-service
source .venv/bin/activate
python -m app.validate_all
```

## Local development (Docker)

Run via Daryeel2 compose (from the repo root):

```bash
cd Daryeel2
docker compose up --build
curl http://localhost:8011/health
curl "http://localhost:8011/config/bootstrap?product=customer_app"
```

The compose file already wires Redis for this service. To override the advertised public runtime/config URL:

```bash
cd Daryeel2
SCHEMA_SERVICE_PUBLIC_BASE_URL=https://runtime.example.com docker compose up --build
```

Note: Redis-backed caching requires the `redis` Python package (included in
`services/schema-service/requirements.txt`).

## Docker dev workflow: making edits take effect

When you edit files that the frontend “owns” but the backend serves/validates (schemas/contracts/themes), the schema-service must re-read the updated files and/or clear caches.

### What updates without rebuild

In the default Docker compose setup, schema-service runs with bind-mounted JSON inputs so you can iterate without rebuilding the image:

- App schemas: `apps/customer-app/schemas/**`
- App contracts: `apps/customer-app/contracts/**`
- Shared contracts/themes/schema contracts: `packages/{component-contracts,theme-contracts,schema-contracts}/**`

### After editing JSON (schemas/contracts/themes)

1) Trigger a dev reload (reloads schema registry and clears cache backend, including Redis when configured):

```bash
curl -sS -X POST http://localhost:8011/dev/reload | cat
```

2) Re-fetch the affected endpoint to confirm the change is served:

```bash
curl -sS http://localhost:8011/schemas/screens/<screen_id> | head
curl -sS "http://localhost:8011/contracts/components?product=customer_app" | head
curl -sS "http://localhost:8011/contracts/actions?product=customer_app" | head
curl -sS http://localhost:8011/themes/catalog | head
```

Why: schemas are loaded into an in-memory registry, and contract/theme endpoints are cached (TTL) and may be Redis-backed; `/dev/reload` clears those caches.

### After editing schema-service Python code

The container does not run with `uvicorn --reload`, and service code is built into the image.
Rebuild + restart the service:

```bash
cd Daryeel2
docker compose up -d --build schema-service
```

If your change affects served payloads that are cached, also run:

```bash
curl -sS -X POST http://localhost:8011/dev/reload | cat
```
