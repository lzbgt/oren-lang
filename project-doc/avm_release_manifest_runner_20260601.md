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
- `host_effects`: expected host artifact assertions such as absent files.

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

The current manifest covers the curated release-gate set, one non-gate VPROC
fixture, the default-safe language/container fixtures, and default-safe
byte/int/call-stack/hash, varargs call/spread/spawn, task/group scheduler,
deterministic join-timeout, and bounded trace diagnostic fixtures. The next completeness step
is to add explicit release inclusion/exclusion and policy metadata for the
remaining host-effect, budget, record/replay, snapshot, and multiverse fixtures,
then gate the full wildcard path when the expected budgets/backends are declared.
