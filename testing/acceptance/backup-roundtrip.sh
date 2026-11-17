#!/usr/bin/env bash
# Backup/restore acceptance test.
#
#   1. install all stacks (including profiling) on a clean Docker host
#   2. write known data into every backend and check it is readable
#   3. make backup
#   4. make uninstall (volumes deleted), reinstall on fresh volumes
#   5. control: the known data must be gone
#   6. make restore-all
#   7. the known data must be back, and the stack must work end to end
#
# Usage: testing/acceptance/backup-roundtrip.sh     (or: make test-backup)
# Env:   KEEP=1 leaves the stack running afterwards; OIB_TEST_FORCE=1 runs even
#        if OIB data already exists (and deletes it).

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=testing/acceptance/lib.sh
. "$DIR/lib.sh"
# shellcheck source=testing/acceptance/data.sh
. "$DIR/data.sh"

need docker curl jq make
cd "$ROOT" || exit 1
guard_clean_host

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oib-backup-test.XXXXXX")
STATE="$WORK/state"
STAMP="acceptance_$(date +%Y%m%d_%H%M%S)"

cleanup() {
  local rc=$?
  if [ "${KEEP:-0}" = 1 ]; then
    warn "KEEP=1: stack left running; backups in $WORK"
  else
    phase "Cleanup"
    teardown_all
    rm -rf "$WORK"
  fi
  cleanup_env
  exit $rc
}
trap cleanup EXIT
ensure_env

phase "Install"
make --no-print-directory install >"$WORK/install.log" 2>&1 || { tail -30 "$WORK/install.log"; die "make install failed"; }
make --no-print-directory install-profiling >>"$WORK/install.log" 2>&1 || { tail -30 "$WORK/install.log"; die "make install-profiling failed"; }
wait_ready with-profiling

phase "Seed"
seed_run "$STATE" with-profiling

phase "Backup"
make --no-print-directory backup BACKUP_DIR="$WORK/backups" TIMESTAMP="$STAMP"
for c in prometheus loki tempo grafana pyroscope; do
  [ -s "$WORK/backups/${c}_$STAMP.tar.gz" ] || die "backup file missing: ${c}_$STAMP.tar.gz"
  [ -O "$WORK/backups/${c}_$STAMP.tar.gz" ] || die "backup file not owned by the invoking user: ${c}_$STAMP.tar.gz"
done
wait_ready with-profiling   # every component was paused during its backup

phase "Wipe and reinstall"
teardown_all
if docker volume ls --format '{{.Name}}' | grep -qE '^oib-'; then die "volumes still present after uninstall"; fi
make --no-print-directory install >>"$WORK/install.log" 2>&1 || die "reinstall failed"
make --no-print-directory install-profiling >>"$WORK/install.log" 2>&1 || die "reinstall of profiling failed"
wait_ready with-profiling

phase "Control: fresh volumes do not have the data"
verify_absent "$STATE"

phase "Restore"
make --no-print-directory restore-all STAMP="$STAMP" BACKUP_DIR="$WORK/backups" YES=1
wait_ready with-profiling

phase "Verify restored data"
verify_persisted "$STATE"

phase "Verify the stack works"
verify_functional with-profiling

summary
