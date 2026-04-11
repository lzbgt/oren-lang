# Capability Runtime Contract

**Last updated:** 2026-04-12

This is the current Oren v0 contract for capability-governed execution and native
runtime profiles. It is a rolling engineering contract, not a security certification:
the code and fixtures below define what users can rely on today, and `docs/STATUS.md`
tracks the gaps.

## Why This Exists

Oren's product thesis is deterministic, capability-governed execution across native
and AVM bytecode backends. That requires a stable vocabulary for:

- which host-effect domains exist;
- which runtime profile a native build injects;
- where compile-time capsule checks end and runtime allowlists begin;
- which verification targets prove the contract.

## Native Runtime Profiles

Native builds select one injected runtime entry file:

| Profile | Entry file | Selection | Contract |
| --- | --- | --- | --- |
| `core` / `minimal` | `lib/runtime_native_core.oren` | `OREN_NATIVE_RUNTIME_PROFILE=core` or `minimal`; also the default `auto` seed profile | Smaller non-capsule runtime for typical programs. Includes capsule stubs, core typed buffers, file/path helpers, select, threads, yield, SHA-256, time, RNG, env helpers, and basic IO. Excludes heavy HPC typed-buffer kernels, TCP/UDP networking, `oren_net_get`, AVM bridge, and AVM-only helpers. |
| `full` | `lib/runtime_native.oren` | `OREN_NATIVE_RUNTIME_PROFILE=full`, or `auto` when the native compiler sees `std:net/*` imports | Full non-capsule runtime. Includes TCP/UDP, full typed-buffer/HPC surfaces, `oren_net_get`, and the AVM bridge. It uses permissive capsule stubs, not capsule syscall hooks. |
| `capsule` | `lib/runtime_native_capsule.oren` | `./oren build ... --backend native --capsule` or platform capsule mode | Capsule-enabled native runtime. Includes `runtime_native/040_capsule_core.oren`, FS/NET/proc/time syscall hooks, and the full-runtime networking, typed-buffer, and AVM bridge surfaces behind domain checks. Capsule selection takes precedence over `OREN_NATIVE_RUNTIME_PROFILE`. |

The arm64 and x64 native backends use the same selection policy. The seed builder
mirrors it: `scripts/build_rtobj_seed.sh --capsule` seeds the capsule entry, while
`--runtime-profile <full|core|minimal>` seeds non-capsule entries.

## Capability Layers

Oren has three capability layers today.

1. **Native compile-time capsule layer.**
   Capsule mode rejects calls to functions annotated with
   `@cap.requires(domain="FS|NET|PROC|ENV|TIME|RNG")` unless the domain is enrolled
   with `--cap-allow-domains` or `OREN_CAP_ALLOW_DOMAINS`. It also rejects direct
   user `sys_*` intrinsics and `ffi` declarations in capsule mode.

2. **Native runtime allowlist layer.**
   The capsule runtime maps enrolled domains to concrete resource allowlists. For
   example, enrolling `FS` permits the domain, but the runtime still checks mounts
   or path prefixes before allowing host filesystem access.

3. **AVM policy layer.**
   The bytecode backend tags effectful native calls by AVM domain. The AVM can run
   with allowed-domain masks, VirtualFS/VirtualNET/VirtualPROC-style fixtures,
   budgets, snapshots, and record/replay surfaces for deterministic effect handling.

## Source Metadata Manifest

`oren meta <file.oren> -o out.meta.json` and native `--metadata` output now include
normalized package/capability manifests in addition to the raw declaration attributes:

```json
{
  "package": {
    "version": 1,
    "declared": false,
    "runtime_profile": null,
    "cap_allow_domains": [],
    "source_required_domains": ["FS", "TIME", "RNG"],
    "dependency_domain_union": ["FS", "TIME", "RNG"],
    "dependency_domain_union_status": "source_attrs_only",
    "budgets": { "version": 1, "declared": false }
  },
  "capabilities": {
    "version": 1,
    "required_domains": ["FS", "TIME", "RNG"],
    "functions": [
      { "name": "read_fs", "domains": ["FS"] },
      { "name": "timed_random", "domains": ["TIME", "RNG"] }
    ]
  }
}
```

