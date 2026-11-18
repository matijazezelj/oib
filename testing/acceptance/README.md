# Acceptance Tests

End-to-end tests that boot the real stacks. They prove that user data survives the operations that put it at risk (backup/restore, upgrades, the Tempo migration), and that restricted mode keeps its promises.

> ⚠️ Both tests **delete every OIB volume** of the Docker daemon they run against. Run directly, they refuse to start when OIB containers or volumes already exist (`OIB_TEST_FORCE=1` overrides that and wipes the install). On a machine with an OIB install, use `ISOLATED=1`.

```bash
make test-backup ISOLATED=1               # in a throwaway Docker-in-Docker daemon (safe next to an install)
make test-upgrade FROM=v1.0.0 ISOLATED=1
make test-backup                          # directly on this host's daemon (CI, clean hosts)
make test-upgrade                         # upgrade from the latest release tag
```

### Isolated mode (`ISOLATED=1`)

[`isolated.sh`](isolated.sh) starts a privileged `docker:dind` container and runs the test in a small runner container that shares its network namespace. Containers, volumes, the `oib-network` network and the published ports of the test all live inside that inner daemon, so an OIB install on the host is never touched and its ports do not need to be free. Details:
- The inner daemon's API listens on 127.0.0.1 inside the dind container only. It uses its own address ranges, so a DNS server on the host bridge (`172.17.0.1`) stays reachable.
- Its image cache is kept in the volume `oibtest-dind-cache`, so later runs skip most pulls. Set `DIND_KEEP_CACHE=0` to drop it, or remove it with `docker volume rm oibtest-dind-cache`.
- The repository is mounted at the same path inside, and the test's temporary files live in a scratch volume, so bind mounts in the compose files resolve. If there is no `.env`, a temporary one is created in the checkout and removed afterwards.
- Requires Docker with privileged containers allowed. `KEEP=1` has no effect here, because the inner daemon is removed at the end.
- **One isolated run at a time.** Both runs would use the same image cache.
  - The lock is a container named `oibtest-lock`, which Docker creates atomically, so two runs started at the same moment cannot both get it.
  - A lock left by a run killed with `kill -9` is recognised (its PID is gone). The next run removes it and that run's leftovers.
- **Leftover state is cleared at the start of each run.** The cache volume keeps only images; containers, volumes and networks that an interrupted run left inside the inner daemon are removed.
- **Cleanup after an interrupt:** Ctrl+C or SIGTERM removes the inner daemon, the test container, the scratch volume, the lock and a `.env` the run created. `kill -9` cannot clean up. The next isolated run removes its containers and volumes, but a `.env` it created stays in the checkout.
- `make test-isolation` checks all of this: concurrent start, Ctrl+C, `kill -9` and stale-lock takeover, and that the host's OIB install, `.env` and git worktrees are unchanged.

Requirements: Docker with Compose v2, `curl`, `jq`, `make`, `git` (and the release tags: `git fetch --tags`). The default OIB ports must be free. With images cached, a run takes about 4 minutes. Each phase header shows the elapsed seconds. Locally, the upgrade from a Tempo 2 release (v1.0.0) skips the final Tempo search check, which needs about 15 minutes; set `OIB_TEST_FULL=1` to wait for it. CI always does. If there is no `.env`, a temporary one with a random Grafana password is created and removed afterwards.

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
3. **Failure handling:** each case must leave Loki unpaused and no archive behind.
   - A backup whose `tar` fails must exit non-zero.
   - A backup interrupted with Ctrl+C (SIGINT to the process group) must clean up.
   - A backup killed with `kill -9` must be healed by the next backup.
4. `make backup` into a temporary directory **while a background writer keeps pushing logs and spans**, recording each write the backend acknowledged and when each component's backup started. Every archive must exist and be owned by the invoking user.
5. Delete every volume, reinstall on fresh volumes.
6. **Control:** the seeded data must now be missing. This proves the checks can fail and that the later pass comes from the restore.
7. `make restore-all STAMP=... YES=1`.
8. **Clean recovery and no lost writes:**
   - `restore-clean-recovery`: no restored component may log corruption, repair, checksum or WAL replay errors while starting from the archive. The exception is a short, documented list of messages where a component recovers by itself from a derived file caught mid-write (`RECOVERY_SELF_HEALING` in `data.sh`). These are printed as notes, and the data checks still decide whether anything was lost.
   - `loki-load-before-backup`: every log line Loki acknowledged before its freeze must be back.
   - `tempo-load-before-backup`: every trace sent more than 10 s before Tempo's freeze must open by ID. The 10 s allow for Alloy's batching.
9. The data checks and functional checks must pass.

`make backup` freezes most containers with `docker pause` while archiving their volumes. That gives a crash-consistent copy, not an application-coordinated one: no database checkpoint or buffer flush happens first. The restore is only proven by restoring. Steps 4, 8 and 9 do that with archives taken under write load. Tempo logs `failed to replay block. removing.` on every restart for the empty block it creates while shutting down, so that message is not treated as an error. Data loss is detected by step 8's checks of acknowledged writes, not from logs.

## `upgrade.sh` (`make test-upgrade FROM=<tag>`)

