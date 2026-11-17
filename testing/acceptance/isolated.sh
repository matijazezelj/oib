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
#     lives in the volume oib-acceptance-dind-cache, so later runs skip most pulls
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
RUNNER_IMAGE=oib-acceptance-runner:2
NAME=oib-acceptance-dind-$$
SCRATCH=oib-acceptance-scratch-$$
CACHE=oib-acceptance-dind-cache

cleanup() {
  local rc=$?
  docker rm -f -v "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$SCRATCH" >/dev/null 2>&1 || true
  [ "${DIND_KEEP_CACHE:-1}" = 0 ] && docker volume rm "$CACHE" >/dev/null 2>&1
  # worktrees the test created live in the scratch volume, which is gone now
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  exit $rc
}
trap cleanup EXIT

echo "==> building the runner image"
docker build -q -t "$RUNNER_IMAGE" - >/dev/null <<'EOF'
FROM docker:27.5.1-cli
RUN apk add --no-cache bash make curl jq git coreutils util-linux findutils gawk lsof
EOF

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
# the scratch volume must be writable by the (non-root) runner
docker exec "$NAME" chmod 1777 /acceptance-tmp

echo "==> running $TEST $* inside the isolated daemon"
docker run --rm \
  --network "container:$NAME" \
  --user "$(id -u):$(id -g)" \
  -e DOCKER_HOST=tcp://127.0.0.1:2375 \
  -e HOME=/acceptance-tmp \
  -e TMPDIR=/acceptance-tmp \
  -e VERIFY_TIMEOUT -e READY_TIMEOUT \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
  -v "$ROOT":"$ROOT" \
  -v "$SCRATCH":/acceptance-tmp \
  -w "$ROOT" \
  "$RUNNER_IMAGE" "$DIR/$TEST" "$@"
