# AGDB Convergence Upgrade — Execution Prompt (v2)

## 0. Objective

I want the `agdb` repository converted from a split codebase — a multi-tenant cloud server built only on the flat append-only store `src/kv.zig`, plus an unreferenced "laboratory" runtime (`src/runtime.zig` and its persistent-heap / ARIES / HTM / DST modules) — into one unified system in which:

- the cloud server executes tenant workloads on the persistent-heap + WAL + recovery runtime,
- every component that currently claims hardware or kernel capabilities it does not exercise (GPU/Futhark, RDMA, TPM2, seccomp user-notification brokering) is either genuinely implemented, compiled into the shipped binaries, and tested, or removed together with every name, comment, log line, metric, and document that claims it,
- every misleading name is corrected (notably the "AI embedding engine" that is feature hashing),
- all identified security and reliability defects (committed infrastructure identifiers, thread-per-connection servers, fragile HTTP parsing, sandbox reap leaks, root-privileged log-scraping auto-shutdown) are eliminated,

so that on a clean clone the documented behaviour and the compiled behaviour are identical, the full verification gate in §9 passes, and no shipped code path is mocked, stubbed, simulated-for-production, hardcoded, or decorative.

Fault injection and virtual time are the single permitted exception: they are legitimate *test* machinery, must live behind `builtin.is_test` or a dedicated test/DST build step, and must be unreachable from any installed binary.

---

## 1. Verified current state (established by inspection of this checkout; re-verify before relying on any line)

Repository root contains: `Makefile`, `build.sh`, `build.zig`, `build.zig.zon`, `deploy.sh`, `nginx.conf`, `replit.nix`, `run.sh`, `.replit`, `src/`. There is **no** `README.md`, **no** `.gitignore`, **no** `.github/` CI, **no** `LICENSE`, **no** test fixtures directory.

- `build.zig.zon`: `name = .agdb`, `version = "1.0.0"`, `minimum_zig_version = "0.14.0"`, no dependencies, and `.paths` lists `"README.md"` — a file that does not exist, so packaging is already broken. `build.zig` uses the `b.createModule` + `.root_module` API. Determine the exact Zig version that compiles this tree, pin it everywhere, and record it.
- `build.zig` builds: static lib `agdb` (`src/agdb.zig`), `agdb` CLI (`src/cli_main.zig`), `agdb-runtime` (`src/runtime_main.zig`), `agdb-cloud` (`src/cloud_main.zig`), `agdb-wake-proxy`, `agdb-autoshutdown`, and `sandbox_runner` (x86_64-linux-musl, static). Test steps: `test`, `test-integration`. `src/compute.fut` and `src/tpm.c` are referenced by **no** build step.
- `src/database.zig` (770 lines): `Database` holds `kv: *kv_mod.KvStore`; config fields include `gpu_ctx`, `gpu_search_threshold`, `jit_alloc`, `dhtm_runtime`; `searchVectorGpu` exists; state keys are magic strings `__agdb_next_id`, `__agdb_bm25_state`, `__agdb_vector_state`.
- `src/runtime.zig` re-exports `PersistentHeap`, `PersistentAllocator`, `WAL`, `TransactionManager`, `Transaction`, `RecoveryEngine`, `RefCountGC`, `SnapshotManager`, `SecurityManager`, `PersistentStore`, `SchemaRegistry`, `PersistentPtr`, and exposes `makeDatabaseConfig`, `beginTransaction`, `commit`, `rollback`, `allocate`, `free`, `getRoot`, `setRoot`, `createSnapshot`, `restoreSnapshot`, `runGC`, `getStats`, `flush`. Nothing under `src/cloud/` imports it.
- `src/cloud/sandbox_runner.zig`: defines `cosineSimilarityKernel` — a CPU `for` loop — and registers it as GPU kernel `"cosine_similarity"`; opens `/dev/null` and calls `ch.connectSoftware(null_stream)` for the RDMA channel; installs a BPF filter whose actions are `SECCOMP_RET_KILL_PROCESS`.
- `src/cloud/process_table.zig`: `seccompSupervisorThread` and `insertWithSeccomp` exist; no production caller registers a listener fd. `reapIdleSandboxes` is invoked from the dispatch loop.
- `src/cloud/http_server.zig` (826 lines): `MAX_CONNECTIONS = 1024`, `std.Thread.spawn` per accepted connection. `src/cloud/wal_transport.zig` has the same pattern (`acceptLoop` + spawn per connection).
- `src/server.zig` is a **second**, `std.net`-based HTTP server used by the single-node CLI path — a duplicated surface that must be reconciled, not ignored.
- `src/wake_proxy_main.zig` hardcodes `PROJECT_ID`, `INSTANCE_ID`, `VPS_HOST` set to a production IP literal, `OVH_HOST`, `OVH_BASE`; `deploy.sh` hardcodes the same production host in `SERVER` and prints it.
- `src/autoshutdown_main.zig` runs as root and parses `/var/log/nginx/access.log` on a 60 s loop.
- `src/vector.zig` exposes `hashEmbed` (per-word Wyhash feature hashing), called from `database.zig`.
- **Corrections to common misreadings of this tree, which the previous plan got wrong and you must not repeat:**
  - `src/io.zig` is **not** an IO abstraction; it contains only `stableHash`, `stableHashU32`, `combineHashes`. The simulated-IO layer required in Phase 5 must be a new module.
  - `src/ssi.zig` is **not** serializable snapshot isolation; it is a token/segment retrieval index (`Segment`, `RankedSegment`, `retrieveTopK`, tensor import/export). No isolation-level implementation exists anywhere today; `src/transaction.zig` contains no isolation handling. Concurrency control must be built, not "wired up".
  - `src/kv.zig` already contains `SimKvBackend` with `armFault`/`KvFaultSpec` — fault injection exists for the KV backend only.
  - `src/seqlock.zig` provides a real `SeqLock`; `src/iouring.zig` contains raw `io_uring` opcode definitions. Both are candidates for reuse, not rewrite.
