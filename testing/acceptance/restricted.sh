#!/usr/bin/env bash
# Restricted-mode acceptance test (OIB_MODE=restricted).
#
#   1. install every stack in restricted mode
#   2. inspect every running oib-* container: no Docker socket, no bind mount of
#      the host's /, /run, /var/run or /var/lib/docker, no added capability, not
#      privileged, no host PID/network namespace, no devices; /proc and /sys
#      read-only. cAdvisor and Alloy (logging) must not exist.
#   3. the stack works: datasources, dashboards, rules, every Prometheus target
#      up, host metrics, pushed logs, traces, profiles, make health
#   4. switch to standard mode with make install: cAdvisor and container-log
#      collection come back, the invariant check flags them (control), the data
#      written in restricted mode is kept
#   5. switch back to restricted: the privileged containers are removed, the
#      invariant holds again, the data is kept
#
# Usage: testing/acceptance/restricted.sh     (or: make test-restricted [ISOLATED=1])

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=testing/acceptance/lib.sh
. "$DIR/lib.sh"
# shellcheck source=testing/acceptance/data.sh
. "$DIR/data.sh"

need docker curl jq make
cd "$ROOT" || exit 1
guard_clean_host

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oib-restricted-test.XXXXXX")
STATE="$WORK/state"

cleanup() {
  local rc=$?
  if [ "${KEEP:-0}" = 1 ]; then
    warn "KEEP=1: stack left running"
  else
    phase "Cleanup"
    teardown_all
  fi
  # put back the .env this test switched between modes
  if [ -f "$WORK/env.orig" ]; then cp "$WORK/env.orig" "$ENV_FILE"; fi
  [ "${KEEP:-0}" = 1 ] || rm -rf "$WORK"
  cleanup_env
  exit $rc
}
trap cleanup EXIT
ensure_env
cp "$ENV_FILE" "$WORK/env.orig"

set_mode() { # set_mode standard|restricted: write OIB_MODE into .env
  grep -v '^OIB_MODE=' "$WORK/env.orig" >"$ENV_FILE"
  echo "OIB_MODE=$1" >>"$ENV_FILE"
}
install_all() { # install_all LOGNAME
  { make --no-print-directory install && make --no-print-directory install-profiling; } >"$WORK/$1.log" 2>&1 \
    || { tail -30 "$WORK/$1.log"; die "make install ($1) failed"; }
  wait_ready with-profiling
}

# Every running OIB container satisfies the restricted invariant. Violations go
# to $WORK/violations.txt (check() hides output).
restricted_invariant() {
  local report="$WORK/violations.txt" c n=0
  : >"$report"
  for c in $(docker ps -q --filter name=^oib-); do
    n=$((n + 1))
    docker inspect "$c" | jq -r '.[0] | .Name as $n | .HostConfig as $h |
      ( if $h.Privileged then "\($n): privileged" else empty end ),
      ( ($h.CapAdd // [])[] | "\($n): added capability \(.)" ),
      ( if $h.PidMode == "host" then "\($n): host PID namespace" else empty end ),
      ( if $h.NetworkMode == "host" then "\($n): host network" else empty end ),
      ( ($h.Devices // [])[] | "\($n): device \(.PathOnHost)" ),
      ( .Mounts[] | select(.Type == "bind") |
        if (.Source | test("docker\\.sock")) then "\($n): Docker socket \(.Source)"
        elif .Source == "/" or (.Source | test("^/(run|var/run|var/lib/docker)(/|$)"))
          then "\($n): host path \(.Source) -> \(.Destination)"
        elif (.Source | test("^/(proc|sys)(/|$)")) and .RW then "\($n): writable \(.Source)"
        else empty end )' >>"$report"
  done
  [ "$n" -gt 0 ] && [ ! -s "$report" ]
}
absent() { [ -z "$(docker ps -aq --filter "name=^$1$")" ]; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }
health_ok() { make --no-print-directory health >"$WORK/health.log" 2>&1; }
prom_has_job() { # prom_has_job JOB: Prometheus has an active target for JOB
  curl -fsS "$PROM/api/v1/targets?state=active" | jq -e --arg j "$1" 'any(.data.activeTargets[]; .labels.job == $j)' >/dev/null
}

restricted_checks() { # restricted_checks LABEL
  local t=${VERIFY_TIMEOUT:-120} run trace
  check "$1-invariant"            30 restricted_invariant
  [ -s "$WORK/violations.txt" ] && sed 's/^/      /' "$WORK/violations.txt"
  check "$1-no-cadvisor"           30 absent oib-cadvisor
  check "$1-no-alloy-logging"      30 absent oib-alloy-logging
  check "$1-no-cadvisor-job"       "$t" not prom_has_job cadvisor
  check "$1-datasources-healthy"  "$t" datasources_healthy with-profiling
  check "$1-dashboards"           "$t" dashboards_provisioned
  check "$1-prometheus-rules"     "$t" prom_rules_loaded
  check "$1-targets-up"           "$t" prom_targets_up
  check "$1-host-metrics"         "$t" host_metrics_flowing
  check "$1-make-health"           60 health_ok
  run=$(hex 8); trace=$(hex 32)
  seed_loki "$run" || true
  seed_trace "$run" "$trace" || true
  check "$1-pushed-logs"          "$t" has_log "$run"
  check "$1-traces"               "$t" has_trace_by_id "$run" "$trace"
}
not() { ! "$@"; }

phase "1. Install in restricted mode"
set_mode restricted
install_all install-restricted
log "running: $(docker ps --format '{{.Names}}' --filter name=^oib- | sort | tr '\n' ' ')"

phase "2-3. Restricted invariant and functionality"
seed_run "$STATE" with-profiling
restricted_checks restricted

phase "4. Switch to standard mode"
set_mode standard
install_all install-standard
check standard-cadvisor-running      60 running oib-cadvisor
check standard-alloy-logging-running 60 running oib-alloy-logging
check standard-cadvisor-job         120 prom_has_job cadvisor
check standard-targets-up           120 prom_targets_up
check standard-container-logs       120 container_logs_flowing
check standard-containers-current    30 containers_current
# Control: the invariant check must catch standard mode's privileged containers.
detects_standard_privileges() {
  ! restricted_invariant || return 1
  grep -q 'oib-cadvisor: Docker socket' "$WORK/violations.txt" \
    && grep -q 'oib-cadvisor: added capability SYS_PTRACE' "$WORK/violations.txt" \
    && grep -q 'oib-alloy-logging: Docker socket' "$WORK/violations.txt" \
    && grep -q 'oib-alloy-metrics: host path / -> /rootfs' "$WORK/violations.txt"
}
check standard-invariant-check-detects-privileges 30 detects_standard_privileges
verify_persisted "$STATE"

phase "5. Switch back to restricted mode"
set_mode restricted
install_all install-restricted-again
restricted_checks back-to-restricted
verify_persisted "$STATE"

summary
