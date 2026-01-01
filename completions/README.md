# Shell Completions for OIB

Tab-completion for `make` targets in the OIB directory.

## Zsh

```bash
# Option 1: Copy to your completions directory
mkdir -p ~/.zsh/completions
cp completions/_oib ~/.zsh/completions/_make
echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
autoload -Uz compinit && compinit

# Option 2: Source directly (simpler)
echo 'source /path/to/oib/completions/_oib' >> ~/.zshrc
```

## Bash

```bash
# Add to your .bashrc
echo 'source /path/to/oib/completions/oib.bash' >> ~/.bashrc
source ~/.bashrc
```

## Usage

In the OIB directory, type `make ` and press Tab:

```bash
$ make install-<TAB>
install-grafana    install-logging    install-metrics    install-profiling  install-telemetry

$ make log<TAB>
logs           logs-grafana   logs-logging   logs-metrics   logs-profiling logs-telemetry
```
