#!/usr/bin/env bash
# Self-test for isolated mode (isolated.sh): concurrent invocations, interrupted
# runs and killed runs must never touch the host's OIB install and must not leave
# anything behind (containers, volumes, lock, .env, git worktrees).
#
# Usage: testing/acceptance/isolation-selftest.sh   (or: make test-isolation)
# Takes a few minutes; the inner test is always interrupted before it gets far.

set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../.." && pwd)
ISO="$DIR/isolated.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/oibtest-selftest.XXXXXX")
trap 'if [ "${FAILED:-0}" -eq 0 ]; then rm -rf "$WORK"; else echo "logs kept in $WORK" >&2; fi' EXIT

PASSED=0; FAILED=0
ok()   { PASSED=$((PASSED + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAILED=$((FAILED + 1)); printf '  FAIL  %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

host_state() {   # the host's own OIB install (if any), plus .env and worktrees
  { docker ps -a --filter name=^oib- --format '{{.ID}} {{.Names}} {{.State}}' | sort
    docker volume ls -q --filter name=^oib- | sort
    [ -f "$ROOT/.env" ] && sha256sum "$ROOT/.env" || echo "no .env"
    git -C "$ROOT" worktree list --porcelain | grep '^worktree' ; } 2>/dev/null
}
no_leftovers() {
  local left
  left=$( { docker ps -a --filter name=^oibtest-dind- --filter name=^oibtest-runner- --filter name=^oibtest-lock --format '{{.Names}} ({{.Status}})'
            docker volume ls -q --filter name=^oibtest-scratch-; } )
  [ -z "$left" ] || { printf '%s\n' "$left" | sed 's/^/    left behind: /'; return 1; }
}
host_unchanged() {
  host_state >"$WORK/host-now"
  diff "$WORK/host-before" "$WORK/host-now" | sed 's/^/    /' || return 1
}

start_run() { # start_run NAME: isolated run in its own process group
  set -m
  "$ISO" backup-roundtrip.sh >"$WORK/$1.log" 2>&1 &
  set +m
  echo $! >"$WORK/$1.pid"
}
runner_of() { docker ps -q --filter "name=^oibtest-runner-$(cat "$WORK/$1.pid")$"; }
wait_runner() { # wait_runner NAME: until the run's test container is running
  for _ in $(seq 1 180); do [ -n "$(runner_of "$1")" ] && return 0; sleep 1; done; return 1
}
# wait_exit NAME: wait for a run started by this shell and store its exit code in RC
# (not via $(...): a subshell cannot wait for this shell's children)
wait_exit() { local pid; pid=$(cat "$WORK/$1.pid"); RC=0; wait "$pid" 2>/dev/null || RC=$?; }

[ -z "$(docker ps -aq --filter name=^oibtest-)" ] || { echo "isolated runs are active; try again later" >&2; exit 2; }
host_state >"$WORK/host-before"

echo "── Two runs started at the same moment ──"
start_run a; start_run b
for _ in $(seq 1 120); do
  ka=$(kill -0 "$(cat "$WORK/a.pid")" 2>/dev/null && echo 1 || echo 0)
  kb=$(kill -0 "$(cat "$WORK/b.pid")" 2>/dev/null && echo 1 || echo 0)
  [ "$ka$kb" = 11 ] || break; sleep 1
done
if kill -0 "$(cat "$WORK/a.pid")" 2>/dev/null; then win=a lose=b; else win=b lose=a; fi
check "exactly one run proceeds" kill -0 "$(cat "$WORK/$win.pid")"
wait_exit "$lose"
check "the other refuses (exit 2)" test "$RC" = 2
check "the refused run says why" grep -q 'another isolated acceptance run is in progress' "$WORK/$lose.log"

echo "── Interrupting the running one (Ctrl+C) ──"
wait_runner "$win" || bad "runner of $win never started"
kill -INT -- "-$(cat "$WORK/$win.pid")" 2>/dev/null || true
wait_exit "$win"
check "interrupted run exits with 130" test "$RC" = 130
check "nothing left behind after Ctrl+C" no_leftovers
check "host install, .env and worktrees unchanged" host_unchanged

echo "── kill -9, then a new run ──"
start_run c
wait_runner c || bad "runner of c never started"
kill -KILL -- "-$(cat "$WORK/c.pid")"; wait "$(cat "$WORK/c.pid")" 2>/dev/null || true
check "kill -9 leaves a stale lock (expected)" test -n "$(docker ps -aq --filter name=^oibtest-lock$)"
start_run d
wait_runner d || bad "runner of d never started"
check "next run takes over the stale lock" grep -q 'removing a stale lock' "$WORK/d.log"
check "only one inner daemon runs" test "$(docker ps -q --filter name=^oibtest-dind- | wc -l)" -eq 1
kill -INT -- "-$(cat "$WORK/d.pid")" 2>/dev/null || true; wait_exit d
check "nothing left behind after the stale-lock run" no_leftovers
# kill -9 cannot clean up the .env the killed run created; the next run (d)
# reuses it and does not own it, so remove it here if the host had none.
if grep -q 'no .env' "$WORK/host-before" && [ -f "$ROOT/.env" ]; then rm -f "$ROOT/.env"; fi
git -C "$ROOT" worktree prune
check "host install and worktrees unchanged" host_unchanged

printf '\nResult: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
