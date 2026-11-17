#!/usr/bin/env bash
# Write known data into every OIB backend and read it back.
# Sourced by the test scripts after lib.sh; needs load_endpoints to have run.
# shellcheck disable=SC2154  # endpoint variables come from lib.sh
#
# A "run" is identified by RUN (8 hex chars). Seeding a run writes:
#   Loki       a log line  {job="oib-acceptance", run="$RUN"}  "oib-acceptance-marker $RUN"
#   Tempo      one span with a fixed trace ID, service.name=oib-acceptance-$RUN (via Alloy OTLP)
#   Pyroscope  a CPU profile for application oib-acceptance-$RUN
#   Grafana    a dashboard with uid oib-acc-$RUN
#   Prometheus nothing is written; SEED_TIME is recorded and the TSDB must
#              still hold samples of up{job="prometheus"} at that instant.

hex() { od -An -tx1 -N"$(( $1 / 2 ))" /dev/urandom | tr -d ' \n'; }  # hex N -> N hex chars

# ---------- writers ----------

seed_loki() { # RUN
  local ns; ns="$(date +%s)000000000"
  curl -fsS -o /dev/null -X POST "$LOKI/loki/api/v1/push" -H 'Content-Type: application/json' \
    -d "{\"streams\":[{\"stream\":{\"job\":\"oib-acceptance\",\"run\":\"$1\"},\"values\":[[\"$ns\",\"oib-acceptance-marker $1\"]]}]}"
}

seed_trace() { # RUN TRACE_ID
  local now span; now=$(date +%s); span=$(hex 16)
  curl -fsS -o /dev/null -X POST "$OTLP/v1/traces" -H 'Content-Type: application/json' -d "{
    \"resourceSpans\": [{
      \"resource\": {\"attributes\": [{\"key\": \"service.name\", \"value\": {\"stringValue\": \"oib-acceptance-$1\"}}]},
      \"scopeSpans\": [{\"spans\": [{
        \"traceId\": \"$2\", \"spanId\": \"$span\", \"name\": \"acceptance-span\", \"kind\": 2,
        \"startTimeUnixNano\": \"$((now - 1))000000000\", \"endTimeUnixNano\": \"${now}000000000\"
      }]}]
    }]
  }"
}

seed_profile() { # RUN
  local now; now=$(date +%s)
  curl -fsS -o /dev/null -X POST \
    "$PYRO/ingest?name=oib-acceptance-$1.cpu&from=$((now - 10))&until=$now&format=folded&sampleRate=100&spyName=gospy" \
    --data-binary $'main;acceptance;work 100\nmain;acceptance;idle 50'
}

seed_grafana() { # RUN
  curl -fsS -o /dev/null -u "$GRAFANA_AUTH" -X POST "$GRAFANA/api/dashboards/db" -H 'Content-Type: application/json' \
    -d "{\"dashboard\":{\"uid\":\"oib-acc-$1\",\"title\":\"oib-acceptance $1\",\"panels\":[],\"schemaVersion\":39},\"overwrite\":true}"
}

# ---------- readers (succeed only when the data is there) ----------

has_log() { # RUN
  local start=$(( $(date +%s) - 86400 ))
  curl -fsS -G "$LOKI/loki/api/v1/query_range" --data-urlencode "query={job=\"oib-acceptance\",run=\"$1\"}" \
    --data-urlencode "start=${start}000000000" --data-urlencode 'limit=10' \
    | jq -e --arg m "oib-acceptance-marker $1" '[.data.result[].values[][1]] | index($m) != null' >/dev/null
}

has_trace_by_id() { # RUN TRACE_ID
  curl -fsS "$TEMPO/api/v2/traces/$2" \
    | jq -e --arg s "oib-acceptance-$1" '[.. | objects | select(.key? == "service.name") | .value.stringValue] | index($s) != null' >/dev/null
}

has_trace_in_search() { # RUN
  local now; now=$(date +%s)
  curl -fsS -G "$TEMPO/api/search" --data-urlencode "q={resource.service.name=\"oib-acceptance-$1\"}" \
    --data-urlencode "start=$((now - 86400))" --data-urlencode "end=$now" \
    | jq -e '(.traces | length) > 0' >/dev/null
}

has_profile() { # RUN
  local now; now=$(date +%s)
  curl -fsS -X POST "$PYRO/querier.v1.QuerierService/LabelValues" -H 'Content-Type: application/json' \
    -d "{\"name\":\"service_name\",\"start\":$(( (now - 86400) * 1000 )),\"end\":$(( now * 1000 ))}" \
    | jq -e --arg s "oib-acceptance-$1" '(.names // []) | index($s) != null' >/dev/null
}

has_dashboard() { # RUN
  curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/dashboards/uid/oib-acc-$1" >/dev/null
}

has_prom_history() { # SEED_TIME
  curl -fsS -G "$PROM/api/v1/query" --data-urlencode 'query=count_over_time(up{job="prometheus"}[2m])' \
    --data-urlencode "time=$1" | jq -e '(.data.result[0].value[1] // "0" | tonumber) > 0' >/dev/null
}

# ---------- functional checks for the running stack ----------

datasources_healthy() { # [with-profiling]
  local uids="prometheus loki tempo" uid
  [ "${1:-}" = with-profiling ] && uids="$uids pyroscope"
  for uid in $uids; do
    curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/datasources/uid/$uid/health" | jq -e '.status == "OK"' >/dev/null || return 1
  done
}