- The build toolchain is **not** installed in the working environment used to produce this document; nothing here has been compile-verified. Install the pinned Zig toolchain first and treat §1 as claims to re-check, not as proven facts.

---

## 2. Defect → phase traceability

Every row must be closed by code and by a test; the pull-request description must map each row to commits.

| # | Defect | Evidence | Phase | Closed when |
|---|---|---|---|---|
| D1 | Cloud runs `kv.zig`, not the runtime engine | `sandbox_runner.zig` → `database.Database` → `kv.zig` | 1 | No cloud-reachable path imports `kv.zig` except the migration tool; crash tests pass on the runtime engine |
| D2 | `pheap`/`allocator`/`wal`/`recovery`/`transaction` unused in production | no `src/cloud/*` imports `runtime.zig` | 1 | Runtime is the tenant storage substrate; recovery report logged at every sandbox start |
| D3 | Fake GPU kernel | `cosineSimilarityKernel` CPU loop registered as GPU | 2 | Futhark compiled by `build.zig` and dispatched, or GPU surface removed entirely |
| D4 | `compute.fut` not in the build | no `build.zig` reference | 2 | Build step generates and links it under `-Dgpu=futhark-*` |
| D5 | RDMA bound to `/dev/null` and to itself | `ch.connectSoftware(null_stream)` | 3 | Real verbs or real framed TCP transport to a configured remote peer; `connectSoftware` deleted |
| D6 | `tpm.c` not compiled or linked | no `addCSourceFile` | 4a | Compiled and linked under `-Dtpm2=tss2`, exercised against swtpm, or file deleted |
| D7 | Seccomp supervisor never runs | `insertWithSeccomp` has no production caller | 4b | Listener fd passed over IPC, supervisor decides live syscalls, integration test proves it |
| D8 | Feature hashing presented as an AI embedding engine | `hashEmbed` | 6 | Renamed `featureHashEmbed`; `Embedder` interface; honest docs and `/v1/capabilities` |
| D9 | Committed infrastructure identifiers and IP | `wake_proxy_main.zig`, `deploy.sh` | 8 | All values come from env/config; secret scanner green; rotation stated in the PR |
| D10 | Thread-per-connection HTTP servers | `http_server.zig`, `wal_transport.zig` | 7 | Fixed worker pool + epoll; load test shows constant thread count |
| D11 | Fragile hand-rolled HTTP parser | 64 KB `\r\n\r\n` scan | 7 | Incremental state-machine parser with chunked, pipelining, smuggling defence, fuzz corpus |
| D12 | Sandbox reap leaks (zombies, tmpfs mounts, cgroups) | `reapIdleSandboxes` in the dispatch loop | 4c | Janitor thread, staged escalation with deadlines, reconciliation; 100-cycle leak test clean |
| D13 | Root auto-shutdown scraping a rotatable log | `autoshutdown_main.zig` | 8 | Unprivileged, counter-driven, drain-protocol shutdown with inhibit and dry-run |
| D14 | DST not applied to the production engine | `SimKvBackend` only | 5 | `agdb-dst` drives the runtime engine under injected faults in CI |
| D15 | HTM claimed without capability probe or fallback metrics | `htm.zig` | 5 | CPUID/`xgetbv` probe, bounded retry, mandatory software fallback, abort-reason metrics |
| D16 | Packaging/hygiene broken: missing README, `.gitignore`, CI, LICENSE; `.paths` references a nonexistent file | repo root | 0, 9 | All present and consistent |
| D17 | Two divergent HTTP surfaces | `server.zig` vs `cloud/http_server.zig` | 7 | One shared parser/transport core; divergence documented or eliminated |

---

## 3. Global rules

