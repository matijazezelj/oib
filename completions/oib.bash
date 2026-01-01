#!/bin/bash
# OIB Makefile completions for bash
# Install: source completions/oib.bash (add to ~/.bashrc)

_oib_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    # Check if we're in OIB directory
    if [[ -f Makefile ]] && grep -q "Observability in a Box" Makefile 2>/dev/null; then
        local targets="install install-grafana install-logging install-metrics install-telemetry install-profiling \
            start stop restart status info logs \
            start-grafana stop-grafana restart-grafana logs-grafana \
            start-logging stop-logging restart-logging logs-logging \
            start-metrics stop-metrics restart-metrics logs-metrics \
            start-telemetry stop-telemetry restart-telemetry logs-telemetry \
            start-profiling stop-profiling restart-profiling logs-profiling \
            health doctor check-ports ps validate \
            demo demo-app demo-traffic test-load \
            open disk-usage version bootstrap \
            update update-grafana update-logging update-metrics update-telemetry update-profiling latest clean \
            uninstall uninstall-grafana uninstall-logging uninstall-metrics uninstall-telemetry uninstall-profiling \
            help"
        COMPREPLY=($(compgen -W "$targets" -- "$cur"))
    fi
}

complete -F _oib_completions make
