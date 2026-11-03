# MatterHub API

FastAPI service that tracks legal matters through their lifecycle (open, on hold,
closed) with an append-only audit trail and a retention review job.

One image, three entrypoints:

| Command | Runs as | Purpose |
|---|---|---|
| `matterhub serve` | Deployment | HTTP API on port 8000 |
| `matterhub migrate` | Helm pre-install/pre-upgrade hook Job | Alembic migrations |
| `matterhub retention [--dry-run]` | CronJob (daily) | Flag closed matters past their retention date |

## Develop

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt -e .
pytest --cov                 # unit + API tests (SQLite in memory)
ruff check . && ruff format --check . && mypy
MATTERHUB_AUTH_MODE=disabled matterhub migrate && MATTERHUB_AUTH_MODE=disabled matterhub serve
```

Open http://localhost:8000/docs for the OpenAPI UI (hidden in production).

## Endpoints

| Method | Path | Role |
|---|---|---|
| GET | `/healthz` | public (liveness) |
| GET | `/readyz` | public (readiness: checks the database) |
| GET | `/version` | public (version and git SHA, used by the smoke test) |
| GET | `/metrics` | public in-cluster only (Prometheus) |
| GET | `/api/v1/matters` | `Matters.Read` |
| POST | `/api/v1/matters` | `Matters.Write` |
| GET | `/api/v1/matters/{id}` | `Matters.Read` |
| PATCH | `/api/v1/matters/{id}` | `Matters.Write` |
| GET | `/api/v1/matters/{id}/audit` | `Matters.Read` |

## Configuration

All settings are environment variables prefixed with `MATTERHUB_` (see `src/matterhub/config.py`).

| Variable | Default | Notes |
|---|---|---|
| `MATTERHUB_ENVIRONMENT` | `local` | `local`, `test`, `dev`, `staging`, `prod` |
| `MATTERHUB_AUTH_MODE` | `entra` | `disabled` is refused in staging/prod |
| `MATTERHUB_ENTRA_TENANT_ID` / `MATTERHUB_ENTRA_AUDIENCE` | none | Entra ID app registration |
| `MATTERHUB_DATABASE_HOST` / `_NAME` / `_USER` / `_PASSWORD` | none | password comes from Key Vault |
| `MATTERHUB_RETENTION_YEARS` | `7` | years after closure before review |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | none | enables OpenTelemetry export |

## Dependencies

`requirements.txt` is compiled from `requirements.in` with hashes, and the Dockerfile
installs it with `--require-hashes`, so a tampered package fails the build.

```bash
pip install pip-tools
pip-compile --generate-hashes --strip-extras -o requirements.txt requirements.in
pip-compile --strip-extras -o requirements-dev.txt requirements-dev.in
```
