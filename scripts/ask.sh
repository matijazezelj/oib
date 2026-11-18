#!/usr/bin/env bash
# make ask: ask an LLM about OIB's data through hib (https://github.com/matijazezelj/hib).
#
# Runs one hib agent turn (`hib ask --workspace`) with the question and the time
# window. The agent investigates through hib's trusted, read-only OIB MCP tools
# (Loki, Prometheus, Tempo, Pyroscope): hib calls the endpoint itself, guards
# every result before it reaches the model, and denies anything that would need
# a prompt. Needs `make install-mcp` and the [mcp.oib] block from `make mcp-config`
# in hib's config.
#
# Usage: scripts/ask.sh "question"        (or: make ask Q="question")
# Env:   SINCE=1h      window to investigate: <n>m, <n>h or <n>d
#        MODEL=        hib model, e.g. claude@default/sonnet (default: hib picks)
#        HIB=hib       command that runs hib (e.g. "bun /path/to/hib/src/cli.ts")
#        ASK_JSON=1    print hib's JSON result ({sessionId, answer, denied, errors, exit})
#        ASK_WORKSPACE folder the agent runs in (default: an empty cache folder; never
#                      this checkout, which holds mcp/secrets)
#        MCP_URL       the OIB MCP endpoint (the Makefile passes it)
# Exit:  hib's: 0 answered, 3 answered but something that would have asked was denied, 1 error
set -euo pipefail

SINCE=${SINCE:-1h}
HIB=${HIB:-hib}
MCP_URL=${MCP_URL:-http://127.0.0.1:3030}
WORKDIR=${ASK_WORKSPACE:-${XDG_CACHE_HOME:-$HOME/.cache}/oib-ask}
QUESTION=${1:-}
[ -n "$QUESTION" ] || QUESTION="Is anything wrong or unusual? Summarise the health of the stack and the services it observes."

die() { echo "ask: $*" >&2; exit 1; }
case "$SINCE" in
  [1-9]*m|[1-9]*h|[1-9]*d) [[ "$SINCE" =~ ^[0-9]+[mhd]$ ]] || die "SINCE must look like 15m, 1h or 2d" ;;
  *) die "SINCE must look like 15m, 1h or 2d, not '$SINCE'" ;;
esac
case "${MODEL:-}" in *[!A-Za-z0-9@/._:-]*) die "MODEL has unexpected characters" ;; esac

read -ra hib <<<"$HIB"
command -v "${hib[0]}" >/dev/null 2>&1 \
  || die "hib is not installed (https://github.com/matijazezelj/hib), or set HIB to the command that runs it"
curl -fsS --max-time 5 -o /dev/null "$MCP_URL/healthz" 2>/dev/null \
  || die "the OIB MCP endpoint is not running at $MCP_URL; run make install-mcp"
cfg="${HIB_HOME:-$HOME/.hib}/config.toml"
if [ -f "$cfg" ] && ! grep -q '^\[mcp\.oib\]' "$cfg"; then
  echo "ask: warning: $cfg has no [mcp.oib] block, so the agent has no OIB tools; add the one make mcp-config prints and restart hib's daemon" >&2
fi

now=$(date -u '+%Y-%m-%d %H:%M UTC')
prompt="$QUESTION

Investigate this with the oib MCP tools only: Loki logs, Prometheus metrics, Tempo traces and Pyroscope profiles of the OIB observability stack. Look at the last $SINCE, up to now ($now). Do not read, search or change local files.
Answer with:
1. What happened, or plainly that nothing looks wrong.
2. When it started and whether it is still going on, in UTC.
3. The evidence: the log lines, metrics or traces you relied on.
4. What to check next.
Say so when the data is not enough to tell."

mkdir -p "$WORKDIR"
args=(ask --workspace "$WORKDIR")
[ -n "${MODEL:-}" ] && args+=(-m "$MODEL")
[ "${ASK_JSON:-0}" = 1 ] && args+=(--json)
set +e
"${hib[@]}" "${args[@]}" "$prompt"
rc=$?
set -e
[ "$rc" = 3 ] && echo "ask: hib denied something the agent tried that would have needed your approval (see hib's timeline)" >&2
exit "$rc"
