#!/usr/bin/env bash
# Shared helpers for the OIB acceptance tests (backup round trip, upgrade).
# Sourced by the other scripts in this directory; not meant to be run directly.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE="$ROOT/.env"

# ---------- output ----------

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=; C_GREEN=; C_YELLOW=; C_CYAN=; C_BOLD=; C_RESET=
fi

log()   { printf '%s==>%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()   { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }
phase() { printf '\n%s%s── %s ──%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }

need() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"; done; }

# ---------- .env and endpoints ----------

env_get() { # env_get KEY DEFAULT
  local v=""
  [ -f "$ENV_FILE" ] && v=$(awk -F= -v k="$1" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$ENV_FILE")
  printf '%s' "${v:-$2}"
}

connect_host() { # 0.0.0.0 / empty bind address -> reach it via loopback
  case "$1" in ""|0.0.0.0|"::") echo 127.0.0.1 ;; *) echo "$1" ;; esac
}

# The endpoint variables are used by data.sh.
# shellcheck disable=SC2034
load_endpoints() {
  local bind otel
  bind=$(connect_host "$(env_get BIND_ADDR 127.0.0.1)")
  otel=$(connect_host "$(env_get OTEL_BIND_ADDR 127.0.0.1)")
  GRAFANA="http://$bind:$(env_get GRAFANA_PORT 3000)"
  LOKI="http://127.0.0.1:$(env_get LOKI_PORT 3100)"
  PROM="http://$bind:$(env_get PROMETHEUS_PORT 9090)"
  TEMPO="http://127.0.0.1:$(env_get TEMPO_HTTP_PORT 3200)"
  OTLP="http://$otel:$(env_get OTEL_HTTP_PORT 4318)"
  PYRO="http://127.0.0.1:$(env_get PYROSCOPE_PORT 4040)"
  GRAFANA_AUTH="admin:$(env_get GRAFANA_ADMIN_PASSWORD '')"
}

# Create a throwaway .env when there is none; removed again by cleanup_env.
CREATED_ENV=0
ensure_env() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ROOT/.env.example" "$ENV_FILE"
    local pw; pw=$(od -An -tx1 -N12 /dev/urandom | tr -d ' \n')
    sed -i.bak "s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=$pw/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
    CREATED_ENV=1
    log "created a temporary .env for this run"
  fi
  load_endpoints
}
cleanup_env() { if [ "$CREATED_ENV" = 1 ]; then rm -f "$ENV_FILE"; fi; }

# The tests delete OIB volumes, so refuse to run next to an existing install.
guard_clean_host() {
  local found
  found=$( { docker ps -a --format '{{.Names}}' | grep -E '^oib-' || true
             docker volume ls --format '{{.Name}}' | grep -E '^oib-' || true; } )
  if [ -n "$found" ] && [ "${OIB_TEST_FORCE:-0}" != 1 ]; then
    printf '%s\n' "$found" | sed 's/^/    /' >&2
    die "OIB containers or volumes already exist (listed above). These tests DELETE all OIB data.
  Run them isolated in Docker-in-Docker instead: make test-backup ISOLATED=1 (or test-upgrade).
  To wipe this install and run here anyway, set OIB_TEST_FORCE=1."
  fi
}

# Remove every OIB stack, volume and the network.
teardown_all() {
  ( cd "$ROOT"
    make --no-print-directory demo-app-stop >/dev/null 2>&1 || true
    make --no-print-directory uninstall-profiling >/dev/null 2>&1 || true
    make --no-print-directory uninstall YES=1 >/dev/null 2>&1 || true )
  # Containers and volumes left behind by older releases (orphaned services,
  # v1.0.0's unnamed Grafana volume)
  docker ps -aq --filter name=^oib- | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker volume ls --format '{{.Name}}' | grep -E '^oib-' | xargs -r docker volume rm >/dev/null 2>&1 || true
  docker network rm oib-network >/dev/null 2>&1 || true
}

# ---------- polling ----------

# retry SECONDS CMD... : rerun CMD every 3s until it succeeds or time runs out
retry() {
  local deadline=$(( $(date +%s) + $1 )); shift
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 3
  done
}

http_ok() { curl -fsS -o /dev/null --max-time 5 "$@"; }

wait_ready() { # wait_ready [with-profiling]
  local timeout=${READY_TIMEOUT:-240} what
  for what in "$GRAFANA/api/health" "$LOKI/ready" "$PROM/-/ready" "$TEMPO/ready"; do
    retry "$timeout" http_ok "$what" || die "not ready after ${timeout}s: $what"
  done
  if [ "${1:-}" = with-profiling ]; then
    # Pyroscope 2 waits ~70s before reporting ready
    retry "$timeout" http_ok "$PYRO/ready" || die "not ready after ${timeout}s: $PYRO/ready"
  fi
  log "all endpoints ready"
}

# ---------- check bookkeeping ----------

PASSED=0; FAILED=0; XFAILED=0; XPASSED=0
FAILED_NAMES=()
EXPECT_LOSS=${EXPECT_LOSS:-}   # space-separated check names that are expected to fail

expected_loss() { case " $EXPECT_LOSS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# check NAME TIMEOUT FN [ARGS...]: FN must succeed within TIMEOUT seconds
check() {
  local name=$1 timeout=$2; shift 2
  if retry "$timeout" "$@"; then
    if expected_loss "$name"; then
      XPASSED=$((XPASSED + 1)); printf '  %sXPASS%s %s (listed as an expected loss but survived; update the expectations)\n' "$C_YELLOW" "$C_RESET" "$name"
    else
      PASSED=$((PASSED + 1)); printf '  %sPASS%s  %s\n' "$C_GREEN" "$C_RESET" "$name"
    fi
  else
    if expected_loss "$name"; then
      XFAILED=$((XFAILED + 1)); printf '  %sXFAIL%s %s (expected loss)\n' "$C_YELLOW" "$C_RESET" "$name"
    else
      FAILED=$((FAILED + 1)); FAILED_NAMES+=("$name"); printf '  %sFAIL%s  %s\n' "$C_RED" "$C_RESET" "$name"
    fi
  fi
}

# check_absent NAME FN [ARGS...]: control check, FN must NOT succeed (data really gone)
check_absent() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("control:$name")
    printf '  %sFAIL%s  control:%s (data present although it should not be)\n' "$C_RED" "$C_RESET" "$name"
  else
    PASSED=$((PASSED + 1)); printf '  %sPASS%s  control:%s absent\n' "$C_GREEN" "$C_RESET" "$name"
  fi
}

summary() {
  printf '\n%sResult:%s %d passed, %d failed, %d expected losses, %d unexpected survivals\n' \
    "$C_BOLD" "$C_RESET" "$PASSED" "$FAILED" "$XFAILED" "$XPASSED"
  if [ "$FAILED" -gt 0 ]; then
    printf '%sFailed:%s %s\n' "$C_RED" "$C_RESET" "${FAILED_NAMES[*]}"
    return 1
  fi
}