1. **Completeness**: produce full, compiling files. No `...`, `// unchanged`, `// TODO`, `// FIXME`, no unimplemented function bodies, no `unreachable` standing in for logic, no placeholder constants, no sample data pretending to be real behaviour.
2. **Honesty of naming**: no identifier, comment, log, metric, HTTP field, or document may name a capability that the executing code does not use. A CPU implementation is named `...Cpu`; a software fallback is named `...Fallback`.
3. **Capability gating**: hardware/external-library features are a compile-time build option *plus* a runtime probe, surfaced through one `Capabilities` struct that feeds `/v1/capabilities`, `/v1/health`, metrics, and startup logs with `{enabled, available, reason}` per feature. Unavailable means refused or explicitly degraded — never silently emulated under the hardware name.
4. **Error handling**: no discarding `catch {}` / `catch null` / `catch |_| {}` on any path affecting durability, isolation, security, or resource release. Every tolerated error is logged with context and converted into an explicit state.
5. **Memory**: `errdefer` on every fallible allocation path; tests run under `std.testing.allocator` and a leak-checking GPA build step.
6. **Concurrency**: every shared mutable datum is protected by a lock, an atomic with a written-down memory ordering, or `SeqLock`; document the invariant next to the declaration. No sleeping while holding a lock; no unbounded blocking syscalls.
7. **On-disk formats**: every persistent structure carries a magic number, format version, and CRC32C; readers reject unknown versions with a precise error; format changes ship with a migration path. Document each layout in `ARCHITECTURE.md` with a field table.
8. **Secrets**: nothing secret or environment-identifying in tracked files. Required values are read from environment or config file and validated at startup with fatal, specific errors. `.env.example` documents each with name, type, default, required/optional.
9. **Dependencies**: no new third-party dependency without recording, in `ARCHITECTURE.md`, why it is required, its licence, and how absence is handled. System libraries (OpenCL/CUDA, libibverbs/librdmacm, tss2, ONNX Runtime) are linked only under their build option.
10. **Compatibility**: the existing CLI commands and public HTTP routes keep working, or a breaking change is listed in `CHANGELOG.md` with its migration step. Existing tenant data must be readable via the Phase 1 migration tool; data loss is unacceptable.
11. **Determinism of verification**: every claim you make in a phase report must be backed by a command and its output. Do not report a phase complete on the basis of reasoning alone.
12. **Commits**: one commit per phase on the current working branch, message `phase<N>: <summary>`, body listing the defect IDs closed and files touched. No history rewriting, no branch switching, no force pushes.
13. **Scope discipline (non-goals)**: do not rewrite `bm25.zig`, `tensor.zig`, `ranker.zig`, `tokenizer.zig`, `numa.zig`, `topology.zig`, `simd.zig`, `ans.zig`, `inspect.zig`, `benchmark.zig` beyond what the phases require; do not reformat untouched files; do not introduce a new query language, a new wire protocol, or a storage rewrite beyond the engine abstraction specified in Phase 1.

---

## 4. Build options and configuration surface (authoritative; implement exactly these names)

Build options (all default to the safest value, all reported by `agdb --version --verbose`):

| Option | Values | Default | Effect |
|---|---|---|---|
| `-Dengine` | `kv`, `runtime` | `runtime` | Default storage backend for new databases |
| `-Dgpu` | `none`, `futhark-c`, `futhark-multicore`, `futhark-opencl`, `futhark-cuda` | `none` | Compiles `src/compute.fut` and links the device runtime |
| `-Drdma` | `off`, `tcp`, `verbs` | `tcp` | WAL-shipping transport implementation |
| `-Dtpm2` | `off`, `tss2` | `off` | Compiles and links `src/tpm.c` |
| `-Dhtm` | `off`, `auto` | `auto` | Allows RTM use when the CPU probe succeeds |
| `-Dseccomp-notify` | `off`, `auto`, `require` | `auto` | `require` fails sandbox start when the kernel lacks user-notification |
| `-Donnx` | `off`, `on` | `off` | Links ONNX Runtime for the local embedder |
| `-Dsanitize` | `off`, `on` | `off` | Enables UBSan/ASan-equivalent checks where the toolchain supports them |

Environment variables (validated at startup; a missing required value is a fatal, named error): `AGDB_REGISTRY_PATH`, `AGDB_DATA_ROOT`, `AGDB_LISTEN_ADDR`, `AGDB_LISTEN_PORT`, `AGDB_WORKER_THREADS`, `AGDB_MAX_CONNECTIONS`, `AGDB_REQUEST_TIMEOUT_MS`, `AGDB_HEADER_TIMEOUT_MS`, `AGDB_BODY_MAX_BYTES`, `AGDB_RATE_LIMIT_RPS`, `AGDB_FSYNC_POLICY`, `AGDB_CHECKPOINT_INTERVAL_MS`, `AGDB_WAL_SEGMENT_BYTES`, `AGDB_WAL_REPLICA_MODE`, `AGDB_WAL_REPLICA_ENDPOINTS`, `AGDB_WAL_REPLICA_ACKS`, `AGDB_WAL_REPLICA_TIMEOUT_MS`, `AGDB_EMBEDDER`, `AGDB_EMBEDDING_ENDPOINT`, `AGDB_EMBEDDING_MODEL`, `AGDB_EMBEDDING_API_KEY`, `AGDB_EMBEDDING_DIM`, `AGDB_MASTER_KEY_SOURCE`, `AGDB_MASTER_KEY_PASSPHRASE`, `AGDB_TPM_TCTI`, `AGDB_CLOUD_PROVIDER`, `AGDB_OVH_ENDPOINT`, `AGDB_OVH_PROJECT_ID`, `AGDB_OVH_INSTANCE_ID`, `OVH_APP_KEY`, `OVH_APP_SECRET`, `OVH_CONSUMER_KEY`, `AGDB_TARGET_HOST`, `AGDB_IDLE_SHUTDOWN_SECONDS`, `AGDB_SHUTDOWN_INHIBIT_FILE`, `AGDB_SHUTDOWN_DRY_RUN`, `AGDB_LOG_LEVEL`, `AGDB_LOG_FORMAT`.