This manifest is an introspection and tooling contract. It does not replace capsule
enforcement: native capsule checks still reject disallowed annotated calls at build time,
and the capsule runtime still applies resource allowlists at runtime. The manifest gives
package tooling, build orchestrators, and agent-facing planners a deterministic way to see
which source-level functions require host-effect domains before selecting a runtime profile
or policy.

`dependency_domain_union` is intentionally marked `source_attrs_only`: it is the linked
source-level `@cap.requires` union, not yet a full stdlib/runtime effect proof.

Artifact `--manifest` output also carries a policy block that ties the artifact hash to
the source capability domains and selected build-policy inputs:

```json
{
  "version": 1,
  "kind": "native",
  "sha256": "...",
  "policy": {
    "version": 1,
    "backend": "native",
    "runtime_profile": "auto",
    "runtime_path": "backend-auto",
    "capsule": false,
    "cap_allow_domains": ["FS"],
    "source_required_domains": ["FS", "TIME", "RNG"],
    "source_package": {
      "version": 1,
      "declared": true,
      "runtime_profile": "capsule",
      "cap_allow_domains": ["FS"],
      "source_required_domains": ["FS", "TIME", "RNG"],
      "dependency_domain_union": ["FS", "TIME", "RNG"],
      "dependency_domain_union_status": "source_attrs_only",
      "budgets": { "version": 1, "declared": true, "cpu_ms": 10 }
    },
    "source_package_check": {
      "version": 1,
      "declared": true,
      "status": "mismatch_observed",
      "runtime_profile": {
        "declared": "capsule",
        "actual": "none",
        "status": "backend_not_runtime_profiled"
      },
      "cap_allow_domains": {
        "declared": ["FS"],
        "actual": ["FS"],
        "missing": [],
        "status": "covers"
      },
      "budget_status": "declared_not_enforced"
    },
    "budgets": { "version": 1, "declared": false }
  }
}
```

`runtime_profile` is the build-policy request. In the native default `auto` mode, the
backend still resolves the concrete runtime path from env/import heuristics, so
`runtime_path` is `backend-auto` rather than a false claim about a final path. Budget
declarations are explicitly marked absent until source/package-level budget syntax exists.

Source files can now declare a first package-policy marker through a declaration
attribute:

```oren
@oren.package(runtime_profile="capsule", cap_allow_domains="FS,ENV", budget_cpu_ms=10)
var package_policy = 1
```

That marker is metadata-only. It does not silently enable capsule mode or enforce budgets.
It normalizes into `metadata.package` and artifact `policy.source_package`. Artifact
manifests also emit observe-only `policy.source_package_check` status so package tooling
can compare declared intent against actual build flags and runtime-profile request without
turning that comparison into enforcement yet.

## Domain Contract

