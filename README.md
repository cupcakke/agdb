# agdb

agdb is a single-process storage engine and multi-tenant cloud control plane written in Zig 0.14.

The repository builds three executables and one library:

| Artifact | Source | Purpose |
| --- | --- | --- |
| `libagdb` | `src/agdb.zig` | Storage engine: persistent heap, write-ahead log, ARIES recovery, transactions, vector and rank indexes |
| `agdb-cloud` | `src/cloud_main.zig` | HTTP control plane: tenant registry, sandbox process table, routing, metrics |
| `agdb-wake-proxy` | `src/wake_proxy_main.zig` | Front proxy that wakes a suspended backend and forwards traffic once it is healthy |
| `agdb-autoshutdown` | `src/autoshutdown_main.zig` | Unprivileged idle supervisor that drains and powers off an idle host |

## Requirements

- Zig 0.14.1 (pinned by `AGDB_ZIG_VERSION`)
- Linux (the process table uses `epoll`, seccomp and namespaces)

## Build and test

```
make build        # zig build -Doptimize=Debug
make test         # zig build test --summary all
make fmt-check    # zig fmt --check src build.zig
make check        # fmt-check + build + test
make release      # ReleaseSafe, x86_64-linux-musl
```

`zig build test` runs the library test suite, the integration suite, the wake proxy suite and the idle supervisor suite.

## Configuration

All runtime components are configured exclusively through environment variables. Copy `.env.example` to `.env` and fill it in; `.env` is git-ignored and must never contain values committed to the repository.

### Cloud server

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGDB_CLOUD_PORT` | `7070` | Listening TCP port |
| `AGDB_WORKER_THREADS` | `0` | Worker pool size; `0` selects `2 x cpu_count`, capped at 64 |
| `AGDB_CONNECTION_QUEUE` | `1024` | Bounded accept queue; overflow returns `503` with `Retry-After` |
| `AGDB_REGISTRY_PATH` | — | Tenant registry database file |
| `AGDB_DATA_ROOT` | — | Per-tenant data directory |
| `AGDB_RUNNER_PATH` | — | Sandbox runner executable |
| `AGDB_WAL_RECEIVER_THREADS` | `0` | WAL receiver worker pool size; `0` selects `cpu_count`, capped at 32 |

The server accepts connections on a single thread and dispatches them to a fixed worker pool through a bounded queue. There is no thread-per-connection path, so connection storms are shed rather than translated into unbounded thread creation. Requests are parsed by `src/cloud/http_parser.zig`, which enforces `max_header_bytes`, `max_header_count` and `max_body_bytes`, supports chunked transfer encoding and `Expect: 100-continue`, and maps protocol violations onto `400`, `413`, `431`, `501` and `505`.

### Wake proxy

`AGDB_WAKE_LISTEN_ADDR`, `AGDB_WAKE_LISTEN_PORT`, `AGDB_TARGET_HOST`, `AGDB_TARGET_PORT`, `AGDB_WAKE_HEALTH_PATH`, `AGDB_WAKE_WORKER_THREADS`, `AGDB_WAKE_QUEUE_CAPACITY`, `AGDB_WAKE_CONNECT_TIMEOUT_MS`, `AGDB_WAKE_IO_TIMEOUT_MS`, `AGDB_WAKE_POLL_INTERVAL_MS`, `AGDB_WAKE_POLL_ATTEMPTS`, `AGDB_WAKE_UPSTREAM_BODY_LIMIT`, `AGDB_WAKE_REQUEST_HEADER_LIMIT`.

The wake provider is selected by `AGDB_CLOUD_PROVIDER`:

- `none` — never attempts to start a backend
- `ovh` — calls the OVH public cloud API using `AGDB_OVH_ENDPOINT`, `AGDB_OVH_PROJECT_ID`, `AGDB_OVH_INSTANCE_ID`, `OVH_APP_KEY`, `OVH_APP_SECRET`, `OVH_CONSUMER_KEY`
- `exec` — runs `AGDB_WAKE_EXEC_COMMAND`

No endpoint identifier, project identifier, instance identifier or host address is compiled into the binaries; a test asserts their absence from the sources.

### Idle shutdown supervisor

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGDB_IDLE_SHUTDOWN_SECONDS` | `900` | Idle window before shutdown is considered |
| `AGDB_IDLE_CHECK_INTERVAL_SECONDS` | `60` | Poll period |
| `AGDB_IDLE_CONFIRMATIONS` | `3` | Consecutive idle polls required before acting |
| `AGDB_ACTIVITY_HOST` / `AGDB_CLOUD_PORT` / `AGDB_ACTIVITY_PATH` | `127.0.0.1` / `7070` / `/v1/activity` | Authoritative activity source |
| `AGDB_USE_ACCESS_LOG` | `0` | Optional secondary confirmation from an nginx access log |
| `AGDB_ACCESS_LOG_PATH` | `/var/log/nginx/access.log` | Log file, reopened on rotation by inode and size checks |
| `AGDB_SHUTDOWN_INHIBIT_FILE` | `/run/agdb/shutdown.inhibit` | Shutdown is skipped while this file exists |
| `AGDB_DRAIN_UNIT` | `agdb-cloud.service` | Unit stopped before poweroff |
| `AGDB_DRAIN_TIMEOUT_SECONDS` | `120` | Maximum wait for in-flight work to finish |
| `AGDB_SHUTDOWN_COMMAND` | `systemctl poweroff` | Command executed after a successful drain |
| `AGDB_SHUTDOWN_DRY_RUN` | `1` | When set, decisions are logged and nothing is stopped |

The supervisor runs as the unprivileged `agdb-shutdown` user. Its decision is driven by `GET /v1/activity`, which reports `idle_ms`, `active_connections`, `queued_connections`, `in_flight_requests`, `active_sandboxes`, `pending_sandbox_requests`, `shed_connections` and `worker_threads`. Shutdown requires every counter to be zero, the idle window to be exceeded, `AGDB_IDLE_CONFIRMATIONS` consecutive confirmations, and the absence of the inhibit file. If the activity endpoint cannot be reached the streak resets and no shutdown occurs. Parsing an access log is never sufficient on its own and is disabled by default.

The privilege to power the machine off is granted outside the binary, through a polkit rule or a single `sudoers` entry restricted to the configured command. The process never requires root and logs a warning when started as root.

## HTTP endpoints

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/v1/health` | Liveness probe |
| `GET` | `/v1/activity` | Machine-readable activity counters used by the idle supervisor |
| `GET` | `/v1/metrics` | Request, latency and tenant metrics |
| `POST` | `/v1/register` | Tenant registration |
| `*` | `/v1/db/...` | Per-tenant database routes |

## Deployment

`deploy.sh` reads `.env`, refuses to run without `AGDB_DEPLOY_HOST` and `AGDB_DEPLOY_USER`, verifies the pinned Zig version, runs `zig build test`, uploads a timestamped release directory, installs hardened systemd units for the `agdb` and `agdb-shutdown` users, reloads nginx, performs ten health retries and rolls back to the previous binaries on failure. `run.sh` provides `--run`, `--cloud`, `--build-only` and `--test` modes for local use.

Continuous integration (`.github/workflows/ci.yml`) builds Debug, ReleaseSafe and ReleaseFast, enforces `zig fmt --check`, runs the full test suite and scans the repository for committed secrets.