dashboards_provisioned() {
  local expected; expected=$(find "$ROOT/grafana/provisioning/dashboards/json" -name '*.json' | wc -l)
  curl -fsS -u "$GRAFANA_AUTH" "$GRAFANA/api/search?type=dash-db&limit=500" \
    | jq -e --argjson n "$expected" '[.[] | select(.title | test("^OIB"))] | length >= $n' >/dev/null
}

prom_rules_loaded() {
  curl -fsS "$PROM/api/v1/rules" \
    | jq -e '[.data.groups[].rules[]] | (length > 0) and all(.health != "err")' >/dev/null
}

prom_targets_up() {
  curl -fsS "$PROM/api/v1/targets?state=active" \
    | jq -e '(.data.activeTargets | length) > 0 and all(.data.activeTargets[]; .health == "up")' >/dev/null
}

host_metrics_flowing() {
  curl -fsS -G "$PROM/api/v1/query" --data-urlencode 'query=(time() - max(timestamp(node_cpu_seconds_total))) < 120' \
    | jq -e '(.data.result | length) > 0' >/dev/null
}

container_logs_flowing() { # logs Alloy collected from the Docker socket in the last 3 minutes
  local start=$(( $(date +%s) - 180 ))
  curl -fsS -G "$LOKI/loki/api/v1/query_range" --data-urlencode 'query={container_name=~"oib-.+"}' \
    --data-urlencode "start=${start}000000000" --data-urlencode 'limit=1' \
    | jq -e '(.data.result | length) > 0' >/dev/null
}

# Every running OIB container belongs to a service of the current compose files
# and runs the image those files specify (no orphans, nothing left on an old image).
containers_current() {
  local d want have line
  for d in grafana logging metrics telemetry profiling; do
    want=$(cd "$ROOT/$d" && docker compose --env-file "$ENV_FILE" --profile '*' config --format json \
           | jq -r '.services | to_entries[] | "\(.key)=\(.value.image)"') || return 1
    have=$(docker ps --filter "label=com.docker.compose.project=oib-$d" \
           --format '{{.Label "com.docker.compose.service"}}={{.Image}}')
    for line in $have; do
      printf '%s\n' "$want" | grep -qxF "$line" || { echo "stale or orphaned container: oib-$d $line" >&2; return 1; }
    done
  done
}

# ---------- run-level helpers ----------

# seed_run STATE_FILE [with-profiling]: write a new run and wait until it is readable
seed_run() {
  local state=$1 prof=${2:-} run trace
  run=$(hex 8); trace=$(hex 32)
  log "seeding run $run (trace $trace)"
  retry 60 has_prom_history "$(date +%s)" || die "Prometheus has no samples of up{job=\"prometheus\"} yet"
  seed_loki "$run" || die "Loki push failed"
  seed_trace "$run" "$trace" || die "OTLP trace export failed"
  seed_grafana "$run" || die "Grafana dashboard create failed"
  [ "$prof" = with-profiling ] && { seed_profile "$run" || die "Pyroscope ingest failed"; }
  retry 60 has_log "$run" || die "seeded log line is not readable"
  retry 90 has_trace_by_id "$run" "$trace" || die "seeded trace is not readable"
  retry 30 has_dashboard "$run" || die "seeded dashboard is not readable"
  [ "$prof" = with-profiling ] && { retry 90 has_profile "$run" || die "seeded profile is not readable"; }
  sleep 2
  cat >"$state" <<EOF
RUN=$run
TRACE_ID=$trace
SEED_TIME=$(date +%s)
PROFILING=$prof
EOF
  log "seed verified readable; state in $state"
}

# verify_persisted STATE_FILE: the seeded run survived (backup/restore or upgrade)
verify_persisted() {
  # shellcheck disable=SC1090
  . "$1"
  local t=${VERIFY_TIMEOUT:-120}
  check loki-data         "$t" has_log "$RUN"
  check prometheus-history "$t" has_prom_history "$SEED_TIME"
  check tempo-by-id       "$t" has_trace_by_id "$RUN" "$TRACE_ID"
  check tempo-search      "$t" has_trace_in_search "$RUN"
  check grafana-dashboard "$t" has_dashboard "$RUN"
  [ "$PROFILING" = with-profiling ] && check pyroscope-data "$t" has_profile "$RUN"
  return 0
}

# verify_absent STATE_FILE: control - on fresh volumes the seeded run must be missing
verify_absent() {
  # shellcheck disable=SC1090
  . "$1"
  check_absent loki-data         has_log "$RUN"
  check_absent prometheus-history has_prom_history "$SEED_TIME"
  check_absent tempo-by-id       has_trace_by_id "$RUN" "$TRACE_ID"
  check_absent grafana-dashboard has_dashboard "$RUN"
  [ "$PROFILING" = with-profiling ] && check_absent pyroscope-data has_profile "$RUN"
  return 0
}

# verify_functional [with-profiling]: the running stack works end to end
verify_functional() {
  local prof=${1:-} t=${VERIFY_TIMEOUT:-120} run trace
  check datasources-healthy    "$t" datasources_healthy "$prof"
  check dashboards-provisioned "$t" dashboards_provisioned
  check prometheus-rules       "$t" prom_rules_loaded
  check prometheus-targets-up  "$t" prom_targets_up
  check host-metrics-flowing   "$t" host_metrics_flowing
  check container-logs-flowing "$t" container_logs_flowing
  check containers-current     30   containers_current
  run=$(hex 8); trace=$(hex 32)
  seed_loki "$run" || true
  seed_trace "$run" "$trace" || true
  check live-logs   "$t" has_log "$run"
  check live-traces "$t" has_trace_by_id "$run" "$trace"
  if [ "$prof" = with-profiling ]; then
    seed_profile "$run" || true
    check live-profiles "$t" has_profile "$run"
  fi
}
