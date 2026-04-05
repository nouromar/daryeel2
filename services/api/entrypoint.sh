#!/usr/bin/env sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"

# Best-effort wait for Postgres.
python - <<'PY'
import os, time
import sqlalchemy as sa

db_url = os.environ["DATABASE_URL"]
for i in range(60):
    try:
        engine = sa.create_engine(db_url, pool_pre_ping=True)
        with engine.connect() as conn:
            conn.execute(sa.text("SELECT 1"))
        break
    except Exception:
        time.sleep(1)
else:
    raise SystemExit("Postgres not reachable")
PY

# Run migrations (safe to run on every start).
alembic upgrade head

exec uvicorn app.main:app --host 0.0.0.0 --port 8010
