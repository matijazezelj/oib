# Shell Completions for OIB

Tab-completion for `make` targets in the OIB directory.

## Zsh

`_oib` is an autoloaded completion function (`#compdef make`). Put it on
`$fpath` under the name `_oib` and let `compinit` pick it up. Do not name it
`_make` (it calls the stock `_make` outside OIB and would recurse), and do not
`source` it (that runs the completion body once at shell start instead of
registering it).

```bash
# Option 1: Copy to your completions directory
mkdir -p ~/.zsh/completions
cp completions/_oib ~/.zsh/completions/_oib
# Add these lines to ~/.zshrc, before any existing compinit call:
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit

# Option 2: Use it from the checkout (add to ~/.zshrc, before compinit)
fpath=(/path/to/oib/completions $fpath)
```

If completion does not change, clear the cache: `rm -f ~/.zcompdump*` and start a new shell.

## Bash

```bash
# Add to your .bashrc
echo 'source /path/to/oib/completions/oib.bash' >> ~/.bashrc
source ~/.bashrc
```

The bash script replaces the `make` completion handler. Outside an OIB checkout it falls back to bash-completion's stock `make` completion (loaded first if bash-completion is installed), or to file names if that is not available.

## Usage

In the OIB directory, type `make ` and press Tab:

```bash
$ make install-<TAB>
install-grafana    install-logging    install-metrics    install-profiling  install-services   install-telemetry

$ make logs<TAB>
logs           logs-grafana   logs-logging   logs-metrics   logs-profiling logs-services  logs-telemetry
```

## How it works

- OIB targets are offered only when the current directory contains a `Makefile` with the text "Observability in a Box", i.e. in the repo root. In subdirectories, or with `make -C /path/to/oib`, you get the normal `make` completion.
- The target lists are static (written into `_oib` and `oib.bash`), not read from the Makefile. They cover every documented target; when a target is added to the Makefile, add it to both files. Zsh also shows a short description per target.
- Arguments such as `FILE=` for `restore-*` are not completed.
