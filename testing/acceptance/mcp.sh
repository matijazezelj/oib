#!/usr/bin/env bash
# MCP endpoint acceptance test (make install-mcp).
#
#   1. install the core stacks and the MCP endpoint, write known data
#   2. access control: no token -> 401, wrong token -> 401, foreign Host -> 403,
#      a browser Origin -> 403
#   3. read-only: no write tool is registered, and Grafana refuses writes made
#      with the endpoint's service-account token (Viewer role)
#   4. it answers from OIB's data: the seeded log line (Loki), a Prometheus
#      series, and the seeded trace (Tempo) through the MCP tools
#   5. make install-mcp repairs a revoked Grafana token and a service account
#      whose role was raised, and keeps the client token; make uninstall-mcp
#      removes the container and the tokens
#
# The test runs on a copy of the checkout: install-mcp and uninstall-mcp
# rewrite and delete mcp/secrets/, which must never touch a real install's tokens.
#
# Usage: testing/acceptance/mcp.sh     (or: make test-mcp [ISOLATED=1])

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=testing/acceptance/lib.sh
. "$DIR/lib.sh"
# shellcheck source=testing/acceptance/data.sh
. "$DIR/data.sh"

need docker curl jq make
cd "$ROOT" || exit 1
guard_clean_host

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oib-mcp-test.XXXXXX")

# Work on a copy of the checkout (see above); record the real secrets to check
# at the end that they are untouched.
secrets_sum() { if [ -d "$1" ]; then (cd "$1" && find . -type f -exec cksum {} + | sort); else echo none; fi; }
HOST_SECRETS="$ROOT/mcp/secrets"; HOST_SECRETS_SUM=$(secrets_sum "$HOST_SECRETS")
mkdir "$WORK/tree"
tar -C "$ROOT" --exclude=./.git --exclude=./mcp/secrets -cf - . | tar -C "$WORK/tree" -xf - || die "copying the checkout failed"
ROOT="$WORK/tree"; ENV_FILE="$ROOT/.env"
cd "$ROOT" || exit 1

cleanup() {
  local rc=$?
  if [ "${KEEP:-0}" = 1 ]; then
    warn "KEEP=1: stack left running"
  else
    phase "Cleanup"
    make --no-print-directory uninstall-mcp >/dev/null 2>&1 || true
    teardown_all
  fi
  [ "${KEEP:-0}" = 1 ] || rm -rf "$WORK"
  cleanup_env
  exit $rc
}
trap cleanup EXIT
ensure_env
MCP="http://127.0.0.1:$(env_get MCP_PORT 3030)"
SECRETS="$ROOT/mcp/secrets/mcp.env"
token() { sed -n "s/^$1=//p" "$SECRETS" 2>/dev/null; }

