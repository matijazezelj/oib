# Acceptance Tests

Two end-to-end tests that boot the real stacks and prove that user data survives the operations that put it at risk: backup/restore and upgrades.

> ⚠️ Both tests **delete every OIB volume**. They refuse to start when OIB containers or volumes already exist. Run them on a disposable host (a CI runner, a throwaway VM, or a laptop without an OIB install). `OIB_TEST_FORCE=1` overrides the check and wipes the existing install.

```bash
make test-backup                  # backup -> wipe -> restore round trip
make test-upgrade                 # upgrade from the latest release tag
make test-upgrade FROM=v1.0.0     # upgrade from a specific release
```

Requirements: Docker with Compose v2, `curl`, `jq`, `make`, `git` (and the release tags: `git fetch --tags`). The default OIB ports must be free. A run takes 5 to 10 minutes, mostly pulling images and waiting for Pyroscope, which takes about 70 s to report ready. If there is no `.env`, a temporary one with a random Grafana password is created and removed afterwards.

## What is checked

Both tests write a uniquely tagged **run** of known data and verify it later:

| Check | Data written | Verified by |
|---|---|---|
| `loki-data` | a log line `{job="oib-acceptance", run="<id>"}` pushed to Loki | LogQL query returns the marker line |
| `prometheus-history` | nothing; the seed time is recorded | `up{job="prometheus"}` has samples at the seed time (a fresh TSDB cannot) |
| `tempo-by-id` | one span with a fixed trace ID, sent over OTLP/HTTP to Alloy | `GET /api/v2/traces/<id>` returns it |
| `tempo-search` | same span | TraceQL search by `service.name` finds it |
| `grafana-dashboard` | a dashboard saved through the Grafana API | fetched again by UID |
| `pyroscope-data` | a CPU profile ingested into Pyroscope | `service_name` label value is listed |

Then the running stack is checked end to end:

| Check | Meaning |
|---|---|
| `datasources-healthy` | Grafana's Prometheus, Loki, Tempo and Pyroscope datasources report OK |
| `dashboards-provisioned` | every dashboard in `grafana/provisioning/dashboards/json` is loaded |
| `prometheus-rules` | alert rules are loaded without errors |
| `prometheus-targets-up` | every scrape target is up |
| `host-metrics-flowing` | `node_cpu_seconds_total` is fresh (Alloy → Prometheus) |
| `container-logs-flowing` | Alloy is shipping container logs from the Docker socket |
| `containers-current` | every running OIB container belongs to a current service and runs the image the compose files pin (no orphans, nothing left on an old image) |
| `live-logs`, `live-traces`, `live-profiles` | newly written data is readable |

Checks retry for up to 120 s (`VERIFY_TIMEOUT`), because data takes a few seconds to become queryable.

## `backup-roundtrip.sh` (`make test-backup`)

1. `make install` and `make install-profiling`, then wait until every endpoint is ready.
2. Seed a run and confirm it is readable.
3. `make backup` into a temporary directory. Every archive must exist and be owned by the invoking user.
4. Delete every volume, reinstall on fresh volumes.
5. **Control:** the seeded data must now be missing. This proves the checks can fail and that the later pass comes from the restore.
6. `make restore-all STAMP=... YES=1`.
7. The data checks and functional checks must pass.

## `upgrade.sh` (`make test-upgrade FROM=<tag>`)

1. Check out `<tag>` in a temporary git worktree and install it from there, including profiling.
2. Seed a run on the old release.
3. Upgrade the way users do: `make update` and `make update-profiling` from the current checkout.
4. The data checks and functional checks must pass.

Losses that are known and accepted for a starting release are listed in [`upgrade-expectations`](upgrade-expectations). They are reported as `XFAIL` and do not fail the run. If a listed check passes, it is reported as `XPASS`; remove it from the list. Any loss not listed fails the test.

## Debugging

`KEEP=1 make test-backup` (or `test-upgrade`) leaves the stack running and keeps the temporary directory (backups, logs, `state` with the run ID and trace ID). Clean up afterwards with `make uninstall-profiling; make uninstall YES=1`.

## CI

[`.github/workflows/acceptance.yml`](../../.github/workflows/acceptance.yml) runs the backup round trip and the upgrade test from every release in its matrix on pull requests that touch compose files, configs, dashboards, the Makefile or these tests, and on pushes to `main`. When you cut a release, add its tag to the matrix.
