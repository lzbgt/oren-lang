# Start Here: Oren Docs (Canonical)

**Last updated:** 2026-03-05

This file is the single **entry point** for the Oren docs. It merges the former root README
orientation with the docs index so you can start in one place and branch out only when needed.

## 0) What Oren is (fast orientation)

Oren is a **self-hosted language + compiler** with three execution backends:

- **C backend**: portable bootstrap path via a host C toolchain.
- **Native backend**: direct Mach-O/ELF/PE output (Tier‑1 intent).
- **Bytecode backend (OBC)**: `.obc` for the AVM (deterministic, capability-governed VM).

Design intent (rolling): deterministic execution for agent workflows, capability-gated effects,
and a path to compiler-in-AVM for sandboxed compilation.

## 1) Current reality (backends + platforms)

- **C backend (default)**: used in the stage0→stage1 chain and portable to any host with `cc`.
- **Native backend (Tier‑1 intent)**: arm64 is most mature; x86_64 Linux/Windows are in rolling bring‑up.
- **Bytecode backend (experimental)**: emits `.obc` for AVM; format and semantics are still evolving.

Tier‑1 intent targets (rolling): `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

## 2) Quick start (fast path)

Build + test:

```bash
make bootstrap   # build stage0 Go compiler
make            # build stage1 self-hosted compiler
make test       # fast native smoke
make verify-native-quick-gc  # includes forced-GC quick integration (stage2)
make verify-runtime-robustness  # W5 runtime robustness smoke (stage2 + C-backend builds)
make verify-backend-parity  # cross-backend parity smokes (C/native/obc)
make readiness-report  # generates build/reports/readiness_report_*.md
make readiness-report-json  # readiness report + JSON summary
make readiness-report-index  # append JSONL summary to build/reports/readiness_index.jsonl
make readiness-report-summary  # generates markdown + HTML summary from index
make readiness-report-index-stats  # index stats (md + json)
make readiness-report-index-prune  # prune index to last N entries
make readiness-report-index-trim  # trim index by timestamp range
make readiness-report-index-csv  # export index to CSV
make readiness-report-index-query  # filter index by fields/time
make readiness-report-index-rollup  # daily rollup (md + json)
make readiness-report-index-latest  # latest entry by profile/tag
make readiness-report-index-trend  # trend summary over latest window
make readiness-report-index-profiles  # per-profile summary
make readiness-report-index-tags  # per-tag summary
make readiness-report-index-audit  # audit index paths
make readiness-report-collect  # collect last N reports into snapshots
make readiness-report-collect-list  # list collected snapshots
make readiness-report-collect-pack  # pack collected snapshots into tar.gz
make readiness-report-sanitize  # sanitize report + json for sharing
make readiness-report-index-diff  # diff two index files
make readiness-report-index-diff-summary  # diff summary stats
make readiness-report-index-gate  # enforce pass/fail thresholds
make readiness-report-index-lint  # check ordering/duplicates
make readiness-report-index-split  # split index by profile/tag
make readiness-pipeline  # run report + summary + stats + validate in one shot
make status-snapshot  # snapshot docs/STATUS.md into build/reports
make status-snapshot-diff  # diff STATUS.md snapshots
make status-matrix  # render readiness matrix from STATUS.md
make status-matrix-diff  # diff readiness matrices or STATUS.md
make verify-readiness-report  # dry-run smoke for readiness report script
make verify-readiness-report-summary  # smoke for summary generator
make verify-readiness-report-index-tools  # smoke for index tools
make verify-readiness-report-index-trim  # smoke for index trim
make verify-readiness-report-index-latest  # smoke for index latest
make verify-readiness-report-index-trend  # smoke for index trend
make verify-readiness-report-index-profiles  # smoke for index profiles
make verify-readiness-report-index-tags  # smoke for index tags
make verify-readiness-report-index-audit  # smoke for index audit
make verify-readiness-report-collect  # smoke for report collect
make verify-readiness-report-collect-pack  # smoke for report collect pack
make verify-readiness-report-sanitize  # smoke for report sanitize
make verify-readiness-pipeline  # smoke for pipeline
make verify-status-snapshot  # smoke for status snapshot
make verify-status-snapshot-diff  # smoke for status snapshot diff
make verify-status-matrix  # smoke for status matrix
make verify-status-matrix-diff  # smoke for status matrix diff

