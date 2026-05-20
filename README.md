# argo-local-stack

Local development infrastructure for Marlow backend services. Spins up Postgres, Kafka, and the Argo DB migration runner so you can run services like Phoebe and Alcyone locally without fiddling with external environments.

# Quick setup for local development

Run docker compose up to start the infrastructure stack

``` bash
docker compose up -d 
```

### how run a argodb branch

By default the argo-db-app container clones the `master` branch of the `argo.db` repo and runs migrations from there. To point it at a different branch (e.g., for testing a feature branch with new migrations), set the `ARGO_DB_BRANCH` environment variable:
The variable can be set in the `.env` file or passed inline when starting the container.

```bash
ARGO_DB_BRANCH=feature/your-branch docker compose up -d --force-recreate --no-deps argo-db-app
```

### how to add a kafka topic

To add a new Kafka topic, set the `KAFKA_TOPICS` environment variable in your `.env` file to include the new topic name.



### Core infrastructure services and ports

| Service | Container | Port | What it does |
|---|---|---|---|
| **PostgreSQL** | `poseidon-postgres` | `5432` | Main database — used by all backend services |
| **pgAdmin** | `poseidon-pgadmin` | `58080` | Web UI for poking around the database |
| **Zookeeper** | `poseidon-zookeeper` | `2181` | Kafka's coordination layer |
| **Kafka** | `poseidon-kafka` | `9092` | Message broker for audit logs, notifications, etc. |
| **Kafka UI** | `poseidon-kafka-ui` | `58081` | Web UI for inspecting topics and messages |
| **Argo DB** | `argo-db-app` | — | Clones `argo.db` and runs SBT migrations against Postgres |

### Phoebe services (profile: `phoebe`)

| Service | Container | Port | Module |
|---|---|---|---|
| **Crewing** | `poseidon-phoebe-crewing` | `8090` | crewing |
| **Training** | `poseidon-phoebe-training` | `8091` | training |
| **Document** | `poseidon-phoebe-document` | `8092` | document |
| **Task Management** | `poseidon-phoebe-task-management` | `8093` | task-management |
| **Audit Logs** | `poseidon-phoebe-audit-logs` | `8094` | audit-logs |
| **User Management** | `poseidon-phoebe-user-management` | `8095` | user-management |
| **Imports** | `poseidon-phoebe-imports` | `8096` | imports |
| **Insurance** | `poseidon-phoebe-insurance` | `8097` | insurance |
| **Integration Client** | `poseidon-phoebe-integration-client` | `8098` | integration-client |

## Getting started

```bash
# bring everything up
docker compose up -d

# or if you're on podman
podman-compose up -d
```

pgAdmin will be available at [http://localhost:58080](http://localhost:58080) (login: `admin@local.dev` / `admin`).
Kafka UI at [http://localhost:58081](http://localhost:58081).


## Fine tune this stack

### Running individual services

You don't have to bring up the entire stack every time. Use `docker compose up -d` with specific service names to start only what you need.

### Database only (Postgres + pgAdmin)

```bash
docker compose up -d postgres pgadmin
```

### Kafka only (Zookeeper + Kafka + Kafka UI)

```bash
docker compose up -d zookeeper kafka kafka-ui
```

### Database + migrations (Postgres + Argo DB)

```bash
docker compose up -d postgres argo-db-app
```

> `argo-db-app` depends on `postgres` being healthy, so Postgres will start automatically even if you only specify `argo-db-app`:
> ```bash
> docker compose up -d argo-db-app
> ```

### Alcyone API (with all its dependencies)

```bash
docker compose up -d alcyone-api
```

This automatically starts `postgres`, `kafka`, `zookeeper`, and `argo-db-app` because of the declared `depends_on` chain.

### Phoebe services

Phoebe services are behind the `phoebe` profile and won't start unless you explicitly enable it.

#### Building images

Each Phoebe module has its own Dockerfile. Build from the phoebe repo root:

```bash
cd /path/to/backends/phoebe

# Build a single module (e.g., crewing)
mvn package -pl crewing -am -DskipTests
cd crewing && docker build --build-arg DOCKER_TAG=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout) -t phoebe-crewing:latest .

# Or build all modules at once
mvn package -DskipTests
for module in crewing training document task-management audit-logs user-management imports insurance integration-client; do
  VERSION=$(cd "$module" && mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
  docker build --build-arg DOCKER_TAG="$VERSION" -t "phoebe-$module:latest" "$module"
done
```

#### Running

```bash
# All phoebe services (infra starts automatically via depends_on)
docker compose --profile phoebe up -d

# Just one service
docker compose --profile phoebe up -d phoebe-crewing

# A few services
docker compose --profile phoebe up -d phoebe-crewing phoebe-task-management phoebe-audit-logs
```

Each service has its own env file (`phoebe-<module>.env`). Edit those to configure DB schemas, Kafka topics, SSO endpoints, etc.

### Jaeger (tracing)

Jaeger is behind a profile and won't start unless you explicitly enable it:

```bash
docker compose --profile tracing up -d jaeger
```

### Mix and match

Combine any services you need:

```bash
# Postgres + Kafka (no UI tools, no migrations)
docker compose up -d postgres zookeeper kafka

# Everything except Alcyone
docker compose up -d postgres pgadmin zookeeper kafka kafka-ui argo-db-app
```

### Restart a single service without touching others

```bash
docker compose up -d --force-recreate --no-deps <service>
```

### Stop a single service

```bash
docker compose stop <service>
```

### View logs for a specific service

```bash
docker compose logs -f <service>
```

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

The actual application code lives in `backends/`. Alcyone can be run via `docker compose up -d alcyone-api`. Phoebe services can be run via `docker compose --profile phoebe up -d` after building their images locally.

| Directory | What it is | How to run |
|---|---|---|
| `alcyone/` | Alcyone API — Spring Boot service (surveys/debriefings) | `docker compose up -d alcyone-api` |
| `phoebe/` | Phoebe — multi-module monolith (crewing, auth, audit-logs, training, documents, etc.) | `docker compose --profile phoebe up -d` |

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
