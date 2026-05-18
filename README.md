# argo-local-stack

Local development infrastructure for Marlow backend services. Spins up Postgres, Kafka, and the Argo DB migration runner so you can run services like Phoebe and Alcyone locally without fiddling with external environments.

## What's in the box

| Service | Container | Port | What it does |
|---|---|---|---|
| **PostgreSQL** | `poseidon-postgres` | `5432` | Main database — used by all backend services |
| **pgAdmin** | `poseidon-pgadmin` | `58080` | Web UI for poking around the database |
| **Zookeeper** | `poseidon-zookeeper` | `2181` | Kafka's coordination layer |
| **Kafka** | `poseidon-kafka` | `9092` | Message broker for audit logs, notifications, etc. |
| **Kafka UI** | `poseidon-kafka-ui` | `58081` | Web UI for inspecting topics and messages |
| **Argo DB** | `argo-db-app` | — | Clones `argo.db` and runs SBT migrations against Postgres |

## Getting started

```bash
# bring everything up
docker compose up -d

# or if you're on podman
podman-compose up -d
```

pgAdmin will be available at [http://localhost:58080](http://localhost:58080) (login: `admin@local.dev` / `admin`).
Kafka UI at [http://localhost:58081](http://localhost:58081).

## Environment variables

Core infra config lives in `.env` at the repo root. The defaults are sensible for local dev — you probably don't need to change anything unless you have port conflicts.

For `alcyone-api`, compose also loads `alcyone.env` via `env_file`. Precedence is: explicit `environment` values in `docker-compose.yaml` > `alcyone.env` > `.env`.

### Core database

| Variable | Default | Notes |
|---|---|---|
| `POSTGRES_DB` | `postgres` | Database name |
| `POSTGRES_USER` | `postgres` | |
| `POSTGRES_PASSWORD` | `postgres` | |
| `POSTGRES_PORT` | `5432` | Host port mapping |

### pgAdmin

| Variable | Default |
|---|---|
| `PGADMIN_DEFAULT_EMAIL` | `admin@local.dev` |
| `PGADMIN_DEFAULT_PASSWORD` | `admin` |
| `PGADMIN_PORT` | `58080` |

### Kafka

| Variable | Default | Notes |
|---|---|---|
| `KAFKA_PORT` | `9092` | Host-facing broker port |
| `KAFKA_UI_PORT` | `58081` | Kafka UI web port |
| `KAFKA_TOPICS` | `crewing-audit-logs-topic-dev,...` | Comma-separated list of topics to auto-create on startup |
| `KAFKA_TOPIC_PARTITIONS` | `1` | Partition count for auto-created topics |
| `KAFKA_TOPIC_REPLICATION_FACTOR` | `1` | Replication factor (keep at 1 for single-node local) |

The Kafka listener config (`KAFKA_LISTENERS`, `KAFKA_ADVERTISED_LISTENERS`, etc.) is set up so that containers talk to Kafka on `kafka:29092` and your host machine connects via `localhost:9092`. Unless you're doing something unusual, leave these alone.

### Argo DB

| Variable | Default | Notes |
|---|---|---|
| `ARGO_DB_BRANCH` | `master` | Branch of `argo.db` to clone and run migrations from |
| `DB_URL` | `jdbc:postgresql://postgres:5432/postgres` | JDBC URL for the migration target |
| `DB_USERNAME` | `postgres` | |
| `DB_PASSWORD` | `postgres` | |

## The `ARGO_DB_BRANCH` variable

This one matters. The `argo-db-app` container clones the [argo.db](https://github.com/Marlow-Navigation/argo.db) repo on startup and runs SBT migrations against your local Postgres. The `ARGO_DB_BRANCH` variable controls which branch gets checked out.

By default it points at `master`, but you'll want to change this when:

- **You're working on a feature that requires schema changes** — point it at the feature branch in `argo.db` that has your migrations, so your local DB matches what your code expects.
- **You need to test someone else's migration** — just set the branch to theirs and restart the container.
- **Something broke** — if your local DB is in a weird state, you can nuke the `argo-db-data` volume and re-run with the correct branch to get a clean migration.

To change it, either edit `.env`:

```
ARGO_DB_BRANCH=feature/my-schema-change
```

Or pass it inline:

```bash
ARGO_DB_BRANCH=feature/my-schema-change docker compose up -d argo-db-app
```

To re-run migrations from scratch:

```bash
docker compose down argo-db-app
docker volume rm projects_argo-db-data   # or whatever your volume prefix is
docker compose up -d argo-db-app
```

> **Note:** The container mounts your `~/.ssh` directory (read-only) so it can clone private repos over SSH. Make sure your SSH keys have access to the `argo.db` repo.

## Backend services

The actual application code lives in `backends/`. These aren't managed by this compose file — you run them from your IDE or command line as usual. This repo just provides the infrastructure they depend on.

| Directory | What it is |
|---|---|
| `alcyone/` | Alcyone API — Spring Boot service (surveys/debriefings) |
| `phoebe/` | Phoebe — multi-module monolith (crewing, auth, audit-logs, training, documents, etc.) |

## Troubleshooting

**Port conflict:** Change the port in `.env` and restart. Most ports have a corresponding `_PORT` variable.

**Kafka topics not created:** The Kafka container has a startup script that waits for the broker to be ready before creating topics. Check the container logs if topics are missing — it might just need a bit more time.

**Argo DB migration failed:** Check if the branch exists, if your SSH keys are mounted correctly, and if Postgres is actually up. The `argo-db-app` container depends on `postgres` but doesn't do a health check, so there's a small race condition on first boot.

**Recreating a single service without pulling deps along:**
```bash
docker compose up -d --force-recreate --no-deps <service>
```

**Strip and recreate**

```bash
podman-compose down -v --remove-orphans && podman-compose pull && podman-compose up -d
```