# Optional knobs for runtime robustness:
# - OREN_RUNTIME_ROBUSTNESS_RUNS, OREN_RUNTIME_ROBUSTNESS_COMPILER
# - OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS, OREN_RUNTIME_ROBUSTNESS_C_RUNS
# - OREN_RUNTIME_ROBUSTNESS_C_FIXTURES, OREN_RUNTIME_ROBUSTNESS_TRACE_ENV
```

Readiness report profiles:

```bash
make readiness-report-minimal  # native quick only
make readiness-report          # quick (native quick + backend parity)
make readiness-report-full     # quick + GC stress + runtime robustness
```

Readiness report flags (optional):

```bash
./scripts/readiness_report.sh --json
./scripts/readiness_report.sh --index
./scripts/readiness_report.sh --tag nightly
./scripts/readiness_report.sh --no-status-snippet
./scripts/readiness_report.sh --status-snapshot
./scripts/readiness_report.sh --status-path docs/STATUS.md
./scripts/readiness_report.sh --include-env
```

Latest report pointers (written on real runs):

- `build/reports/readiness_latest.md`
- `build/reports/readiness_latest.json`
- `build/reports/readiness_latest.meta`

Summary outputs (from index):

- `build/reports/readiness_summary.md`
- `build/reports/readiness_summary.html`
- `build/reports/readiness_dashboard.html`

Index stats outputs:

- `build/reports/readiness_index_stats.md`
- `build/reports/readiness_index_stats.json`

Index CSV output:

- `build/reports/readiness_index.csv`

Rollup outputs (daily):

- `build/reports/readiness_rollup.md`
- `build/reports/readiness_rollup.json`

Pipeline (single entrypoint):

```bash
./scripts/readiness_pipeline.sh --profile quick --tag nightly
./scripts/readiness_pipeline.sh --profile full --prune 200
./scripts/readiness_pipeline.sh --profile quick --no-csv
./scripts/readiness_pipeline.sh --profile quick --rollup-days 14
./scripts/readiness_pipeline.sh --profile quick --log build/logs/readiness_pipeline_manual.log
./scripts/readiness_pipeline.sh --profile quick --diff-against build/reports/readiness_index.jsonl
./scripts/readiness_pipeline.sh --profile quick --gate-pass-rate 80 --gate-window 20
./scripts/readiness_pipeline.sh --profile quick --trim-since-days 30
./scripts/readiness_pipeline.sh --profile quick --no-status-snapshot
./scripts/readiness_pipeline.sh --profile quick --status-diff-against docs/STATUS.md
./scripts/readiness_pipeline.sh --profile quick --no-latest-summary
./scripts/readiness_pipeline.sh --profile quick --trend-window 50
./scripts/readiness_pipeline.sh --profile quick --no-trend
./scripts/readiness_pipeline.sh --profile quick --no-profile-summary
./scripts/readiness_pipeline.sh --profile quick --no-tag-summary
./scripts/readiness_pipeline.sh --profile quick --audit --audit-allow-missing
./scripts/readiness_pipeline.sh --profile quick --collect 3 --collect-copy-logs
./scripts/readiness_pipeline.sh --profile quick --collect 3 --collect-copy-logs --collect-pack
./scripts/readiness_report_sanitize.py --report build/reports/readiness_latest.md --json build/reports/readiness_latest.json
./scripts/readiness_pipeline.sh --profile quick --no-dashboard
```

Build and run a hello binary (C backend by default):

```bash
./oren build examples/hello.oren -o hello
./hello
```

Run test blocks with the built-in test runner:

```bash
./oren test tests/fixtures/test_runner_smoke.oren --backend native
```

Emit bytecode and run under AVM:

```bash
./oren build examples/hello.oren --backend bytecode -o hello.obc
make avm
./avm hello.obc
```

Details and platform-specific notes live in:

- `docs/DESIGN.md` — design + toolchain, build/test/self-hosting, Tier‑1 targets, portability notes, remote x64 workflow

## 3) Benchmarks (perf sanity)

Local cross-backend microbenchmarks live under `benchmarks/`:

- How to run: `benchmarks/README.md`
- Latest snapshot: `benchmarks/RESULTS_LATEST.md`

## 4) Canonical doc map (read only what you need)

**Start here / trackers**

- `docs/STATUS.md` — task tracker + feature matrix, gaps, roadmap, agentic requirements
- `docs/BLEEDING_EDGE_TASKS.md` — bleeding-edge goals + derived task buckets
- `docs/READINESS.md` — readiness report schema + tooling
- `docs/readiness_index.schema.json` — JSON schema for readiness index entries

**Language (user-facing)**

- `docs/LANGUAGE.md` — manual + spec + appendices (single canonical language doc)

**Design + toolchain (compiler/runtime/AVM/platforms)**

- `docs/DESIGN.md` — architecture, backends, runtime layering, AVM/OBC summary, and toolchain/platform notes
- `docs/design/tagged_values.md` — staged tagged-value convergence plan and migration gates
- `docs/design/arena_loop_policy.md` — loop arena policy + GC reuse safety (alloc/GC perf track)
- `docs/design/alloc_index_dedup.md` — alloc-index de-dup for `track_alloc_new` under reuse/GC churn
- `scripts/suggest_alloc_index_dedup_cap.sh` — suggest a `dedup_hits` guardrail cap from logs

## 5) Rolling policy (no stubs)

This repo is in rolling mode: remove empty or duplicate docs instead of keeping stubs.
When a doc is merged, update this map and keep exactly one canonical place for each topic.
