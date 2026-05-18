# marlow-dev-stack

Orchestrates the full local Marlow development stack: Postgres + Kafka + Zookeeper + pgAdmin + Kafka-UI + Jaeger + argo.db migrations + **phoebe-crewing** + **alcyone-api** (Spring Boot, in containers) — paired with **themis** (Next.js) running on the host via `yarn dev`.

A colleague's fork enriched the upstream `thariq-mj-shah/marlow-dev-stack` with multi-stage Dockerfiles for the Java services, HTTPS-based migration cloning (for machines where SSH is locked), placeholder users + `argodb` DB to satisfy stg's afterMigrate GRANTs, and a 1-click bootstrap script.

---

## 1-click quickstart

```bash
# clone this repo into a workspace dir (e.g. C:\marlow_workspace), then:
cd marlow-dev-stack
./bootstrap.sh
```

`bootstrap.sh` does everything: verifies prereqs, clones sibling repos, scaffolds `.env.local` files from templates, runs migrations, builds and starts the BE services, and launches themis on `:3001`.

When it finishes you'll see:

```
  Themis    → http://localhost:3001        (FE — yarn dev)
  Crewing   → http://localhost:8081/health (BE)
  Alcyone   → http://localhost:8082/health (BE)
  pgAdmin   → http://localhost:58080       admin@local.dev / admin
  Kafka-UI  → http://localhost:58081
  Jaeger    → http://localhost:16686
  Postgres  → localhost:5433               postgres/postgres
```

