#!/usr/bin/env bash
# Marlow dev stack — 1-click bootstrap.
#
# What this does:
#   1. Verifies prereqs (Docker daemon, gh CLI auth, ~/.m2/settings.xml, NEXUS_TOKEN, node/yarn)
#   2. Clones sibling repos (phoebe, alcyone, themis, argo.db, instructions) if missing
#   3. Copies .env.local.example -> .env.local and themis.env.local.example -> ../themis/.env.local if missing
#   4. Boots the full stack: infra -> argo migrations -> crewing -> alcyone
#   5. Optionally starts themis (yarn dev) on the host
#   6. Health-checks everything
#
# Idempotent — safe to re-run. First run takes ~5 min (image pulls + maven downloads).
# Run from this repo's root: ./bootstrap.sh
#
# Flags:
#   --skip-themis        don't start themis (just the BE stack)
#   --rebuild            force-rebuild crewing + alcyone images before starting
#   --reset-kafka        nuke kafka+zookeeper volumes before starting (use if NodeExistsException)
#
# See `instructions/guides/local-dev/LOCAL_STACK.md` for the deep dive on every gotcha this script avoids.

set -euo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="$WORKSPACE/marlow-dev-stack"
THEMIS_DIR="$WORKSPACE/themis"

SKIP_THEMIS=0
REBUILD=0
RESET_KAFKA=0
for arg in "$@"; do
  case "$arg" in
    --skip-themis) SKIP_THEMIS=1 ;;
    --rebuild)     REBUILD=1 ;;
    --reset-kafka) RESET_KAFKA=1 ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