---

## 5. Phases

Dependency order: Phase 0 → 1 → 5 (DST needs the engine) ; Phases 2, 3, 4, 6, 7, 8 depend only on 0 and 1 and may be done in any order after Phase 1; Phase 9 last. Do not start a phase before its predecessors are green.

### Phase 0 — Toolchain, hygiene, baseline

1. Install and pin the exact Zig version that builds this tree; update `build.zig.zon` `minimum_zig_version`, `build.sh`, `Makefile`, `replit.nix`, `.replit`, and the CI workflow to that version.
2. Record a baseline: `zig build`, `zig build test`, `zig build test-integration` outputs, including every pre-existing failure, in `BASELINE.md`. Fix build breakage caused by the missing `README.md` in `.paths` by creating the real `README.md` (final content in Phase 9) or by correcting `.paths` — state which and why.
3. Add `.gitignore` (`zig-out/`, `.zig-cache/`, `zig-cache/`, `.env`, `*.key`, `*.pem`, generated Futhark sources, test data dirs), `LICENSE` if the owner specifies one, `.editorconfig`.
4. Add `.github/workflows/ci.yml` running, at this stage, `zig fmt --check`, `zig build`, `zig build test`, `zig build test-integration`, and a secret scan. CI must be green at the end of every later phase.
5. **Definition of done**: `zig fmt --check src build.zig` clean; CI green; `BASELINE.md` committed.

### Phase 1 — One engine (D1, D2)

1. `src/storage_engine.zig`: vtable interface `StorageEngine` with an explicit error set (no `anyerror`) and operations `open`, `close`, `beginTransaction`, `commit`, `rollback`, `put`, `get`, `delete`, `contains`, `iterate` (full and prefix, owned key/value iterator with `deinit`), `count`, `countWithPrefix`, `keysWithPrefix`, `diskSize`, `deadBytes`, `flush`, `compact`, `createSnapshot`, `restoreSnapshot`, `stats`. Specify, in doc comments, the durability and visibility contract each operation must satisfy; both backends must satisfy it identically.
2. `src/engine_kv.zig`: adapts `kv.zig` unchanged in behaviour, used by the single-file CLI and as the migration source. Its transaction methods must provide real single-writer atomicity with fsync-on-commit — if `kv.zig` cannot, implement it there rather than pretending.
3. `src/engine_runtime.zig`: the production backend.
   - Keys and values live in the persistent heap, addressed by `PersistentPtr` (128-bit heap UUID + 64-bit offset), allocated through `PersistentAllocator`.
   - A **persistent, crash-safe index** (hash table or B+-tree) stored inside the heap via `PersistentPtr`; no in-memory map rebuilt by scanning the log at open.
   - Every mutation produces ARIES WAL records with monotonically increasing LSNs, page/record-level redo and undo information, CLRs on rollback, transaction table and dirty-page table maintenance, and fuzzy checkpoints triggered by interval and WAL-byte threshold.
   - `RecoveryEngine` runs Analysis → Redo → Undo at open and returns a report (last checkpoint LSN, transactions analysed/redone/undone, bytes scanned, duration) that the caller logs.
   - Concurrency control is **new work**: implement multi-version visibility or strict two-phase locking in `src/transaction.zig` (do not assume `ssi.zig` provides it — it does not), define the supported isolation level explicitly, detect and report write-write and, if serializable, read-write conflicts, and return a typed `Conflict` error that callers retry.
   - Space reclamation through `gc.zig`; point-in-time snapshots through `snapshot.zig`.
   - HTM (`htm.zig`) may be used for short critical sections only behind the Phase 5 probe, always with the software fallback.
