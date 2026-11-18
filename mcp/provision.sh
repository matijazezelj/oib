#!/usr/bin/env bash
# Create or refresh the credentials of the OIB MCP endpoint (make install-mcp).
#
#   - a Grafana service account "oib-mcp" with the Viewer role (enforced on every run)
#   - a token for it, kept while it still works
#   - a random bearer token MCP clients must send
#
# Both go to mcp/secrets/mcp.env (directory 0700, file 0600), which compose
# loads into the container. Grafana must be running.
#
# Usage: mcp/provision.sh GRAFANA_URL
set -euo pipefail

GRAFANA=${1:?usage: provision.sh GRAFANA_URL}
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
SECRETS="$DIR/secrets"
OUT="$SECRETS/mcp.env"
SA_NAME=oib-mcp

die() { echo "✗ $*" >&2; exit 1; }

# Read a value from .env without evaluating it; strip one pair of surrounding quotes.
env_val() {
  awk -F= -v k="$1" '$1 == k { v = substr($0, index($0, "=") + 1); print v; exit }' "$ROOT/.env" 2>/dev/null \
    | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}
file_val() { [ -f "$OUT" ] && sed -n "s/^$1=//p" "$OUT" | head -1; }

ADMIN_USER=$(env_val GRAFANA_ADMIN_USER); ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASS=$(env_val GRAFANA_ADMIN_PASSWORD)
[ -n "$ADMIN_PASS" ] || die "GRAFANA_ADMIN_PASSWORD is not set in .env"

# curl as the Grafana admin. The credentials go through a config on stdin, so
# they never appear in the process list.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
admin() { # admin METHOD PATH [JSON]
  local method=$1 path=$2 body=${3:-}
  printf 'user = "%s:%s"\n' "$(esc "$ADMIN_USER")" "$(esc "$ADMIN_PASS")" \
    | curl -fsS --max-time 15 -K - -X "$method" -H 'Content-Type: application/json' \
        ${body:+--data "$body"} "$GRAFANA$path"
}
json_num() { sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p" | head -1; }
json_str() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -1; }

# Grafana may still be starting (make install && make install-mcp)
i=0
until curl -fsS --max-time 5 -o /dev/null "$GRAFANA/api/health" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -le 90 ] || die "Grafana is not reachable at $GRAFANA (run make install-grafana first)"
  [ "$i" = 1 ] && echo "  … waiting for Grafana at $GRAFANA"
  sleep 1
done
admin GET /api/user >/dev/null || die "Grafana rejected the admin credentials from .env"

# Service account, Viewer only
# one account object per line, then the one named exactly $SA_NAME
id=$(admin GET "/api/serviceaccounts/search?query=$SA_NAME" | tr -d '\n' | sed 's/},{/}\n{/g' \
  | grep "\"name\":\"$SA_NAME\"" | json_num id || true)
if [ -z "$id" ]; then
  id=$(admin POST /api/serviceaccounts "{\"name\":\"$SA_NAME\",\"role\":\"Viewer\",\"isDisabled\":false}" | json_num id)
  [ -n "$id" ] || die "could not create the Grafana service account $SA_NAME"
  echo "  ✓ created Grafana service account $SA_NAME (Viewer)"
else
  admin PATCH "/api/serviceaccounts/$id" '{"role":"Viewer","isDisabled":false}' >/dev/null \
    || die "could not set the role of service account $SA_NAME to Viewer"
fi

# Grafana token: keep the saved one while Grafana accepts it
token=$(file_val GRAFANA_SERVICE_ACCOUNT_TOKEN || true)
if [ -n "$token" ] && curl -fsS --max-time 5 -o /dev/null -H "Authorization: Bearer $token" "$GRAFANA/api/search?limit=1"; then
  echo "  ✓ Grafana service account token still valid"
else
  token=$(admin POST "/api/serviceaccounts/$id/tokens" "{\"name\":\"$SA_NAME-$(date +%Y%m%d%H%M%S)\"}" | json_str key)
  [ -n "$token" ] || die "could not create a token for service account $SA_NAME"
  echo "  ✓ new Grafana service account token"
fi

# Bearer token for MCP clients: keep it, so configured clients keep working
caller=$(file_val MCP_GRAFANA_SERVER_TOKEN || true)
if [ -z "$caller" ]; then
  caller=$(od -An -tx1 -N24 /dev/urandom | tr -d ' \n')
  echo "  ✓ new MCP client token"
fi

umask 077
mkdir -p "$SECRETS"; chmod 700 "$SECRETS"
printf 'GRAFANA_SERVICE_ACCOUNT_TOKEN=%s\nMCP_GRAFANA_SERVER_TOKEN=%s\n' "$token" "$caller" >"$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
