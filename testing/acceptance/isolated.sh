#!/usr/bin/env bash
# Run an acceptance test against a separate Docker daemon (Docker-in-Docker), so
# it cannot touch an OIB install on this host and does not need its ports free.
#
# Usage: testing/acceptance/isolated.sh backup-roundtrip.sh
#        testing/acceptance/isolated.sh upgrade.sh v1.0.0
#   (or: make test-backup ISOLATED=1, make test-upgrade FROM=v1.0.0 ISOLATED=1)
#
# How it works:
#   - a privileged docker:dind container runs the inner daemon; its image cache
#     lives in the volume oibtest-dind-cache, so later runs skip most pulls
#   - the test runs in a small runner container that shares the dind network
#     namespace (the inner stacks publish on its 127.0.0.1) and talks to the
#     inner daemon over its TCP socket, which listens on 127.0.0.1 only
#   - the inner daemon uses its own address ranges, so the host's bridge (and a
#     DNS server listening on it, e.g. 172.17.0.1) stays reachable from inside
#   - the repository and a scratch volume are mounted at the same paths in both
#     containers, so bind mounts in the compose files resolve inside dind
#
# Needs: Docker on the host with privileged containers allowed.
# Env: DIND_KEEP_CACHE=0 removes the image cache volume afterwards.

set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../.." && pwd)
TEST=${1:?usage: isolated.sh <backup-roundtrip.sh|upgrade.sh> [args]}; shift
[ -x "$DIR/$TEST" ] || { echo "unknown test: $TEST" >&2; exit 2; }

DIND_IMAGE=docker:27.5.1-dind
# Names start with "oibtest-", not "oib-", so the clean-host guard and the
# teardown of a direct (non-isolated) run never match them.
RUNNER_IMAGE=oibtest-runner:2
NAME=oibtest-dind-$$
RUNNER=oibtest-runner-$$
SCRATCH=oibtest-scratch-$$
CACHE=oibtest-dind-cache
LOCK=oibtest-lock

LOCKED=0
CREATED_ENV=0
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  docker rm -f "$RUNNER" >/dev/null 2>&1 || true
  docker rm -f -v "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$SCRATCH" >/dev/null 2>&1 || true
  if [ "${DIND_KEEP_CACHE:-1}" = 0 ]; then docker volume rm "$CACHE" >/dev/null 2>&1 || true; fi
  # worktrees the test created live in the scratch volume, which is gone now
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  if [ "$CREATED_ENV" = 1 ]; then rm -f "$ROOT/.env"; fi
  if [ "$LOCKED" = 1 ]; then docker rm -f "$LOCK" >/dev/null 2>&1 || true; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "==> building the runner image"
docker build -q -t "$RUNNER_IMAGE" - >/dev/null <<'EOF'
FROM docker:27.5.1-cli
RUN apk add --no-cache bash make curl jq git coreutils util-linux findutils gawk lsof
EOF

# One isolated run at a time: two inner daemons must not share the image cache
# (/var/lib/docker). The lock is a container name, which Docker creates
# atomically; it records the owner's PID so a lock left by a killed run is
# recognised as stale.
acquire_lock() {
  local owner host
  for _ in $(seq 1 10); do
    if docker create --name "$LOCK" --label "oibtest.pid=$$" --label "oibtest.host=$(hostname)" \
         "$RUNNER_IMAGE" true >/dev/null 2>&1; then
      LOCKED=1; return 0
    fi
    if ! docker inspect "$LOCK" >/dev/null 2>&1; then
      sleep 1; continue   # create failed for another reason (e.g. image being re-tagged); try again
    fi
    owner=$(docker inspect -f '{{index .Config.Labels "oibtest.pid"}}' "$LOCK" 2>/dev/null || true)
    host=$(docker inspect -f '{{index .Config.Labels "oibtest.host"}}' "$LOCK" 2>/dev/null || true)
    if [ -n "$owner" ] && [ "$host" = "$(hostname)" ] && ! kill -0 "$owner" 2>/dev/null; then
      echo "==> removing a stale lock and leftovers of an interrupted run (pid $owner)"
      docker ps -aq --filter name=^oibtest-runner- --filter name=^oibtest-dind- | xargs -r docker rm -f -v >/dev/null 2>&1 || true
      docker volume ls -q --filter name=^oibtest-scratch- | xargs -r docker volume rm >/dev/null 2>&1 || true
      docker rm -f "$LOCK" >/dev/null 2>&1 || true
      continue
    fi
    echo "another isolated acceptance run is in progress (pid ${owner:-?}); wait for it to finish" >&2
    exit 2
  done
  echo "could not take the lock $LOCK" >&2; exit 2
}
acquire_lock

# A temporary .env is made here, on the host side, so it is removed even when
# the run is interrupted and the runner container is killed.
if [ ! -f "$ROOT/.env" ]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  sed -i.bak "s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=$(od -An -tx1 -N12 /dev/urandom | tr -d ' \n')/" "$ROOT/.env"
  rm -f "$ROOT/.env.bak"
  CREATED_ENV=1
fi

echo "==> starting the inner Docker daemon"
docker volume create "$SCRATCH" >/dev/null
docker run -d --privileged --name "$NAME" \
  -e DOCKER_TLS_CERTDIR= \
  -v "$CACHE":/var/lib/docker \
  -v "$ROOT":"$ROOT" \
  -v "$SCRATCH":/acceptance-tmp \
  "$DIND_IMAGE" dockerd --host=unix:///var/run/docker.sock --host=tcp://127.0.0.1:2375 \
    --bip=10.213.0.1/24 --default-address-pool base=10.214.0.0/16,size=24 >/dev/null
for _ in $(seq 1 60); do
  docker exec "$NAME" docker -H tcp://127.0.0.1:2375 info >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$NAME" docker -H tcp://127.0.0.1:2375 info >/dev/null || { docker logs "$NAME" | tail -20; exit 1; }
# The cache volume is meant for images only. Containers, volumes and networks
# that an interrupted earlier run left inside the inner daemon are removed, so
# the test starts from a clean inner host.
inner() { docker exec "$NAME" docker -H tcp://127.0.0.1:2375 "$@"; }
leftovers=$(inner ps -aq)
if [ -n "$leftovers" ]; then
  echo "==> removing containers an earlier interrupted run left in the inner daemon"
  # shellcheck disable=SC2086
  inner rm -f $leftovers >/dev/null
fi
inner volume prune -af >/dev/null
inner network prune -f >/dev/null
# the scratch volume must be writable by the (non-root) runner
docker exec "$NAME" chmod 1777 /acceptance-tmp

echo "==> running $TEST $* inside the isolated daemon"
docker run --rm --name "$RUNNER" \
  --network "container:$NAME" \
  --user "$(id -u):$(id -g)" \
  -e DOCKER_HOST=tcp://127.0.0.1:2375 \
  -e HOME=/acceptance-tmp \
  -e TMPDIR=/acceptance-tmp \
  -e VERIFY_TIMEOUT -e READY_TIMEOUT -e OIB_TEST_FULL \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
  -v "$ROOT":"$ROOT" \
  -v "$SCRATCH":/acceptance-tmp \
  -w "$ROOT" \
  "$RUNNER_IMAGE" "$DIR/$TEST" "$@" &
# wait (unlike a foreground command) returns as soon as a signal arrives, so an
# interrupt reaches cleanup right away instead of after the test finishes.
wait $!