| Domain | Native capsule meaning | Runtime knobs / AVM notes |
| --- | --- | --- |
| `CORE` | Pure/core execution. Native capsule code does not require an explicit `CORE` allow bit. | AVM domain `CORE` is domain `0` and is used for pure/core VM calls. |
| `FS` | Files, paths, stat/readdir, binary IO, and filesystem syscalls. | Native: `OREN_FS_MOUNTS`, `OREN_FS_MOUNTS_READ`, `OREN_FS_MOUNTS_WRITE`, `OREN_FS_ALLOW_PREFIXES`, `OREN_FS_ALLOW_READ_PREFIXES`, `OREN_FS_ALLOW_WRITE_PREFIXES`. AVM: FS domain plus VirtualFS and host-FS policy fixtures. |
| `NET` | TCP/UDP/socket surfaces and network syscalls. | Native: `OREN_NET_ALLOW_LOOPBACK`, `OREN_NET_ALLOW_TCP_CONNECT`, `OREN_NET_ALLOW_TCP_LISTEN`, `OREN_NET_TCP_CONNECT_MAP`, `OREN_NET_TCP_LISTEN_MAP`. AVM: NET domain plus VirtualNET/multiverse fixtures. |
| `PROC` | Process spawn, system shell helpers, process-related syscalls, threads, wait/kill ownership edges, and controlled child environment. | Native: `OREN_PROC_ALLOW_EXEC_PREFIXES`, `OREN_PROC_ALLOW_SYSTEM`, `OREN_PROC_INHERIT_ENV`, `OREN_PROC_ALLOW_ENV_KEYS`, `OREN_PROC_ALLOW_ARGV`. AVM: PROC domain plus VirtualPROC/multiverse fixtures. |
| `ENV` | Environment variable reads. | Native: `oren_env` / `oren_getenv` are annotated with `ENV`; capsule-denied `oren_getenv` reads return `0`, so `oren_env` returns `nil`. AVM: ENV is domain `7` and is covered by record/replay env fixtures. |
| `TIME` | Wall-clock, sleep, wait, and time-adjacent syscall hooks. | Native: `@cap.requires(domain="TIME")` plus capsule syscall hooks. AVM: TIME is domain `2`; deterministic and record/replay fixtures cover time behavior. |
| `RNG` | Entropy and random-number APIs. | Native: `@cap.requires(domain="RNG")`. AVM: RNG is domain `3`; deterministic and record/replay fixtures cover random behavior. |
| `EXIT` | Process or VM exit behavior. | Native process exit is not a native capsule allow bit today. AVM: EXIT is domain `6` so replay and nested VM runs can model exit as data instead of terminating the host process early. |
| `AVM` | Nested bytecode execution from native full runtime through the AVM bridge. | Native: the bridge is in the full and capsule runtimes, not the core runtime. AVM: AVM is domain `8` for nested multiverse execution. |

## Failure Model

- Native compile-time capsule failures are hard build errors: disallowed annotated
  calls, direct user `sys_*` intrinsics, and `ffi` declarations are rejected before
  native code is emitted.
- Native runtime capsule failures fail closed. The runtime prints `CAPSULE DENY: ...`
  diagnostics with hints for the relevant domain or resource allowlist, then uses
  the policy-specific failure path for that API.
- AVM failures are VM policy errors or structured VM results. Record/replay fixtures
  must keep effect behavior deterministic and must not accidentally terminate the
  host process from inside replayed or nested execution.

## What Is Not Stable Yet

- The native runtime profile is still selected by env/import heuristic, not enforced by
  the package marker. The source package marker records declared intent for tooling only.
- `policy.source_package_check` is observe-only. It can report `mismatch_observed`, but the
  compiler does not reject the artifact on that basis yet.
- Capability budgets are now representable in package metadata, but they are not yet a
  complete enforcement contract across native and AVM. AVM has budget machinery; native
  capsule runtime knobs are domain/resource allowlists first.
- The native and AVM policy vocabularies are converging but not fully unified. For
  example, AVM has explicit `CORE`, `EXIT`, and `AVM` domains while native capsule
  enrollment currently focuses on `FS`, `NET`, `PROC`, `ENV`, `TIME`, and `RNG`.

## Verification Map

Use these targets when changing the capability or runtime-profile contract:

```sh
make verify-capability-runtime-contract
make verify-capability-metadata
make verify-capability-manifest-policy
make test-native-capsule-smoke-stage2
make test-avm
make verify-backend-parity
make test
```

Important fixture families:

- Native capsule compile-time and runtime fixtures: `tests/native/fixtures/capsule_*.oren`
  and `tests/native/fixtures/capsule_runtime_*.oren`.
- Source-level capability metadata fixture: `tests/fixtures/meta_capabilities_src.oren`.
- AVM policy, record/replay, budget, snapshot, and multiverse fixtures: `tests/avm/`.
- Cross-backend semantic parity smokes: `make verify-backend-parity`.
- Contract drift guards: `scripts/verify_capability_runtime_contract.sh` and
  `scripts/verify_capability_metadata.sh`.