Flags:
- `--skip-themis` — bring up only the BE stack (use if you're running themis from your IDE)
- `--rebuild` — force-rebuild crewing/alcyone images (use after pulling new BE code)
- `--reset-kafka` — wipe kafka+zookeeper volumes (use on the known `NodeExistsException` cold-start footgun — see Troubleshooting)

---

## One-time setup (before first `./bootstrap.sh`)

The script enforces these; it'll bail with a clear message if any are missing.

### 1. Tools

| Tool | Why | Notes |
|---|---|---|
| Docker Desktop | infra + BE services | BuildKit must be enabled (default in modern Docker) |
| Node 22.13+ | themis dev server | If you have 22.12, the script passes `--ignore-engines` on yarn install |
| yarn 1.x | themis install | `corepack enable` or `npm i -g yarn@1` |
| gh CLI | HTTPS clones via your GitHub token | `gh auth login` |
| Maven (optional) | host-side BE builds | The Docker build uses a containerised maven, so host maven is not strictly required |

### 2. Nexus credentials (Maven + npm both need them)

`~/.m2/settings.xml` — for the BE Maven build to pull internal `ananke` artifacts:

```xml
<settings>
  <servers>
    <server>
      <id>nexus</id>
      <username>your.nexus.user</username>
      <password>your.nexus.password</password>
    </server>
  </servers>
</settings>
```

> **Windows gotcha:** File Explorer's "Hide extensions" turns the file into `settings.xml.txt` silently. Make extensions visible and rename if needed.

OS env vars for npm/yarn:

```powershell
# PowerShell (Windows user scope — applies to new shells)
[Environment]::SetEnvironmentVariable('NEXUS_TOKEN','<npm token from Nexus UI → User Token>','User')
[Environment]::SetEnvironmentVariable('NEXUS_USER','<nexus username>','User')
[Environment]::SetEnvironmentVariable('NEXUS_PASS','<nexus password>','User')
```

```bash
# Git Bash — append to ~/.bashrc
export NEXUS_TOKEN='NpmToken.<uuid>'
export NEXUS_USER='your.nexus.user'
export NEXUS_PASS='your.nexus.password'
```

Reopen your terminal so the env vars propagate.

### 3. `.env.local` files

`bootstrap.sh` copies `.env.local.example` → `.env.local` automatically. After the first run you must edit two files and fill the **SECRETS** sections from your team vault:

- `marlow-dev-stack/.env.local` — Java service secrets (`SURVEYS_INTERNAL_SA`, `migration_debriefing`, `CREWING_SSO_SA_KEY`, `CREWING_INTERNAL_API_KEY`, etc.)
- `themis/.env.local` — FE secrets (`KEYCLOAK_CLIENT_SECRET`, `NEXTAUTH_SECRET`, `NEXT_PUBLIC_MUI_LICENSE_KEY`, `NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN`, etc.)

Without those values the stack still boots, but the FE error-boundary trips on expired MUI license, login fails without Keycloak secret, and `/debriefing` 500s without `SURVEYS_INTERNAL_SA`.

---

## What's in the stack

| Service | Container / Process | Host port | Source |
|---|---|---|---|
| Postgres 17 | `poseidon-postgres` | `5433` → 5432 | Docker image |
| pgAdmin | `poseidon-pgadmin` | `58080` | Docker image |
| Zookeeper | `poseidon-zookeeper` | `2181` | confluentinc/cp-zookeeper:7.5.0 |
| Kafka | `poseidon-kafka` | `9092` | confluentinc/cp-kafka:7.5.0 |
| Kafka-UI | `poseidon-kafka-ui` | `58081` | provectuslabs/kafka-ui |
| Jaeger | `phoebe-jaeger` | `16686`/`14268` | jaegertracing/all-in-one:1.57 |
| Argo migrations | `argo-db-app` | — | bind-mounts `../argo.db`, runs sbt migrate against local Postgres |
| **Phoebe (crewing)** | `phoebe-crewing` | `8081` → 8080 | builds from `../phoebe/crewing` (multi-stage maven) |
| **Alcyone (api)** | `alcyone-api` | `8082` → 8081 | builds from `../alcyone/api` (multi-stage maven) |
| **Themis** | `node` (host process) | `3001` | runs from `../themis` via `yarn dev` |

The fork's `docker-compose.yaml` includes the BE services + Jaeger; an init script (`docker/postgres-init/01-argodb-users.sql`) pre-creates the users + empty `argodb` database that argo.db's `stg` afterMigrate callback requires.

---

## Directory expectations

The compose file references **sibling directories** of `marlow-dev-stack`:

```
<workspace>/
├── marlow-dev-stack/      ← this repo
├── phoebe/                ← BE monorepo (multi-module, includes crewing/)
├── alcyone/               ← Surveys/Debriefing BE
├── themis/                ← Crewing FE (Next.js)
├── argo.db/               ← Flyway migrations (bind-mounted into argo-db-app)
├── ananke/                ← shared Spring-Boot libs (optional; used when iterating on them locally)
└── instructions/          ← canonical knowledge base + LOCAL_STACK.md deep dive
```

`bootstrap.sh` clones any missing ones via `gh repo clone Marlow-Navigation/<name>`.

---

## Day-to-day operations

### Iterate on a single BE module

After editing `phoebe/<module>/...` or `alcyone/api/...`:

```bash
cd marlow-dev-stack
DOCKER_BUILDKIT=1 docker compose --env-file .env.local build <service>
docker compose --env-file .env.local up -d --force-recreate --no-deps <service>
curl -sS http://localhost:<port>/health
```

`<service>` = `crewing` or `alcyone`. Use `--no-deps` — recreating kafka alongside triggers the `NodeExistsException` cold-start bug (see Troubleshooting).

### Flip a backend between local and staging from the FE

Edit `themis/.env.local`:

| Path prefix | Env var | Local value | Staging value |
|---|---|---|---|
| `/be-api` | `SERVER_API_BASE_URL` | `http://localhost:8081` | `https://phoebe-stg.marecrew.com` |
| `/kh-api` | `KH_API_BASE_URL` | `http://localhost:8081` | `https://phoebe-stg.marecrew.com` |
| `/aly-api` (debriefing) | `DEBRIEFING_API_BASE_URL` | `http://localhost:8082` | `https://alcyone-api-stg.marecrew.com` |

Restart themis (`yarn dev`) to pick up changes.

### Stop everything

```bash
cd marlow-dev-stack
docker compose --env-file .env.local stop
# plus kill themis on host:
# (Git Bash): netstat -ano | grep 3001 → taskkill /F /PID <pid>
# (PowerShell): Get-NetTCPConnection -LocalPort 3001 -State Listen | %{ Stop-Process -Id $_.OwningProcess -Force }
```

---

## Troubleshooting

The biggest pitfalls — symptom → fix:

| Symptom | Fix |
|---|---|
| `Permission denied (publickey)` on git pull/clone | SSH key is locked. The script and docs use HTTPS via `gh` — make sure you ran `gh auth login`. |
| Maven build: `Illegal character ... ${env.NEXUS_REPO}/...` | `NEXUS_REPO` not propagated into the build stage — the Dockerfile sets it via `ARG`. Rebuild with the latest Dockerfile. |
| Crewing crashes on startup with `ConflictingBeanDefinitionException: authUtils` | Stale `phoebe/auth/target/classes` from a pre-migration era leaks into the fat jar. The Dockerfile uses `clean package` + a `.dockerignore` excluding `**/target/`; both are load-bearing. |
| Argo migrations fail with `Connection refused 0.0.0.0:5432` | Argo's `dev` profile hardcodes `0.0.0.0`. Our compose uses `--environment stg` (reads DB_URL from env). The postgres-init script in `docker/postgres-init/` creates the placeholder roles + `argodb` DB so the `stg` afterMigrate GRANTs succeed. |
| Java service: `Couldn't parse remote JWK set: Missing required "keys" member` | `SSO_*_ISSUER_URL` was pointed at a realm root. Must be `.../protocol/openid-connect/certs`. The example .env has the correct URLs. |
| Alcyone debriefing endpoints 500 with downstream 401 from ps-auth | `SURVEYS_INTERNAL_SA` empty. Fill it from vault. |
| Themis: every page shows "Something went wrong!" with a single MUI X expired-license console error | `NEXT_PUBLIC_MUI_LICENSE_KEY` expired — DataGridPro throws at render. Get a fresh key from your MUI Pro account. |
| Themis: NextAuth bounces through `/api/auth/error` with `Jest worker encountered 2 child process exceptions` | Turbopack crashes on `tailwind.config.mjs` (CJS body in an ESM package). The script starts themis with `TURBOPACK=0`. |
| Kafka container exits seconds after `--force-recreate` with `NodeExistsException: KeeperErrorCode = NodeExists at registerBroker` | Stale ephemeral broker znode in Zookeeper from the previous kafka container. Run `./bootstrap.sh --reset-kafka` (wipes both kafka+zookeeper volumes and restarts together), then `docker restart alcyone-api` to refresh DNS. |
| Alcyone `/health` returns DOWN with `Couldn't resolve server kafka:29092` | Started before kafka was ready — `docker restart alcyone-api`. The bootstrap script auto-bounces it once. |
| Java service build fails on a test compile error after switching branches | `-DskipTests` only skips test execution; compilation still runs. The Dockerfiles use `-Dmaven.test.skip=true` (skips both). If a branch has diverged tests, the build still succeeds. |
| `POST /v1/inbox/session 404` in themis logs | Jira helpdesk inbox widget endpoint, harmless, ignore. |

Full long-form guide with all gotchas + history: see `../instructions/guides/local-dev/LOCAL_STACK.md`.

---

## Skills (Claude Code)

Two project-scoped Claude Code skills live in the workspace at `.claude/skills/`:

- `/run-argo` — boot the whole stack (equivalent to `./bootstrap.sh`)
- `/build-deploy <repo>` — rebuild + redeploy a single service (crewing / alcyone / themis)

---

## Differences from upstream `thariq-mj-shah/marlow-dev-stack`

| What | Why |
|---|---|
| Added `crewing` + `alcyone` services with multi-stage Maven Dockerfiles | Run the BE entirely in containers, no host JDK required |
| Added `jaeger` for local tracing | `phoebe/crewing` is wired to a Jaeger collector at `JAEGER_HOST:JAEGER_PORT`; without this the BE logs a tracing init error |
| Bind-mount `../argo.db` instead of cloning inside the container | SSH-locked workstations can't clone via `git@github.com` |
| `sbt -batch ... migrate` instead of `printf '...' | sbt` | Upstream's tty + piped-stdin pattern got stuck at the SBT interactive prompt |
| `--environment stg` (not `dev`) + a postgres-init script | Argo's `dev` profile has a hardcoded `0.0.0.0` DB URL; `stg` reads `DB_URL` from env but its afterMigrate callback GRANTs to users that don't exist on a fresh DB — the init script creates them |
| `-Dmaven.test.skip=true` in both Dockerfiles | `-DskipTests` still compiles tests; diverged feature-branch tests would block packaging |
| `bootstrap.sh` | 1-click setup that handles every gotcha above without you needing to know them |

Once upstream PR [#478](https://github.com/Marlow-Navigation/argo.db/pull/478) merges in `argo.db`, the `--environment stg` workaround can be reverted to `dev`.
