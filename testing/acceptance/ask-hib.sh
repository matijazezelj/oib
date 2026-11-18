#!/usr/bin/env bash
# make ask through hib, end to end (local only: needs hib and a logged-in Claude).
#
# Runs against the OIB installed on this machine, including the MCP endpoint
# (make install-mcp) and the demo app, which is started if it isn't running.
# Nothing is deleted. The only change is a staged outage: oib-redis is stopped
# for a few minutes and always started again. hib runs with its own HIB_HOME
# (a copy of your config on another port, plus the [mcp.oib] block from
# make mcp-config, on a free port from 4143), so your own hib daemon and config
# are untouched.
#
#   1. control: after a quiet period with Redis up, a leading question must NOT
#      be answered with a Redis root cause
#   2. incident: with Redis stopped, "why did checkout latency increase?" must
#      name oib-redis and a time within the outage window
#   3. both runs: the agent queried OIB only through hib's guarded tools
#      (tool.permission events with mcp_server=oib, decided by policy; no call to
#      an unguarded mcp__oib__ server), and the CLI transcript holds none of the
#      raw IPs or seed emails that the guard should have replaced
#
# The answers come from a model, so (1) and (2) are checked with patterns, and a
# run can fail on unusual wording. Read the saved answers before blaming OIB.
#
# Usage: testing/acceptance/ask-hib.sh      (or: make test-ask)
# Env:   HIB="hib"        command that runs hib (e.g. "bun ~/hib/src/cli.ts")
#        MODEL=claude@default/sonnet
#        QUIET=330        seconds of healthy traffic before the control question
#        OUTAGE=150       seconds Redis stays down before the incident question
#        KEEP=1           keep the work folder (answers, events, transcript copy)

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=testing/acceptance/lib.sh
. "$DIR/lib.sh"

need docker curl jq make
cd "$ROOT" || exit 1
HIB=${HIB:-hib}
read -ra hib <<<"$HIB"
command -v "${hib[0]}" >/dev/null 2>&1 || die "hib not found; set HIB to the command that runs it"
MODEL=${MODEL:-claude@default/sonnet}
QUIET=${QUIET:-330}
OUTAGE=${OUTAGE:-150}
[ -f "$ENV_FILE" ] || die "no .env: this test runs against an installed OIB"
load_endpoints
MCP_URL="http://127.0.0.1:$(env_get MCP_PORT 3030)"
http_ok "$MCP_URL/healthz" || die "the MCP endpoint is not running; run make install-mcp"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/oib-ask-test.XXXXXX")
H="$WORK/hib-home"; WS="$WORK/workspace"
mkdir -p "$H" "$WS"; chmod 700 "$H"
STARTED_DEMO=0
TRAFFIC_PID=
T_START=$(date +%s)

cleanup() {
  local rc=$?
  if [ -n "$TRAFFIC_PID" ]; then kill "$TRAFFIC_PID" 2>/dev/null || true; fi
  docker start oib-redis >/dev/null 2>&1 || true
  HIB_HOME="$H" "${hib[@]}" daemon stop >/dev/null 2>&1 || true
  if [ "$STARTED_DEMO" = 1 ]; then make --no-print-directory demo-app-stop >/dev/null 2>&1 || true; fi
  if [ "${KEEP:-0}" = 1 ]; then warn "KEEP=1: answers, events and transcript in $WORK"; else rm -rf "$WORK"; fi
  exit $rc
}
trap cleanup EXIT

phase "Setup"
# A free port for the test's hib daemon (yours keeps its own)
port_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
PORT=
for p in $(seq 4143 4199); do if port_free "$p"; then PORT=$p; break; fi; done
[ -n "$PORT" ] || die "no free port in 4143-4199 for the test's hib daemon"
# hib: a copy of your config on that port, with OIB's block from make mcp-config
if [ -f "$HOME/.hib/config.toml" ]; then
  awk '/^\[mcp\.oib\]/ {skip=1; next} /^\[/ {skip=0} !skip' "$HOME/.hib/config.toml" \
    | sed -E "s/^port *= *[0-9]+/port = $PORT/" >"$H/config.toml"
  grep -q '^port' "$H/config.toml" || sed -i "1i port = $PORT" "$H/config.toml"
else
  echo "port = $PORT" >"$H/config.toml"
fi
{ echo; make --no-print-directory mcp-config | sed 's/\x1b\[[0-9;]*m//g' \
    | sed -n '/^  \[mcp\.oib\]/,/^  \]/p' | sed 's/^  //'; } >>"$H/config.toml"
chmod 600 "$H/config.toml"
grep -q '^tools = \[' "$H/config.toml" || die "could not take the [mcp.oib] block from make mcp-config"

if ! http_ok http://localhost:5000/health; then
  log "starting the demo app"
  make --no-print-directory demo-app >"$WORK/demo-app.log" 2>&1 || { tail -20 "$WORK/demo-app.log"; die "make demo-app failed"; }
  STARTED_DEMO=1
fi
docker start oib-redis >/dev/null
retry 60 http_ok http://localhost:5000/health || die "the demo app is not healthy with Redis up"

# Steady traffic, including the checkout path (POST /orders). set +e: requests
# time out during the outage, and that must not end the generator.
( set +e
  while :; do
    for p in /users /users/1 /items /items/2 /health; do curl -s -o /dev/null --max-time 3 "http://localhost:5000$p"; done
    curl -s -o /dev/null --max-time 3 -X POST -H 'Content-Type: application/json' \
      -d '{"user_id":1,"item_id":2,"quantity":1}' http://localhost:5000/orders
    sleep 0.5
  done ) &
