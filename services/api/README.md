# api

Core business backend service for Daryeel2.

Responsibilities include requests, providers, dispatch orchestration, payments orchestration, ratings, and events.

This service is currently a minimal FastAPI skeleton wired for Docker local dev
with Postgres, Redis, and Alembic migrations.

## Local development (Docker)

From the repo root:

```bash
cd Daryeel2
docker compose up --build
curl http://localhost:8010/health
```

## Migrations (Alembic)

Migrations run automatically on container startup.

To run them manually:

```bash
docker compose run --rm api alembic upgrade head
```