4. `src/database.zig`: `DatabaseConfig` gains `engine: EngineKind`, `runtime: ?*Runtime`, `fsync_policy`, `checkpoint_interval_ms`, `wal_segment_bytes`; the `kv` field is replaced by a `StorageEngine`. Replace the magic state keys with a documented, versioned key-space (`agdb/v1/meta/next_id`, `agdb/v1/index/bm25`, `agdb/v1/index/vector`, `agdb/v1/rec/<be_u64_id>`, …). Record insert plus BM25 plus vector-index updates must be one atomic transaction; a crash can never leave indexes disagreeing with records.
5. `src/cloud/sandbox_runner.zig`: build a `Runtime` from `RuntimeConfig` rooted in the sandbox data directory; open `Database` through `Runtime.makeDatabaseConfig`; log the recovery report; run a checkpoint thread; on `SIGTERM`/shutdown IPC drain, checkpoint, flush, fsync and close within a configurable grace period; exit non-zero with a precise message when recovery fails. Apply the same to `src/cli.zig`/`src/runtime_main.zig` so the CLI can open runtime-backed databases.
6. `src/migrate_main.zig` → `agdb-migrate`: reads a `kv.zig` database, writes a runtime heap + WAL set, verifies by full key-space comparison and per-record checksum, emits a JSON manifest, supports `--dry-run` and `--verify-only`, and never mutates the source. Wire it into `deploy.sh` with a documented, reversible procedure.
7. Tests: `src/tests_engine.zig` — one conformance body executed against both backends; transaction atomicity, isolation, and conflict tests; reopen-after-close equivalence; migration round-trip; concurrent writers; large-value and many-key stress.
8. **Definition of done**: `grep -rn "kv.zig\|kv_mod" src/cloud src/cloud_main.zig` returns nothing; conformance suite passes on both backends; a `kill -9` during ingest followed by reopen preserves exactly the acknowledged writes.

### Phase 2 — GPU: real or removed (D3, D4)

1. Decide and state up front: implement or remove. Removal means deleting `src/gpu.zig`, `src/compute.fut`, `searchVectorGpu`, `gpu_ctx`, `gpu_search_threshold`, and every GPU mention, and recording the decision in `CHANGELOG.md`. Only the implementation path is specified below.
2. `build.zig`: under `-Dgpu=futhark-*`, run the Futhark compiler on `src/compute.fut` to produce C sources and a header into the build cache, compile them with `addCSourceFile`, link the matching runtime (`-lOpenCL`, `-lcuda -lcudart`, or pthreads), and fail the build with an explicit message when the compiler, headers, or libraries are missing. Generated files are never committed.
3. `src/compute.fut`: complete entry points `cosine_similarity_batch`, `dot_product_batch`, `l2_distance_batch`, `top_k`, `bm25_score_batch`, with types matching the Zig call sites exactly.
4. `src/gpu.zig`: rewrite as a real backend — context creation over the generated Futhark context, device query, typed device buffers with explicit ownership and lifetimes, host↔device transfer, kernel dispatch, synchronization, device error → Zig error mapping, and `GpuCapabilities { backend, device_name, total_memory, max_workgroup }`. Delete the kernel-registration indirection that allowed arbitrary CPU functions to be registered as GPU kernels, or restrict it to kernels the device backend owns.
5. `sandbox_runner.zig` registers no kernels; the engine consults `gpu.probe()`. Rename `searchVectorGpu`/`gpu_search_threshold` to `searchVectorAccelerated`/`accel_search_threshold`, with the CPU implementation named `searchVectorCpu`.
6. Tests: randomized CPU/device equivalence within 1e-5 relative tolerance for f32, empty/1-element/non-multiple-of-workgroup sizes, dimension-mismatch error paths, and a benchmark step reporting both paths. Device tests skip with a printed reason only when `-Dgpu=none`.
7. **Definition of done**: under `-Dgpu=futhark-opencl` (or `-cuda`) on a capable host, a counter proves kernels executed on the device; under `-Dgpu=none`, `grep -rniE "gpu|cuda|opencl" src/` yields only build-option plumbing and capability reporting.

### Phase 3 — RDMA: real transport or removed (D5)

1. `-Drdma=off|tcp|verbs`. Delete `connectSoftware` and every `/dev/null`/self-loopback wiring.
2. `src/rdma.zig` (`verbs`): device enumeration, PD, CQ, QP creation and INIT→RTR→RTS transitions, memory-region registration with correct access flags, RDMA WRITE / WRITE_WITH_IMM and SEND/RECV posting, completion polling with per-WC error handling, `rdma_cm` connect/accept with timeouts, teardown without leaks.
3. `src/rdma_channel.zig`: transport-agnostic WAL-shipping channel with `verbs` and `tcp` implementations. `tcp` is a real transport over `std.net`: length-prefixed frames, CRC32C per frame, sequence numbers, credit-based backpressure, heartbeat, reconnect with exponential backoff and jitter, and strict rejection of malformed or out-of-order frames. A test-only in-memory pipe may exist behind `builtin.is_test`.
4. `src/cloud/wal_transport.zig` + runner: ship WAL segments to `AGDB_WAL_REPLICA_ENDPOINTS`; implement the follower: receive, validate (CRC, LSN continuity), persist, apply, acknowledge, and expose a durable follower LSN. Implement `AGDB_WAL_REPLICA_MODE=async|semisync` with `AGDB_WAL_REPLICA_ACKS` and `AGDB_WAL_REPLICA_TIMEOUT_MS`; define and document commit behaviour on timeout.
5. Tests: two-process TCP replication including disconnects, partial frames, corrupted frames, slow follower, follower restart and catch-up; leader/follower consistency check over the full key space; verbs tests gated on hardware with a printed skip reason.
6. **Definition of done**: `grep -rn "connectSoftware\|/dev/null" src/cloud src/rdma*.zig` returns nothing relevant; replication lag is a live metric; a follower reconstructs the leader's database byte-for-byte at the acknowledged LSN.

