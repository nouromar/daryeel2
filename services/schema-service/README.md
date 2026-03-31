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

Config and theme delivery were merged into this service to reduce moving pieces early on.

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
```

Enable Redis-backed caching (optional):

```bash
cd Daryeel2
SCHEMA_SERVICE_REDIS_URL=redis://redis:6379/0 docker compose --profile redis up --build
```

Note: Redis-backed caching requires the `redis` Python package (included in
`services/schema-service/requirements.txt`).
