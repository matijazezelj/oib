#!/usr/bin/env bash
# Upgrade acceptance test: install an older release, write known data, upgrade
# to the current checkout the way users do (make update), then check that the
# data survived and the stack works.
#
# Usage: testing/acceptance/upgrade.sh [FROM_TAG]    (or: make test-upgrade FROM=v1.1.0)
#        FROM_TAG defaults to the most recent release tag.
#
# Losses that are known and accepted for a given starting release are listed in
# upgrade-expectations; they are reported as XFAIL instead of failing the run.
#
# Env:   KEEP=1 leaves the stack running afterwards; OIB_TEST_FORCE=1 runs even
#        if OIB data already exists (and deletes it).

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=testing/acceptance/lib.sh
. "$DIR/lib.sh"
# shellcheck source=testing/acceptance/data.sh
. "$DIR/data.sh"

need docker curl jq make git
cd "$ROOT" || exit 1

FROM=${1:-$(git describe --tags --abbrev=0)}
git rev-parse -q --verify "refs/tags/$FROM" >/dev/null || die "unknown tag: $FROM (fetch tags with: git fetch --tags)"

# Accepted losses for this starting point (first matching line wins)
EXPECT_LOSS=$(awk -v t="$FROM" '$1 == t { $1 = ""; sub(/^ +/, ""); print; exit }' "$DIR/upgrade-expectations")
export EXPECT_LOSS

guard_clean_host

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oib-upgrade-test.XXXXXX")
OLD="$WORK/oib-$FROM"
STATE="$WORK/state"

cleanup() {
  local rc=$?
  if [ "${KEEP:-0}" = 1 ]; then
    warn "KEEP=1: stack left running; old release checked out in $OLD"
  else
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

phase "Install $FROM"
git worktree add --detach "$OLD" "$FROM" >/dev/null 2>&1 || die "git worktree add failed"
cp "$ENV_FILE" "$OLD/.env"
( cd "$OLD" && make --no-print-directory install && make --no-print-directory install-profiling ) >"$WORK/install-old.log" 2>&1 \
  || { tail -30 "$WORK/install-old.log"; die "installing $FROM failed"; }
wait_ready with-profiling
log "running: $(docker ps --filter name=^oib- --format '{{.Image}}' | sort | tr '\n' ' ')"

phase "Seed on $FROM"
seed_run "$STATE" with-profiling

OLD_TEMPO=$(docker inspect -f '{{.Config.Image}}' oib-tempo)
case "$OLD_TEMPO" in
  *tempo:2.*|*tempo:v2.*)
    phase "Tempo 2 -> 3 migration"
    set +e
    make --no-print-directory update >"$WORK/update-guarded.log" 2>&1; rc=$?
    set -e
    check tempo-guard-blocks-update 1 test "$rc" -ne 0
    tempo_still_old() { [ "$(docker inspect -f '{{.Config.Image}}' oib-tempo)" = "$OLD_TEMPO" ]; }
    check tempo-guard-left-tempo-alone 1 tempo_still_old
    # Migrate while traces keep arriving: every trace Alloy accepted must survive.
    write_load_start "$WORK/load"
    sleep 5
    make --no-print-directory migrate-tempo BACKUP_DIR="$WORK/backups" >"$WORK/migrate-tempo.log" 2>&1 \
      || { write_load_stop; tail -30 "$WORK/migrate-tempo.log"; die "make migrate-tempo failed"; }
    MIGRATION_LOAD=1
    grep -E 'flushed|migrated' "$WORK/migrate-tempo.log" | sed 's/\x1b\[[0-9;]*m//g; s/^/    /'
    # Tempo 3 searches only its live store for the most recent 15 minutes, so
    # traces flushed by Tempo 2 become searchable once they are 15 minutes old.
    export TEMPO_SEARCH_LAG=960
    ;;
esac

phase "Upgrade to $(git describe --tags --always --dirty)"
make --no-print-directory update >"$WORK/update.log" 2>&1 || { tail -30 "$WORK/update.log"; die "make update failed"; }
make --no-print-directory update-profiling >>"$WORK/update.log" 2>&1 || { tail -30 "$WORK/update.log"; die "make update-profiling failed"; }
wait_ready with-profiling
log "running: $(docker ps --filter name=^oib- --format '{{.Image}}' | sort | tr '\n' ' ')"
[ -n "$EXPECT_LOSS" ] && log "accepted losses for $FROM: $EXPECT_LOSS"

if [ "${MIGRATION_LOAD:-0}" = 1 ]; then
  write_load_stop
  LOAD_STOP=$(date +%s%3N)
  log "traces sent during the migration: $(grep -c ' trace ' "$WORK/load")"
fi

phase "Verify data from $FROM"
verify_persisted "$STATE"
if [ "${MIGRATION_LOAD:-0}" = 1 ]; then
  check tempo-migration-load 120 load_traces_present "$WORK/load" "$LOAD_STOP"
  [ -s "$WORK/load-report.txt" ] && sort -u "$WORK/load-report.txt" | sed 's/^/    /'
fi

phase "Verify the upgraded stack works"
verify_functional with-profiling

phase "Update again (must be a quiet no-op for data)"
make --no-print-directory update >"$WORK/update2.log" 2>&1 || { tail -30 "$WORK/update2.log"; die "second make update failed"; }
wait_ready
no_migration_nag() { ! grep -q 'Found Grafana data from before' "$WORK/update2.log"; }
check no-migration-warning 1 no_migration_nag
# shellcheck disable=SC1090
. "$STATE"
check grafana-dashboard-after-second-update 60 has_dashboard "$RUN"

summary