### Phase 4 — TPM2, seccomp brokering, sandbox lifecycle (D6, D7, D12)

**4a. TPM2.** `-Dtpm2=tss2` compiles `src/tpm.c` via `addCSourceFile` and links `tss2-esys`, `tss2-tctildr`, `tss2-mu`, with a header/library presence check in `build.zig`. Complete `tpm.c`: TCTI/ESAPI setup and teardown, PCR read and extend, `TPM2_GetRandom`, owner-hierarchy primary key creation, seal/unseal of the tenant data-encryption key under a PCR policy, quote generation; full `TSS2_RC` → stable error-code mapping; no leaked ESYS objects on any path. Add `src/tpm.zig` as the Zig wrapper with `TpmCapabilities` and integrate with `src/security.zig`: the at-rest master key is TPM-sealed when available, otherwise derived with Argon2id from `AGDB_MASTER_KEY_PASSPHRASE`; never a compiled-in constant. Test against `swtpm` when present; always unit-test the RC mapping and wrapper lifetimes. If TPM2 is not implemented, delete `src/tpm.c` and all references.

**4b. Seccomp user notification.** The runner installs a filter returning `SECCOMP_RET_USER_NOTIF` for the brokered syscall set and `SECCOMP_RET_KILL_PROCESS` for the hard-denied set, obtaining the listener fd with `SECCOMP_FILTER_FLAG_NEW_LISTENER`; the fd is sent to the supervisor over the existing IPC channel with `SCM_RIGHTS`; `src/cloud/sandbox.zig` calls `ProcessTable.insertWithSeccomp` on the real startup path, and registration without a listener fd is refused when policy requires brokering. Complete `seccompSupervisorThread`: `NOTIF_RECV`, `NOTIF_ID_VALID` before **and** after reading target memory (TOCTOU), bounds-checked target reads via `/proc/<pid>/mem`, per-syscall policy evaluation, `NOTIF_SEND` with allow/errno, `FLAG_CONTINUE` only where provably safe, `NOTIF_ADDFD` where needed, `ENOENT` handling for dead targets, epoll multiplexing of many listeners over a bounded thread pool, clean teardown. Probe kernel support at startup; under `-Dseccomp-notify=auto` fall back to the kill-only filter with one explicit warning and a degraded capability report; under `require`, refuse to start sandboxes. Tests: brokered syscall observed and decided; denied syscall kills the process; TOCTOU attempt defeated; supervisor death fails sandboxes closed; 1000 notifications without fd or memory growth.

**4c. Sandbox reaping.** Move reaping from the dispatch epoll loop to a dedicated janitor thread with its own timer. Implement a per-sandbox shutdown state machine with a deadline at every stage: `SIGTERM` → grace → `cgroup.kill` → `SIGKILL` → bounded wait → `umount2(MNT_DETACH)` of tmpfs/overlay mounts → cgroup `rmdir` with retry and backoff → persistent orphan record retried later. No unbounded wait, no blocking syscall without a timeout, no reap work on the request path. Add startup and periodic reconciliation scanning the cgroup tree, `/proc/self/mountinfo`, and the runtime directory for sandboxes unknown to the process table, with counters for orphans found/cleaned/failed. Test with a child that ignores `SIGTERM`: escalation completes, no mount, cgroup, or zombie remains.

### Phase 5 — DST against the production engine (D14, D15)

1. New `src/sim_io.zig` (do not overload `src/io.zig`, which is hashing-only): a single IO interface used by `pheap.zig`, `wal.zig`, `recovery.zig`, `engine_runtime.zig`, with a real backend (pwrite/pread/fsync/fdatasync, optionally `iouring.zig`) and a deterministic simulated backend supporting torn and partial writes at arbitrary offsets, reordering of writes not separated by fsync, lost fsync, sector corruption, bit flips, `EIO`, latency injection, and instantaneous power loss. The simulated backend is compiled only into tests and `agdb-dst`.
2. `src/dst_main.zig` → `agdb-dst`: a seeded simulator built on `tsc.zig` virtual time and the `concurrency.zig` fiber scheduler, driving randomized transactional workloads against the runtime engine with injected faults, then checking invariants: every acknowledged commit survives, no aborted effect survives, indexes match records, `pheap` free lists and allocator size classes are consistent, refcounts are exact, WAL LSNs are monotonic and checkpoints are valid. Each run prints its seed; a given seed replays identically.
3. Build steps `zig build dst -Dseed=<n> -Dsteps=<n>` and `zig build dst-soak` (fixed seed corpus `tests/seeds.txt` plus randomized seeds for a bounded duration). CI runs the corpus; a new failing seed is added to the corpus with its fix.
4. `htm.zig`: real CPUID leaf-7 RTM/HLE probe plus `xgetbv` check, abort-code classification (`_XABORT_EXPLICIT/RETRY/CONFLICT/CAPACITY/DEBUG/NESTED`), bounded retry policy, mandatory software-lock fallback, metrics for hardware commits and aborts by reason, and a test that forces aborts to prove the fallback executes. Gate all use behind `-Dhtm=auto` plus the probe, and on non-x86_64 compile only the software path.
5. **Definition of done**: `zig build dst-soak` passes the committed corpus; a deliberately introduced missing-fsync bug is caught by the simulator (demonstrate this, then revert the injected bug).

