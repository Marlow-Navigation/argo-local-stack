#!/bin/zsh
# Recreate local Marlow dev infrastructure and wait for argo-db migrations to complete.
# Works with both docker-compose and podman-compose.

set -e

STACK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect compose command
if command -v docker-compose &>/dev/null && docker info &>/dev/null 2>&1; then
  COMPOSE="docker-compose"
  RUNTIME="docker"
elif command -v podman-compose &>/dev/null; then
  COMPOSE="podman-compose"
  RUNTIME="podman"
else
  echo "❌ Neither docker-compose nor podman-compose found"
  exit 1
fi

echo "Using: $COMPOSE"

echo "🔄 Tearing down existing stack..."
$COMPOSE -f "$STACK_DIR/docker-compose.yaml" down -v --remove-orphans

echo "🚀 Starting stack with tracing..."
$COMPOSE -f "$STACK_DIR/docker-compose.yaml" --profile tracing up -d

echo "⏳ Waiting for argo-db-app migrations to complete..."
while true; do
  if $RUNTIME logs argo-db-app 2>&1 | tail -5 | grep -q "shutting down sbt server"; then
    echo "✅ argo-db-app migrations complete. Stack is ready!"
    break
  fi

  cstate=$($RUNTIME inspect --format '{{.State.Status}}' argo-db-app 2>/dev/null || echo "missing")
  if [[ "$cstate" == "exited" || "$cstate" == "missing" ]]; then
    ecode=$($RUNTIME inspect --format '{{.State.ExitCode}}' argo-db-app 2>/dev/null || echo "?")
    if [[ "$ecode" == "0" ]]; then
      echo "✅ argo-db-app exited successfully. Stack is ready!"
      break
    else
      echo "❌ argo-db-app exited with code $ecode"
      $RUNTIME logs --tail 20 argo-db-app
      exit 1
    fi
  fi

  sleep 3
done