# mcp_post BODY [extra curl args]: POST to /mcp with the client token and the
# current session; prints the HTTP status, the JSON-RPC body goes to $WORK/body
SESSION=
mcp_post() {
  local body=$1; shift
  local auth=(-H "Authorization: Bearer $(token MCP_GRAFANA_SERVER_TOKEN)")
  [ "${NO_AUTH:-0}" = 1 ] && auth=()
  [ -n "${BAD_AUTH:-}" ] && auth=(-H "Authorization: Bearer $BAD_AUTH")
  curl -sS -o "$WORK/raw" -D "$WORK/headers" -w '%{http_code}' --max-time 60 -X POST "$MCP/mcp" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-06-18' \
    ${SESSION:+-H "Mcp-Session-Id: $SESSION"} "${auth[@]}" "$@" --data "$body"
  # streamable HTTP may answer as an event stream: keep the data lines
  if grep -q '^data:' "$WORK/raw"; then sed -n 's/^data: \{0,1\}//p' "$WORK/raw" >"$WORK/body"; else cp "$WORK/raw" "$WORK/body"; fi
}
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"oib-acceptance","version":"1"}}}'
mcp_init() {
  SESSION=
  [ "$(mcp_post "$INIT")" = 200 ] || return 1
  jq -e '.result.serverInfo' "$WORK/body" >/dev/null || return 1
  SESSION=$(tr -d '\r' <"$WORK/headers" | sed -n 's/^[Mm]cp-[Ss]ession-[Ii]d: //p' | head -1)
  mcp_post '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
}
# bash scoping: a local in the caller is what mcp_post sees
no_token_rejected()    { local NO_AUTH=1; [ "$(mcp_post "$INIT")" = 401 ]; }
wrong_token_rejected() { local BAD_AUTH=not-the-token; [ "$(mcp_post "$INIT")" = 401 ]; }
status_is() { # status_is CODE BODY [curl args]
  local want=$1; shift
  [ "$(mcp_post "$@")" = "$want" ]
}
tools_list() { mcp_post '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' >/dev/null && jq -r '.result.tools[].name' "$WORK/body"; }
has_tools() { local t list; list=$(tools_list) || return 1; for t in "$@"; do grep -qx "$t" <<<"$list" || return 1; done; }
# No tool that can change something: one the server marks as not read-only or
# destructive (MCP tool annotations), or whose name says it writes and that is
# not marked read-only (alerting_manage_routing, say, only has get_* operations).
no_write_tools() {
  mcp_post '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' >/dev/null || return 1
  jq -e '(.result.tools | length) > 0' "$WORK/body" >/dev/null || return 1
  jq -r '.result.tools[] | (.annotations // {}) as $a
    | select($a.readOnlyHint == false or $a.destructiveHint == true
             or ((.name | test("^(create|update|delete|add|patch|put|set|upsert|import|remove|manage|alerting_manage|acknowledge|resolve)_")) and $a.readOnlyHint != true))
    | "\(.name) readOnlyHint=\($a.readOnlyHint) destructiveHint=\($a.destructiveHint)"' "$WORK/body" >"$WORK/write-tools.txt"
  [ ! -s "$WORK/write-tools.txt" ]
}
# call TOOL ARGS_JSON: tools/call; the text content goes to $WORK/text
call() {
  local body
  body=$(jq -cn --arg n "$1" --argjson a "$2" '{jsonrpc:"2.0",id:3,method:"tools/call",params:{name:$n,arguments:$a}}')
  [ "$(mcp_post "$body")" = 200 ] || return 1
  jq -e '.result and (.result.isError != true)' "$WORK/body" >/dev/null || return 1
  jq -r '.result.content[]? | select(.type == "text") | .text' "$WORK/body" >"$WORK/text"
}
call_contains() { local needle=$1; shift; call "$@" && grep -qF "$needle" "$WORK/text"; }