### Phase 6 — Honest embeddings (D8)

1. Rename `hashEmbed` → `featureHashEmbed` at every call site, documented as "feature hashing (hashing trick), not a learned model", with the hash function, sign rule, dimension semantics, and normalization written out.
2. `Embedder` interface with: `FeatureHashEmbedder` (default, dependency-free); `ExternalModelEmbedder` — a complete HTTPS client for an OpenAI-compatible `/v1/embeddings` endpoint with certificate verification, connect/read timeouts, retry with exponential backoff and jitter, request batching, bounded on-disk cache keyed by content hash, strict dimension validation, and no logging of keys or payloads; optionally `OnnxEmbedder` behind `-Donnx=on` with a real tokenizer path through `src/tokenizer.zig` — implement it completely or omit it.
3. Persist embedder identity (kind, model, dimension, version) with the vector index; refuse to mix vectors from different embedders; provide a re-embed/reindex command in the CLI.
4. Remove every "AI", "neural", "transformer", "semantic model" claim from code, CLI help, API responses, and docs unless an external model is configured and reachable. `/v1/capabilities` reports the active embedder.
5. Tests: determinism and dimension correctness of feature hashing; external embedder against a local test HTTP server covering success, 429 with retry, 5xx, timeout, malformed JSON, and dimension mismatch; mixed-embedder rejection; reindex correctness.

### Phase 7 — HTTP: pool, parser, limits (D10, D11, D17)

1. Replace thread-per-connection in `src/cloud/http_server.zig` and `src/cloud/wal_transport.zig` with a fixed worker pool (default `min(2*ncpu, 64)`, `AGDB_WORKER_THREADS`) over edge-triggered `epoll`, `accept4(SOCK_NONBLOCK|SOCK_CLOEXEC)`, `SO_REUSEPORT` per worker or accept-and-distribute, per-connection state machines, bounded connection table, and load shedding with `503` + `Retry-After` instead of unbounded spawning.
2. New `src/cloud/http_parser.zig`: incremental state-machine HTTP/1.1 parser — request-line validation (method, target forms, version), header limits (count and total bytes), rejection of conflicting `Content-Length`/`Transfer-Encoding` and of obsolete line folding (request-smuggling defence), chunked decoding with trailers, `Expect: 100-continue`, keep-alive and pipelining with a per-connection request cap, `Connection: close`, streaming bodies with `AGDB_BODY_MAX_BYTES`, and correct status codes for every malformed case (400, 413, 414, 431, 501, 505). No fixed 64 KB assumption anywhere.
3. Deadlines and defences: header timeout, body timeout, idle keep-alive timeout, total request timeout, slowloris defence, read/write backpressure, sharded token-bucket rate limiting per tenant and per IP with bounded memory.
4. Response hardening: exact framing, no header injection from user-controlled data, security headers, request-id generation and propagation, structured access logs that never contain API keys or record bodies.
5. Reconcile `src/server.zig` with the cloud server: both use the same parser and response writer; any remaining difference is documented in `ARCHITECTURE.md`.
6. Tests: parser corpus plus fuzzing — split at every byte boundary, oversized header, missing terminator, smuggling vectors, chunked edge cases, invalid UTF-8 in targets; pipelining; timeout and slowloris tests; load test asserting constant thread count and bounded RSS over ≥10k sequential and ≥1k concurrent connections.

### Phase 8 — Secrets, deployment, auto-shutdown (D9, D13)

