#!/bin/bash
# OIB Makefile completions for bash
# Install: source completions/oib.bash (add to ~/.bashrc)

# Load the stock make completion first (bash-completion loads it lazily), so we
# can fall back to it outside an OIB checkout instead of disabling it.
if declare -F _comp_load >/dev/null; then
    _comp_load make >/dev/null 2>&1
elif declare -F _completion_loader >/dev/null; then
    _completion_loader make >/dev/null 2>&1
fi

_oib_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    # Check if we're in OIB directory
    if [[ -f Makefile ]] && grep -q "Observability in a Box" Makefile 2>/dev/null; then
        local targets="install install-grafana install-logging install-metrics install-telemetry install-profiling install-services install-mcp mcp-config logs-mcp \
            preflight network \
            start stop restart status info logs \
            start-grafana stop-grafana restart-grafana logs-grafana info-grafana \
            start-logging stop-logging restart-logging logs-logging info-logging \
            start-metrics stop-metrics restart-metrics logs-metrics info-metrics \
            start-telemetry stop-telemetry restart-telemetry logs-telemetry info-telemetry \
            start-profiling stop-profiling restart-profiling logs-profiling info-profiling \
            start-services stop-services restart-services logs-services info-services \
            health doctor check-ports ps validate \
            demo demo-app demo-app-stop demo-traffic demo-examples \
            test-load test-stress test-spike test-api test-backup test-upgrade test-tempo-recovery test-mcp test-isolation test-restricted \
            open disk-usage version bootstrap \
            update update-grafana update-logging update-metrics update-telemetry update-profiling latest clean \
            backup backup-prometheus backup-loki backup-tempo backup-grafana backup-pyroscope \
            restore restore-all restore-prometheus restore-loki restore-tempo restore-grafana restore-pyroscope \
            migrate-grafana-volume migrate-tempo rollback-tempo \
            uninstall uninstall-grafana uninstall-logging uninstall-metrics uninstall-telemetry uninstall-profiling uninstall-services uninstall-mcp \
            help"
        COMPREPLY=($(compgen -W "$targets" -- "$cur"))
    elif declare -F _comp_cmd_make >/dev/null; then
        _comp_cmd_make "$@"
    elif declare -F _make >/dev/null; then
        _make "$@"
    else
        COMPREPLY=($(compgen -f -- "$cur"))
    fi
}

complete -F _oib_completions make