# Grafana with the endpoint's own service-account token
GRAFANA_SA_TOKEN=
grafana_sa() { curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -H "Authorization: Bearer $GRAFANA_SA_TOKEN" "$@"; }
sa_can_read() { [ "$(grafana_sa "$GRAFANA/api/search?limit=1")" = 200 ]; }
sa_cannot_write_dashboard() {
  [ "$(grafana_sa -X POST -H 'Content-Type: application/json' "$GRAFANA/api/dashboards/db" \
        --data '{"dashboard":{"title":"oib-mcp-write-probe"},"overwrite":false}')" = 403 ]
}
sa_cannot_create_service_account() {
  [ "$(grafana_sa -X POST -H 'Content-Type: application/json' "$GRAFANA/api/serviceaccounts" \
        --data '{"name":"oib-mcp-escalation-probe","role":"Admin"}')" = 403 ]
}
sa_is_viewer() {
  curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/serviceaccounts/search?query=oib-mcp" \
    | jq -e '[.serviceAccounts[] | select(.name == "oib-mcp")] | length == 1 and .[0].role == "Viewer"' >/dev/null
}
sa_id() {
  curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/serviceaccounts/search?query=oib-mcp" \
    | jq -r '.serviceAccounts[] | select(.name == "oib-mcp") | .id'
}
revoke_sa_tokens() {
  local id t; id=$(sa_id)
  for t in $(curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/serviceaccounts/$id/tokens" | jq -r '.[].id'); do
    curl -fsS -o /dev/null -u "$GRAFANA_AUTH" -X DELETE "$GRAFANA/api/serviceaccounts/$id/tokens/$t" || return 1
  done
}
raise_sa_role() {
  curl -fsS -o /dev/null -u "$GRAFANA_AUTH" -X PATCH -H 'Content-Type: application/json' \
    "$GRAFANA/api/serviceaccounts/$(sa_id)" --data '{"role":"Editor"}'
}
prom_call_ok() { call_contains '"prometheus"' query_prometheus '{"datasourceUid":"prometheus","expr":"up{job=\"prometheus\"}","queryType":"instant","endTime":"now"}'; }
prom_call_fails() { mcp_init && ! prom_call_ok; }
host_secrets_unchanged() { [ "$(secrets_sum "$HOST_SECRETS")" = "$HOST_SECRETS_SUM" ]; }
secrets_private() {
  [ "$(stat -c '%a' "$ROOT/mcp/secrets" 2>/dev/null || stat -f '%Lp' "$ROOT/mcp/secrets")" = 700 ] \
    && [ "$(stat -c '%a' "$SECRETS" 2>/dev/null || stat -f '%Lp' "$SECRETS")" = 600 ]
}

phase "1. Install the core stacks and the MCP endpoint"
make --no-print-directory install >"$WORK/install.log" 2>&1 || { tail -30 "$WORK/install.log"; die "make install failed"; }
# Straight after make install, as users do: Grafana may still be starting.
make --no-print-directory install-mcp >"$WORK/install-mcp.log" 2>&1 || { tail -30 "$WORK/install-mcp.log"; die "make install-mcp failed"; }
wait_ready
GRAFANA_SA_TOKEN=$(token GRAFANA_SERVICE_ACCOUNT_TOKEN)
RUN=$(hex 8); TRACE=$(hex 32)
seed_loki "$RUN" || die "Loki push failed"
seed_trace "$RUN" "$TRACE" || die "OTLP trace export failed"
retry 60 has_log "$RUN" || die "seeded log line is not readable"
retry 90 has_trace_by_id "$RUN" "$TRACE" || die "seeded trace is not readable"

phase "2. Access control"
check secrets-private                 1 secrets_private
check no-token-rejected               5 no_token_rejected
check wrong-token-rejected            5 wrong_token_rejected
check foreign-host-rejected           5 status_is 403 "$INIT" -H 'Host: attacker.example:3030'
check browser-origin-rejected         5 status_is 403 "$INIT" -H 'Origin: http://attacker.example'
check initialize                     30 mcp_init

phase "3. Read-only"
check read-tools-available           10 has_tools query_prometheus query_loki_logs search_tempo_traces get_tempo_trace search_dashboards
check no-write-tools                 10 no_write_tools
[ -s "$WORK/write-tools.txt" ] && sed 's/^/      write tool: /' "$WORK/write-tools.txt"
check service-account-is-viewer      10 sa_is_viewer
check service-account-can-read       10 sa_can_read
check service-account-cannot-write   10 sa_cannot_write_dashboard
check service-account-cannot-escalate 10 sa_cannot_create_service_account

phase "4. Answers from OIB's data"
check mcp-loki-seeded-log     60 call_contains "oib-acceptance-marker $RUN" query_loki_logs \
  "$(jq -cn --arg q "{job=\"oib-acceptance\", run=\"$RUN\"}" '{datasourceUid:"loki", logql:$q, startRfc3339:"now-1h", limit:5}')"
check mcp-prometheus-up       60 call_contains '"prometheus"' query_prometheus \
  '{"datasourceUid":"prometheus","expr":"up{job=\"prometheus\"}","queryType":"instant","endTime":"now"}'
check mcp-tempo-seeded-trace  60 call_contains "oib-acceptance-$RUN" get_tempo_trace \
  "$(jq -cn --arg t "$TRACE" '{datasourceUid:"tempo", trace_id:$t}')"
check mcp-tempo-search        60 call_contains "oib-acceptance-$RUN" search_tempo_traces \
  "$(jq -cn --arg q "{ resource.service.name = \"oib-acceptance-$RUN\" }" '{datasourceUid:"tempo", query:$q}')"
[ "$FAILED" -gt 0 ] && [ -s "$WORK/text" ] && { log "last tool output:"; head -c 1500 "$WORK/text" | sed 's/^/      /'; echo; }

phase "5. Repair, reinstall and uninstall"
# As after a Grafana restore or reinstall: the saved Grafana token no longer
# works (the endpoint stays healthy, every query fails), and someone raised the
# service account's role.
revoke_sa_tokens || die "revoking the service account's tokens failed"
raise_sa_role || die "raising the service account's role failed"
check revoked-token-breaks-queries 30 prom_call_fails
before=$(token MCP_GRAFANA_SERVER_TOKEN)
make --no-print-directory install-mcp >"$WORK/reinstall-mcp.log" 2>&1 || { tail -30 "$WORK/reinstall-mcp.log"; die "second make install-mcp failed"; }
check reinstall-keeps-client-token  1 test "$(token MCP_GRAFANA_SERVER_TOKEN)" = "$before"
check reinstall-resets-role-to-viewer 10 sa_is_viewer
check reinstall-still-answers      60 mcp_init
check reinstall-queries-work       60 prom_call_ok
make --no-print-directory uninstall-mcp >"$WORK/uninstall-mcp.log" 2>&1 || { tail -30 "$WORK/uninstall-mcp.log"; die "make uninstall-mcp failed"; }
check uninstall-removes-container  10 test -z "$(docker ps -aq --filter name=^oib-mcp-grafana$)"
check uninstall-removes-tokens      1 test ! -e "$SECRETS"
check host-secrets-unchanged        1 host_secrets_unchanged

summary
