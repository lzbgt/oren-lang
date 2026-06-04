# AVM Release Manifest Runner

**Date:** 2026-06-01

## Decision

AVM release fixtures should be driven by an explicit manifest instead of Makefile
case arms. The release manifest is:

```text
tests/avm/release_manifest.json
```

The runner is:

```text
scripts/verify_avm_release_manifest.py
```

`make test-avm` now calls the runner while preserving the existing `AVM_TESTS`
override surface.

## Manifest Contract

The schema is `oren.avm.release_manifest.v0`. Each case is merged with manifest
defaults and must resolve these fields:

- `path`: fixture source path;
- `release_gate`: whether the fixture is part of the default release gate;
- `expected.exit_code` and `expected.error_contains`;
- `env`: budget and runtime environment variables;
- `avm_args`: AVM CLI backend/capability policy;
- `deterministic`: whether the case is expected to be deterministic;
- `backend_policy`: human-readable backend policy label;
- `budgets`: structured budget metadata;
- `setup_dirs`: host directories to create before running the fixture;
- `setup_builds`: child bytecode builds to materialize before running the fixture;
- `host_effects`: expected host artifact assertions such as absent files;
- `phases`: optional multi-run phase records for record/replay, snapshot/resume,
  state-hash, and trace repeat fixtures;
- `captures` / `assertions`: line-prefix captures such as `RECORD_LOG_HEX`,
  `STATE_HASH`, and `TRACE_BYTES_HEX`, plus cross-phase equality, inequality,
  presence, and non-empty assertions.

This makes fixture policy reviewable as data and removes hidden expectations from
Makefile shell branches.

## Commands

```bash
make verify-avm-release-manifest
make test-avm
make test-avm AVM_TESTS="tests/avm/test_vproc_fixtures.oren"
```

If `AVM_TESTS` includes a path not present in the manifest, the runner applies
default zero-exit virtual-backend policy. Release-grade fixtures should be added
to the manifest with explicit metadata instead of relying on defaults.

## Next Work

The current manifest covers every tracked `tests/avm/test_*.oren` fixture with
explicit metadata, including record/replay, snapshot/resume, state-hash, trace,
nested multiverse AVM/VNET/VPROC/VFS, VFS inheritance plus host-prefix
inheritance, and child-bytecode setup builds. The next completeness step is no
longer manifesting existing fixtures; it is adding new release cases only when
new AVM/runtime surfaces are introduced or when focused fixtures expose a real
gap.
