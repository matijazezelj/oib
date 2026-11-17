#!/usr/bin/env bash
# Run an acceptance test directly against this host's Docker daemon.
# Usage: testing/acceptance/run.sh <backup-roundtrip.sh|upgrade.sh> [args]
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
TEST=${1:?usage: run.sh <backup-roundtrip.sh|upgrade.sh> [args]}; shift
[ -x "$DIR/$TEST" ] || { echo "unknown test: $TEST" >&2; exit 2; }
exec "$DIR/$TEST" "$@"
