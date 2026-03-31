# Daryeel2

This directory contains the next-generation Daryeel platform work.

Current starting structure:
- `docs/` — architecture, contracts, runtime, theming, and project-structure docs
- `apps/` — product shells
- `services/` — backend services
- `packages/` — shared contracts and runtime libraries

Key docs:
- `docs/diagnostics-and-telemetry.md` — canonical diagnostics/logs/telemetry spec
- `docs/config-service.md` — mobile-first config/bootstrap design (near-zero overhead)
- `docs/caching-framework.md` — shared caching contract (ETag/LKG + Redis)
- `docs/framework-completion-plan.md` — end-to-end roadmap to finish the schema-driven framework
- `docs/framework-completion-checklist.md` — executable checklist (milestones → tasks)

## Local development (Docker)

Run the runtime delivery backend (`schema-service`) on port `8011`:

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

Initial build order:
1. contract packages
2. schema runtime core (Dart + TypeScript parity)
3. Flutter runtime adapter + schema renderer foundation
4. schema-service
5. minimal API slice
6. first customer-app vertical slice