1. Check out `<tag>` in a temporary git worktree and install it from there, including profiling.
2. Seed a run on the old release.
3. If the old release runs Tempo 2, check the migration path first:
   - `make update` must refuse, and Tempo must stay on 2.x.
   - `make migrate-tempo` must succeed while a background writer keeps sending traces, and every trace Alloy accepted must open by ID afterwards (`tempo-migration-load`).
   - The `tempo-search` check then waits until the seeded trace is 16 minutes old, because Tempo 3 searches blocks only for data older than 15 minutes. This adds about 10 minutes to the run.
4. Upgrade the way users do: `make update` and `make update-profiling` from the current checkout.
5. The data checks and functional checks must pass. Nothing is lost.
6. Run `make update` a second time. It must not print the Grafana migration warning, and the seeded dashboard must still be there.

Losses that are known and accepted for a starting release are listed in [`upgrade-expectations`](upgrade-expectations). They are reported as `XFAIL` and do not fail the run. If a listed check passes, it is reported as `XPASS`; remove it from the list. Any loss not listed fails the test.

## `tempo-migration-recovery.sh` (`make test-tempo-recovery`)

Installs the telemetry stack of a Tempo 2 release (`FROM`, default v1.0.0) and drives `make migrate-tempo` through its failure cases:
1. **Unavailable image:** the migration aborts, and Tempo 2 is unchanged and still accepts traces.
2. **Broken new config:** the dry run catches it, and Tempo 2 is unchanged and still accepts traces. No dry-run container is left behind.
3. **Interrupted after `/shutdown`:** Tempo 2 is up but its ingester is stopped, and a trace sent meanwhile waits in Alloy's queue. Rerunning `make migrate-tempo` completes, and every trace, including the queued one, opens by ID on Tempo 3.
4. **`make rollback-tempo`:** Tempo 2 is back with its pre-migration traces and accepts new ones. Migrating again keeps those traces as well.

## `restricted.sh` (`make test-restricted`)

Checks restricted mode (`OIB_MODE=restricted`, see [restricted mode](../../docs/production-hardening.md#restricted-mode)):
1. Installs every stack, including profiling, in restricted mode, and writes a run of known data.
2. **Invariant**, checked with `docker inspect` on every running `oib-*` container, so new services are covered automatically:
   - no Docker socket;
   - no bind mount of `/`, `/run`, `/var/run` or `/var/lib/docker`;
   - no added capability, privileged mode, devices, host PID or host network;
   - `/proc` and `/sys` only read-only.

   `oib-cadvisor` and `oib-alloy-logging` must not exist, and Prometheus must have no `cadvisor` target. Alloy (metrics) must not be able to read the environment or files of a root process in another container through the host's `/proc`.
3. **It works:** datasources, dashboards, alert rules, every Prometheus target up, host metrics, pushed logs, traces, `make health` and `make backup`.
4. **Switch to standard** with `make install`: cAdvisor and container-log collection come back, there are no stale containers, and the data written in restricted mode is still there. As controls, the invariant check must now report the Docker socket, `SYS_PTRACE` and the `/` mount, and the `/proc` probe must succeed against the root Alloy.
5. **Switch back to restricted:** before `make install`, `make health` fails and names the leftover cAdvisor and Alloy (logging). After it, they are removed, the checks in steps 2 and 3 pass again, and the data is still there.
6. **`make update`** keeps restricted mode: the invariant and the `/proc` check pass again, and the data is still there.

Switching modes rewrites `.env`, so the test runs on a copy of the checkout and never edits yours; it checks at the end that your `.env` is unchanged.

## `mcp.sh` (`make test-mcp`)

Installs the core stacks and the MCP endpoint (`make install-mcp`), writes a known log line and trace, and checks:
1. **Access control:**
   - no token or a wrong token: `401`;
   - a foreign `Host` header or a browser `Origin`: `403`;
   - the token file is `0600` in a `0700` directory.
2. **Read-only:**
   - the read tools are there, and no tool is registered that the server marks as writable or destructive, or whose name says it writes (`create_`, `update_`, `delete_`…) without a read-only mark;
   - the `oib-mcp` service account has the Viewer role, can read, and gets `403` when it tries to save a dashboard or create a service account.
3. **It answers from OIB's data:** through MCP tool calls, the seeded log line comes back from Loki, `up{job="prometheus"}` from Prometheus, and the seeded trace from Tempo, both by ID and by TraceQL search.
4. **Repair, reinstall and uninstall:**
   - With the Grafana token revoked (as after a Grafana restore) and the service account raised to Editor, queries fail.
   - A second `make install-mcp` keeps the client token, sets the role back to Viewer, and makes queries work again.
   - `make uninstall-mcp` removes the container and the tokens.

The test runs on a copy of the checkout, so a real install's `mcp/secrets/` is never touched; it checks that at the end.

## Debugging

`KEEP=1 make test-backup` (or `test-upgrade`) leaves the stack running and keeps the temporary directory (backups, logs, `state` with the run ID and trace ID). Clean up afterwards with `make uninstall-profiling; make uninstall YES=1`.

## CI

[`.github/workflows/acceptance.yml`](../../.github/workflows/acceptance.yml) runs the backup round trip, the Tempo recovery test, the restricted-mode test, the MCP endpoint test, the isolation self-test, and the upgrade test from every release in its matrix. It runs:
- on every pull request except those that change only documentation (`*.md`, `docs/`, `LICENSE`, `completions/`);
- on pushes to `main`;
- weekly, to catch registry-side changes such as moved or deleted image tags.

CI runners are fresh, so the tests run directly against the runner's daemon. When you cut a release, add its tag to the matrix.