say()  { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m  ! %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. PREREQS
# ---------------------------------------------------------------------------
say "Preflight"

command -v docker >/dev/null   || fail "docker not on PATH. Install Docker Desktop."
command -v gh >/dev/null       || fail "gh CLI not on PATH. Install via https://cli.github.com/"
command -v yarn >/dev/null     || fail "yarn not on PATH. corepack enable or npm i -g yarn@1"
command -v node >/dev/null     || fail "node not on PATH. Install Node 22.13+ (or 22.12 with --ignore-engines)."

if ! docker ps >/dev/null 2>&1; then
  fail "Docker daemon not reachable. Start Docker Desktop and re-run."
fi
echo "  ✓ docker daemon"

if ! gh auth status >/dev/null 2>&1; then
  fail "gh CLI not authenticated. Run: gh auth login"
fi
echo "  ✓ gh auth"

# Configure gh to use HTTPS (SSH on this machine usually has passphrase-locked id_rsa, no agent).
gh config set -h github.com git_protocol https >/dev/null 2>&1 || true

if [ ! -f "$HOME/.m2/settings.xml" ]; then
  fail "~/.m2/settings.xml missing. Needs a <server id=\"nexus\"> block with NEXUS_USER/NEXUS_PASS. See LOCAL_STACK.md §0."
fi
echo "  ✓ ~/.m2/settings.xml"

if [ -z "${NEXUS_TOKEN:-}" ]; then
  fail "NEXUS_TOKEN env var not set. Persist it once: see LOCAL_STACK.md §'One-time: persist credentials as OS env vars'."
fi
echo "  ✓ NEXUS_TOKEN in env"

# ---------------------------------------------------------------------------
# 2. SIBLING REPOS
# ---------------------------------------------------------------------------
say "Sibling repos (clone if missing)"

for repo in phoebe alcyone themis argo.db instructions ananke; do
  target="$WORKSPACE/$repo"
  if [ -d "$target/.git" ]; then
    echo "  ✓ $repo"
  else
    echo "  → cloning $repo"
    gh repo clone "Marlow-Navigation/$repo" "$target" >/dev/null
  fi
done

# ---------------------------------------------------------------------------
# 3. ENV FILES
# ---------------------------------------------------------------------------
say "Env files"

if [ ! -f "$STACK_DIR/.env.local" ]; then
  cp "$STACK_DIR/.env.local.example" "$STACK_DIR/.env.local"
  warn ".env.local created from template — fill in SECRETS section (SURVEYS_INTERNAL_SA, migration_debriefing, etc.) before BE features will fully work."
else
  echo "  ✓ marlow-dev-stack/.env.local"
fi

if [ ! -f "$THEMIS_DIR/.env.local" ]; then
  cp "$STACK_DIR/themis.env.local.example" "$THEMIS_DIR/.env.local"
  warn "themis/.env.local created from template — fill in NEXTAUTH_SECRET, KEYCLOAK_CLIENT_SECRET, NEXT_PUBLIC_MUI_LICENSE_KEY before login works."
else
  echo "  ✓ themis/.env.local"
fi

# ---------------------------------------------------------------------------
# 4. OPTIONAL RESETS
# ---------------------------------------------------------------------------
cd "$STACK_DIR"

if [ "$RESET_KAFKA" = 1 ]; then
  say "Resetting kafka + zookeeper (volumes wiped)"
  docker rm -f poseidon-kafka poseidon-zookeeper poseidon-kafka-ui >/dev/null 2>&1 || true
  docker volume rm marlow-dev-stack_poseidon-kafka-data marlow-dev-stack_poseidon-zookeeper-data >/dev/null 2>&1 || true
fi

if [ "$REBUILD" = 1 ]; then
  say "Rebuilding BE images (this can take a few minutes on first run)"
  DOCKER_BUILDKIT=1 docker compose --env-file .env.local build crewing alcyone
fi

# ---------------------------------------------------------------------------
# 5. INFRA
# ---------------------------------------------------------------------------
say "Infra (postgres, kafka, zookeeper, pgadmin, kafka-ui, jaeger)"
docker compose --env-file .env.local up -d postgres pgadmin zookeeper kafka kafka-ui jaeger >/dev/null

# ---------------------------------------------------------------------------
# 6. MIGRATIONS
# ---------------------------------------------------------------------------
say "Argo DB migrations"
docker compose --env-file .env.local up -d argo-db-app >/dev/null

# Wait for the crewing schema to exist (proxy for "migrations done").
i=0
until docker exec poseidon-postgres psql -U postgres -d postgres -c "\dn" 2>/dev/null | grep -q crewing; do
  i=$((i+1))
  if [ $i -gt 60 ]; then
    fail "Migrations didn't finish in 5 min. docker logs argo-db-app"
  fi
  sleep 5
done
echo "  ✓ schemas present"

# ---------------------------------------------------------------------------
# 7. BE SERVICES
# ---------------------------------------------------------------------------
say "Backend services (crewing, alcyone)"
docker compose --env-file .env.local up -d crewing alcyone >/dev/null

# crewing
i=0
until curl -sS --max-time 2 http://localhost:8081/health 2>/dev/null | grep -q UP; do
  i=$((i+1)); [ $i -gt 60 ] && fail "crewing didn't come up. docker logs phoebe-crewing"
  sleep 5
done
echo "  ✓ crewing :8081"

# alcyone — often hits the kafka-DNS race on cold start; one auto-bounce.
i=0
bounced=0
until curl -sS --max-time 2 http://localhost:8082/health 2>/dev/null | grep -q '"UP"'; do
  i=$((i+1))
  if [ $i -eq 12 ] && [ $bounced -eq 0 ]; then
    warn "alcyone slow to start, bouncing once (likely kafka DNS race)"
    docker restart alcyone-api >/dev/null
    bounced=1
    i=0
  fi
  [ $i -gt 60 ] && fail "alcyone didn't come up. docker logs alcyone-api"
  sleep 5
done
echo "  ✓ alcyone :8082"

# ---------------------------------------------------------------------------
# 8. THEMIS (host, yarn dev)
# ---------------------------------------------------------------------------
if [ "$SKIP_THEMIS" = 1 ]; then
  echo
  echo "Skipping themis (--skip-themis)."
else
  say "Themis (host, yarn dev)"
  if [ ! -d "$THEMIS_DIR/node_modules" ]; then
    echo "  → yarn install"
    (cd "$THEMIS_DIR" && yarn install --frozen-lockfile --ignore-engines)
  fi

  # Don't start if already listening
  if curl -sS --max-time 2 -o /dev/null http://localhost:3001/ 2>/dev/null; then
    echo "  ✓ themis already on :3001"
  else
    echo "  → starting in background (logs: $WORKSPACE/themis.dev.log)"
    (cd "$THEMIS_DIR" && \
      TURBOPACK=0 nohup npx cross-env nodemon --max_old_space_size=17048 ./src/server/index.ts \
      > "$WORKSPACE/themis.dev.log" 2>&1 &) >/dev/null

    i=0
    until curl -sS --max-time 2 -o /dev/null http://localhost:3001/ 2>/dev/null; do
      i=$((i+1)); [ $i -gt 60 ] && fail "themis didn't come up. tail $WORKSPACE/themis.dev.log"
      sleep 5
    done
    echo "  ✓ themis :3001"
  fi
fi

# ---------------------------------------------------------------------------
# 9. REPORT
# ---------------------------------------------------------------------------
say "Stack is up"
cat <<EOF

  Themis    → http://localhost:3001        (FE — yarn dev)
  Crewing   → http://localhost:8081/health (BE)
  Alcyone   → http://localhost:8082/health (BE)
  pgAdmin   → http://localhost:58080       admin@local.dev / admin
  Kafka-UI  → http://localhost:58081
  Jaeger    → http://localhost:16686
  Postgres  → localhost:5433               postgres/postgres

  Stop everything: cd $STACK_DIR && docker compose --env-file .env.local stop
  Full guide:      $WORKSPACE/instructions/guides/local-dev/LOCAL_STACK.md

EOF