1. Remove `PROJECT_ID`, `INSTANCE_ID`, `VPS_HOST`, and hardcoded endpoints from `src/wake_proxy_main.zig`; remove the hardcoded host from `deploy.sh`, `run.sh`, `nginx.conf`, `Makefile`, `.replit`. All come from the §4 environment variables with fatal startup validation. Add `.env.example`. State in the PR that the previously committed project ID, instance ID, and IP must be treated as disclosed and rotated or reprovisioned.
2. `CloudProvider` interface (`start`, `status`, `stop`) with a complete OVH implementation — correct `X-Ovh-Signature` computation, clock-skew correction via the provider time endpoint, retries with backoff, response-body error parsing, verified TLS — and a generic exec-hook implementation running an operator-supplied command. Never disable certificate verification.
3. Rewrite `src/autoshutdown_main.zig`: runs as a dedicated unprivileged system user; primary idle signal is `agdb-cloud`'s own counters over a local Unix socket (last request timestamp, active connections, active sandboxes, in-flight background jobs); nginx log reading, if retained at all, is secondary and robust (open by inode, detect rotation and truncation via `fstat`, safe reopen, tolerate partial and malformed lines, cap read size). Never shut down while a sandbox is live, a WAL segment is unreplicated, or a checkpoint/compaction/migration/backup is running. Implement a drain protocol: stop accepting work → wait for in-flight work with a deadline → checkpoint and flush all tenants → fsync → signal shutdown. Support an inhibit lock file and `--dry-run`, and log the full decision rationale on every evaluation.
4. Systemd units for `agdb-cloud`, `agdb-wake-proxy`, `agdb-autoshutdown` with `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, minimal `CapabilityBoundingSet`, `RestrictAddressFamilies`, `SystemCallFilter`, resource limits, and restart policies, referenced from `deploy.sh`. `deploy.sh` must be idempotent, fail fast on any error (`set -euo pipefail`), verify binaries before swapping, and support rollback to the previous release.
5. CI gains a required secret-scanning job (`gitleaks` or equivalent) with the repository history scanned once and the result reported.

### Phase 9 — Observability, documentation, verification

1. `src/cloud/metrics.zig`: Prometheus-format metrics for engine kind, WAL bytes written/fsynced, checkpoint duration, recovery duration and phase counts, transaction commits/aborts/conflicts, HTM hardware commits vs. software fallbacks by abort reason, GC reclaimed bytes, replication lag and follower ack latency, GPU backend and kernel timings, seccomp notifications received/allowed/denied, sandbox start/stop/reap/orphan counts, HTTP status and latency histograms, worker-pool saturation, rate-limit rejections, embedder requests and cache hit ratio.
2. Endpoints `/v1/health` (liveness), `/v1/ready` (recovery complete, replication connected when required, pools healthy), `/v1/capabilities` (probed truth: `engine`, `gpu`, `rdma`, `tpm2`, `htm`, `seccomp_notify`, `replication_mode`, `embedder`, each with `enabled`, `available`, `reason`).
3. `README.md`: architecture overview, capability matrix with exact prerequisite packages per build option, full configuration reference, operational runbooks (deploy, migrate, back up, restore, fail over, drain, rotate keys), measured benchmark numbers from `src/benchmark.zig` with the hardware stated, and an explicit "not implemented / known limitations" section. No README claim may lack a test or a documented build option behind it.
4. `ARCHITECTURE.md`: heap layout, WAL record formats as field tables, checkpoint format, key-space layout, recovery algorithm, concurrency and isolation model, sandbox lifecycle, security model with threat model and trust boundaries, dependency justifications.
5. `CHANGELOG.md`: per phase, what was fake and what is now real, plus every breaking change with its migration step.
6. **Final verification gate — all must pass on a clean clone of the branch:**
   - `zig fmt --check src build.zig`
   - `zig build -Doptimize=Debug`, `-Doptimize=ReleaseSafe`, `-Doptimize=ReleaseFast`
   - `zig build test`, `zig build test-integration`, leak-check step
   - `zig build dst` over the seed corpus and `zig build dst-soak`
   - End-to-end: start `agdb-cloud`, create a tenant, ingest ≥100k records, run BM25, vector, and hybrid queries, `kill -9` mid-ingest, restart, verify every acknowledged write survived, no partial record exists, and indexes agree with records
   - Sandbox lifecycle: 100 start/stop cycles with zero zombies, zero stray mounts, zero stray cgroups, flat RSS
   - HTTP load test from Phase 7
   - Secret scan clean on tree and history
   - `grep -rniE "TODO|FIXME|mock|stub|dummy|placeholder|not implemented|simulated|fake" src/` matches only fault-injection/DST test modules, each with a comment justifying the term
   - Performance guardrails, measured and recorded: single-node point `get` p99 under 1 ms on warm data, ingest throughput not worse than the pre-upgrade `kv.zig` baseline by more than 2× for durable commits (`fsync` on), recovery of a 1 GB WAL under 60 s. Any guardrail you cannot meet must be reported with measurements and an analysis, not silently dropped.

---

## 6. Reporting format (required for every phase)

Before coding: list the files you will create, modify, or delete, and the exact public interfaces (types, functions, error sets) you will introduce, plus the risks and the rollback step for that phase.

After coding: list the commands you ran with their outputs, the tests added and what each proves, the defect IDs closed, and anything deferred with the reason. If a requirement cannot be executed in the environment — for example no RDMA hardware, no TPM, no GPU — compile the real implementation, state precisely what was not executed and why, and give the exact command an operator must run on suitable hardware to validate it. Never substitute a fake implementation, never mark a phase done on untested code, and never claim a result you did not observe.

## 7. Deliverables

- Complete, compiling source for every file touched; no omitted bodies.
- Updated `build.zig`, `build.zig.zon`, `build.sh`, `Makefile`, `run.sh`, `deploy.sh`, `nginx.conf`, `replit.nix`, `.replit`, systemd units, `.env.example`, `.gitignore`, `.github/workflows/ci.yml`.
- `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `BASELINE.md`, seed corpus `tests/seeds.txt`.
- Ten commits (Phases 0–9) on the current working branch, and a pull request whose description contains the §2 table with commit hashes, the probed capability matrix, the migration and rollback procedure, measured performance numbers, and the explicit statement that the disclosed OVH project ID, instance ID, and server IP must be rotated.
