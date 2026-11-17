#!/usr/bin/env bash
# Tempo 2 -> 3 migration failure and recovery test.
#
# Installs the telemetry stack of a Tempo 2 release (default v1.0.0) and checks:
#   1. unavailable image   -> make migrate-tempo aborts, Tempo 2 untouched and accepting
#   2. broken new config   -> the dry run catches it, Tempo 2 untouched and accepting
#   3. interrupted after /shutdown (Tempo 2 up, ingester stopped, traces queued in
#      Alloy) -> rerunning make migrate-tempo completes, no trace lost
#   4. make rollback-tempo -> Tempo 2 back with its pre-migration traces and
#      accepting new ones; migrating again works
#
# Usage: testing/acceptance/tempo-migration-recovery.sh [TEMPO2_TAG]
#        (or: make test-tempo-recovery [FROM=v1.0.0] [ISOLATED=1])

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=testing/acceptance/lib.sh
. "$DIR/lib.sh"
# shellcheck source=testing/acceptance/data.sh
. "$DIR/data.sh"

need docker curl jq make git
cd "$ROOT" || exit 1
FROM=${1:-v1.0.0}
git rev-parse -q --verify "refs/tags/$FROM" >/dev/null || die "unknown tag: $FROM"
guard_clean_host

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oib-tempo-recovery.XXXXXX")
OLD="$WORK/oib-$FROM"
cleanup() {
  local rc=$?
  if [ "${KEEP:-0}" != 1 ]; then
    phase "Cleanup"
    teardown_all
    git -C "$ROOT" worktree remove --force "$OLD" >/dev/null 2>&1 || true
    rm -rf "$WORK"
  fi
  cleanup_env
  exit $rc
}
trap cleanup EXIT
ensure_env
BK="$WORK/backups"

tempo_image() { docker inspect -f '{{.Config.Image}}' oib-tempo 2>/dev/null; }
tempo_is() { case "$(tempo_image)" in *tempo:"$1"*) return 0 ;; *) return 1 ;; esac; }
# write a trace through Alloy and require it to open by ID
accepts_traces() {
  local run t; run=$(hex 8); t=$(hex 32)
  retry 30 seed_trace "$run" "$t" && retry 60 has_trace_by_id "$run" "$t"
}
send() { # send NAME: write a trace through Alloy, remember its run and ID
  local run t; run=$(hex 8); t=$(hex 32)
  retry 60 seed_trace "$run" "$t" || die "Alloy did not accept trace $1"
  echo "$run $t" >"$WORK/trace-$1"
}
present() { local run t; read -r run t <"$WORK/trace-$1"; has_trace_by_id "$run" "$t"; }

phase "Install the telemetry stack of $FROM"
git worktree add --detach "$OLD" "$FROM" >/dev/null 2>&1 || die "git worktree add failed"
cp "$ENV_FILE" "$OLD/.env"
( cd "$OLD" && make --no-print-directory network && make --no-print-directory install-telemetry ) >"$WORK/install.log" 2>&1 \
  || { tail -30 "$WORK/install.log"; die "installing $FROM telemetry failed"; }
retry 120 http_ok "$TEMPO/ready" || die "Tempo 2 not ready"
tempo_is 2. || die "expected Tempo 2, got $(tempo_image)"
log "running $(tempo_image)"
send a
check trace-a-written 60 present a

phase "1. New image unavailable"
set +e
TEMPO_VERSION=9.9.9-oib-does-not-exist make --no-print-directory migrate-tempo BACKUP_DIR="$BK" >"$WORK/m1.log" 2>&1; rc=$?
set -e
check unavailable-image-aborts 1 test "$rc" -ne 0
check unavailable-image-says-nothing-changed 1 grep -q 'nothing was changed' "$WORK/m1.log"
check unavailable-image-leaves-tempo2 1 tempo_is 2.
check unavailable-image-tempo2-accepts 60 accepts_traces

phase "2. New config broken (dry run)"
printf 'server:\n  http_listen_port: [not, a, port]\n' >"$WORK/broken-tempo.yaml"
set +e
TEMPO_CONFIG="$WORK/broken-tempo.yaml" make --no-print-directory migrate-tempo BACKUP_DIR="$BK" >"$WORK/m2.log" 2>&1; rc=$?
set -e
check broken-config-aborts 1 test "$rc" -ne 0
check broken-config-caught-by-dry-run 1 grep -q 'does not start' "$WORK/m2.log"
check broken-config-leaves-tempo2 1 tempo_is 2.
check broken-config-tempo2-accepts 60 accepts_traces
check no-dry-run-container-left 1 test -z "$(docker ps -aq --filter name=^oib-tempo-dryrun$)"
send b
check trace-b-written 60 present b

phase "3. Interrupted after /shutdown, then rerun"
curl -fsS -X POST "$TEMPO/shutdown" >/dev/null || die "POST /shutdown failed"
sleep 3
send c   # Alloy accepts it and keeps retrying while Tempo 2 refuses writes
log "trace c sent while Tempo 2's ingester is stopped"
make --no-print-directory migrate-tempo BACKUP_DIR="$BK" >"$WORK/m3.log" 2>&1 \
  || { tail -20 "$WORK/m3.log"; die "rerunning make migrate-tempo failed"; }
check rerun-migrates 1 tempo_is 3.
check trace-a-after-migration 120 present a
check trace-b-after-migration 120 present b
check trace-c-queued-during-shutdown 120 present c
send d
check trace-d-on-tempo3 60 present d

phase "4. Roll back to Tempo 2, then migrate again"
make --no-print-directory rollback-tempo BACKUP_DIR="$BK" YES=1 >"$WORK/rb.log" 2>&1 \
  || { tail -20 "$WORK/rb.log"; die "make rollback-tempo failed"; }
check rollback-runs-tempo2 1 tempo_is 2.
check rollback-trace-a 120 present a
check rollback-trace-b 120 present b
check rollback-tempo2-accepts 60 accepts_traces
send e
check trace-e-on-rolled-back-tempo2 60 present e
make --no-print-directory migrate-tempo BACKUP_DIR="$BK" >"$WORK/m4.log" 2>&1 \
  || { tail -20 "$WORK/m4.log"; die "migrating again after the rollback failed"; }
check migrate-again 1 tempo_is 3.
check trace-a-after-second-migration 120 present a
check trace-b-after-second-migration 120 present b
check trace-e-after-second-migration 120 present e

summary