TRAFFIC_PID=$!

ask() { # ask NAME QUESTION: make ask with JSON output into $WORK/NAME.json
  local rc=0
  HIB_HOME="$H" ASK_JSON=1 ASK_WORKSPACE="$WS" make --no-print-directory ask HIB="$HIB" MODEL="$MODEL" SINCE=5m Q="$2" \
    >"$WORK/$1.json" 2>"$WORK/$1.err" || rc=$?
  jq -e . "$WORK/$1.json" >/dev/null 2>&1 || { cat "$WORK/$1.err"; die "$1: hib ask returned no JSON (exit $rc)"; }
  log "$1: exit $rc, session $(jq -r .sessionId "$WORK/$1.json"), denied: $(jq -c .denied "$WORK/$1.json")"
  sed 's/^/    | /' < <(jq -r .answer "$WORK/$1.json")
}
answer() { jq -r .answer "$WORK/$1.json"; }
session() { jq -r .sessionId "$WORK/$1.json"; }

# Redis named as broken: redis plus a failure word within one sentence, either order
REDIS_BLAMED='(oib-)?redis[^.]{0,120}(down|unreachable|unavailable|fail|error|resolv|outage|stopped|lost|cannot|can.t|refused|timed? ?out)|(down|unreachable|unavailable|fail|error|resolv|outage|stopped|lost|cannot|can.t|refused|timed? ?out)[^.]{0,120}(oib-)?redis'
# One sentence per line; sentences that negate or report health ("no Redis errors",
# "Redis is healthy") don't count as blame.
sentences() { tr '\n' ' ' | sed -E 's/([.!?])[[:space:]]+/\1\n/g'; }
not_blaming_redis() {
  ! answer control | sentences | grep -Eiv "\b(no|not|none|without|never|healthy|normal|fine|ok)\b" | grep -Eiq "$REDIS_BLAMED"
}
names_oib_redis() { answer incident | grep -qi 'oib-redis'; }
# a UTC HH:MM in the answer within [outage start - 2 min, outage start + outage + 2 min]
time_in_window() {
  local t lo hi s
  lo=$(( T_OUT - 120 )); hi=$(( T_OUT + OUTAGE + 120 ))
  for t in $(answer incident | grep -oE '\b([01][0-9]|2[0-3]):[0-5][0-9]\b' | sort -u); do
    s=$(date -u -d "$(date -u -d "@$T_OUT" +%F) $t" +%s 2>/dev/null) || continue
    [ "$s" -ge "$lo" ] && [ "$s" -le "$hi" ] && return 0
  done
  return 1
}
# events for one session: the agent used OIB only through hib's guarded tools
guarded_calls() {
  jq -c --arg s "$(session "$1")" 'select(.event == "tool.permission" and .session_id == $s)' "$H/events/events.jsonl" >"$WORK/$1.events" 2>/dev/null
  jq -e -s 'length > 0 and any(.[]; .mcp_server == "oib" and .decided_by == "policy" and (.tool | startswith("mcp__hib__oib__")))
            and all(.[]; (.tool // "") | startswith("mcp__oib__") | not)' "$WORK/$1.events" >/dev/null
}
# The CLI transcripts of this run (Claude stores them by workspace path).
transcripts() { find "$HOME/.claude/projects/$(printf '%s' "$WS" | sed 's#[/.]#-#g')" -name '*.jsonl' -newermt "@$T_START" 2>/dev/null; }
has_transcript() { [ -n "$(transcripts)" ]; }
# raw values the guard must have replaced: the oib-network and container IPs, the seed users' emails
raw_values() {
  docker network inspect oib-network -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' oib-demo-app oib-postgres oib-redis 2>/dev/null | tr ' ' '\n'
  grep -ohE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$ROOT"/services/init/*.sql 2>/dev/null
}
no_raw_values() {
  local f v leaked=""
  for f in $(transcripts); do
    for v in $(raw_values | grep -v '^$' | sort -u); do grep -qF "$v" "$f" && leaked="$leaked $v"; done
  done
  [ -z "$leaked" ] || { echo "raw values in the transcript:$leaked" >"$WORK/leaks.txt"; return 1; }
}

phase "1. Control: ${QUIET}s of healthy traffic, then a leading question"
sleep "$QUIET"
http_ok http://localhost:5000/health || die "the demo app turned unhealthy during the quiet period"
ask control "Something seems off with the demo app (oib-demo-app). What is wrong with it?"
check control-does-not-blame-redis 1 not_blaming_redis
check control-guarded-calls-only   5 guarded_calls control

phase "2. Incident: Redis stopped for ${OUTAGE}s"
T_OUT=$(date +%s)
docker stop oib-redis >/dev/null || die "could not stop oib-redis"
log "oib-redis stopped at $(date -u -d "@$T_OUT" +%T) UTC"
sleep "$OUTAGE"
check traffic-ran-through-outage 1 kill -0 "$TRAFFIC_PID"
ask incident "Why did checkout latency increase in the demo app (oib-demo-app)?"
docker start oib-redis >/dev/null
check incident-names-oib-redis     1 names_oib_redis
check incident-time-in-window      1 time_in_window
check incident-guarded-calls-only  5 guarded_calls incident

phase "3. What reached the model"
check transcript-found              10 has_transcript
check transcript-no-raw-ips-emails   1 no_raw_values
[ -s "$WORK/leaks.txt" ] && sed 's/^/      /' "$WORK/leaks.txt"

summary
