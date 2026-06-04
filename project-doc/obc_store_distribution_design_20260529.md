# OBC Store Distribution Design

Yes: after the GUI bridge is usable, a public Git repository can distribute OBC
programs as app experiences. The iPhone app can download signed OBC packages,
show metadata/screenshots, run them inside `libavm`, and map portable Oren APIs
to app capabilities such as graphics, VFS, virtual network, virtual process,
time, stdout, and future input mailboxes.

The store should not distribute raw, unindexed `.obc` blobs as the main contract.
It should distribute small signed packages with a machine-readable manifest,
capability declaration, compatibility constraints, hashes, and optional assets.

## Product Model

- **Oren program author** publishes source and release artifacts.
- **OBC store site** should be `store.hubstack.cn`, a PyPI-like public service
  for release, discovery, metadata, and download of curated OBC packages.
- **OBC store repo/storage** stores immutable package releases and a signed index.
- **iOS Note app** fetches the index, filters compatible packages, downloads a
  selected package, verifies signatures/hashes, and runs it through `libavm`.
- **libavm** enforces package capabilities, budgets, deterministic or interactive
  time mode, and bridge mailboxes.
- **Host adapter SDK** renders GUI packages through `std:gfx` command buffers and
  sends input events back to AVM.

This makes the app experience similar to installing mini-programs, but the trust
boundary stays strict: an OBC package is data executed by AVM under declared
capabilities, not native iOS code.

## Package Layout

Recommended package directory:

```text
packages/<publisher>/<name>/<version>/
  package.json
  program.obc
  assets/
    icon.png
    data/
      optional-fixture.bin
  screenshots/
    iphone-01.png
    iphone-02.png
  README.md
  signature.minisig
```

`program.obc` is the executable bytecode. Assets are optional and should be
treated as VirtualFS inputs, not arbitrary host filesystem paths. Screenshots are
store presentation metadata outside `package.json` assets and outside the
client-installable `.obc.zip` bundle.

The portable release artifact should also be available as a deterministic ZIP
bundle. The ZIP mirrors the rootless package layout above, uses media type
`application/vnd.oren.obc.release+zip`, and should normally use an `.obc.zip`
extension. The expanded directory remains the server/install layout; the ZIP is
for upload, download, mirroring, archive, and offline handoff. Bundle details are
specified in `project-doc/obc_release_bundle_spec_20260601.md`.

## Manifest Contract

Minimum `package.json` shape:

```json
{
  "schema": "oren.obc.package.v0",
  "name": "plot-demo",
  "publisher": "oren-labs",
  "version": "0.1.0",
  "title": "2D Plot Demo",
  "summary": "Interactive scientific plotting example.",
  "entry_obc": "program.obc",
  "obc_sha256": "<hex>",
  "source_commit": "<optional-git-commit>",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 3,
  "stdlib_bundle": "stdlib_bundle.obc",
  "capabilities": ["CORE", "TIME", "GFX", "INPUT"],
  "permission_defaults": [
    {
      "domain": "NET",
      "action": "connect",
      "detail": "https://api.example.invalid",
      "granted": false,
      "reason": "Optional demo data sync"
    }
  ],
  "time_mode": "interactive",
  "budgets": {
    "gas": 5000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 20000
  },
  "vfs_mounts": [
    { "virtual": "/assets/", "package_path": "assets/data/", "read_only": true }
  ],
  "sources": [
    { "path": "assets/source/main.oren", "language": "oren", "role": "main" }
  ],
  "ui": {
    "kind": "gfx",
    "canvas": { "width": 390, "height": 844, "scale": "device" },
    "requires_input": true
  }
}
```

Rules:

- The manifest declares capabilities before execution. The host must never infer
  permissions from code behavior after launch.
- `permission_defaults` is optional host-facing policy metadata. Entries declare
  proposed persisted grants or revocations (`domain`, `action`, optional `detail`,
  optional boolean `granted`, and UI metadata such as `reason`). The SDK never
  applies them implicitly; a host app must explicitly apply them after store policy
  or user confirmation.
- `time_mode` is explicit. Scientific simulations can use deterministic time;
  interactive UI demos can use wall-clock `avm_embed_config_interactive_default`.
- Interactive network should use host-backed VNET providers by default when the
  host policy grants it; deterministic tests can still use VirtualNET fixtures.
- Process execution should stay VirtualPROC on iOS.
- GUI packages require the future `GFX` capability and frame mailbox.
- Source code is optional for third-party packages and required for official
  demos. If included, it should be declared as normal hashed assets and listed in
  `sources`; host apps may choose to display, cache, recompile, or ignore it.

## Store Index

The root repo should publish a compact signed index:

```text
index.json
index.minisig
bundles/...
packages/...
```

Index shape:

```json
{
  "schema": "oren.obc.store.index.v0",
  "generated_at": "2026-05-29T00:00:00Z",
  "packages": [
    {
      "id": "oren-labs/plot-demo",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/plot-demo/versions/0.1.0/package.json",
      "manifest_sha256": "<hex>",
      "bundle": "packages/oren-labs/plot-demo/versions/0.1.0/bundle.obc.zip",
      "bundle_sha256": "<hex>",
      "bundle_media_type": "application/vnd.oren.obc.release+zip",
      "tags": ["science", "plot", "gfx"],
      "min_app": "0.1.0"
    }
  ]
}
```

The app downloads `index.json`, verifies `index.json.sig`, then downloads package
manifests and OBC files by hash. The canonical store host should be
`store.hubstack.cn`. It should serve the same signed index/package schema as a
real package registry, while static Git storage or CDN mirrors can back immutable
artifacts behind that store site. A normal public Git repository can still be used
for early fixture development, but the product endpoint for host apps should be
the store site.

## Store Site Contract

`store.hubstack.cn` should act like a small PyPI-style registry for OBC packages:

- publish package pages with title, summary, screenshots, capabilities, publisher,
  versions, hashes, signatures, compatibility metadata, and rendered source views
  for declared Oren source assets;
- serve signed machine-readable indexes such as `/obc/index.json` and
  `/obc/index.json.sig`;
- serve immutable package manifests, `program.obc`, deterministic `.obc.zip`
  release bundles, assets, and per-release signatures by content-hashed or
  versioned paths;
- expose a publisher upload/release workflow that signs metadata outside the web
  server and never stores private signing keys in this repo;
- make packages public by default, while allowing publishers/admins to mark a
  package private; private packages are excluded from public browse/search/index
  and unauthenticated downloads, but remain available to authenticated owner/admin
  APIs;
- keep all package execution decisions in the host app: trust policy, untrusted
  run confirmation, permissions, budgets, and install/update/remove lifecycle.

The store site must not be a raw code-execution authority. It distributes signed data;
AVM and the host SDK enforce capabilities and runtime limits.

Deployment note: the host is expected to be reachable by SSH with trusted certs
and fronted by Traefik for domain routing. Deployment automation should still
treat private signing keys/root CA material as external to this repo.

API/service detail lives in `project-doc/obc_store_service_design_20260601.md`.

## iOS App Flow

1. Fetch signed `index.json` from `store.hubstack.cn` or a configured mirror.
2. Filter packages by `avm_abi_min`, required capabilities, app version, and GUI
   support.
3. Download the release ZIP bundle when `bundle`/`bundle_sha256` are advertised,
   otherwise download `package.json`, `program.obc`, and selected assets
   individually.
4. Verify package signature, bundle or asset hashes, manifest hash, and OBC hash.
5. Create an `AvmEmbedConfig`.
6. Apply capabilities and budgets from the manifest.
7. Use deterministic default config for reproducible/headless packages, or
   `avm_embed_config_interactive_default(...)` for wall-clock UI packages.
8. Inject package assets into VirtualFS with `avm_embed_vfs_put(...)`.
9. Run OBC on an AVM worker thread, not the iOS main thread.
10. For GUI packages, attach the graphics mailbox to the host adapter SDK view.
11. Surface stdout, result, errors, and capability-denial diagnostics in the app UI.

## GUI Dependency

Without the GUI bridge, an OBC store can still distribute command-line or
calculation packages, but the iPhone user experience is limited to input forms,
stdout, files, and result values.

With the GUI bridge ready, OBC packages become visible app experiences:

- scientific plots;
- calculators and notebooks;
- simulations;
- educational animations;
- small 2D/3D demos;
- data viewers.

The Oren code still uses portable APIs such as `std:gfx`, `std:input`,
`std:time`, `std:fs`, and `std:net`. The iOS app only supplies adapters and
capabilities.

## Security Boundary

- OBC packages are untrusted by default.
- Every host effect requires an explicit capability.
- Package signatures prove publisher identity; OBC hashes prove artifact
  integrity.
- The app should refuse packages with unknown schema versions or unsupported AVM
  ABI requirements.
- Runtime budgets must be enforced by AVM, not by UI convention.
- Host filesystem/network/process access should remain unavailable unless a
  reviewed bridge explicitly implements it.

## Release Gates

Before publishing an official public OBC store:

1. `make verify-libavm-ios` proves iOS device/simulator linkage and app-style
   OBC execution.
2. The graphics bridge has a bytecode fixture, host C smoke, and iOS adapter
   smoke.
3. A package verifier validates manifests, hashes, signatures, capabilities, and
   budget bounds.
4. The iOS Note app can download a signed fixture package, verify it, run it,
   render one GUI frame if applicable, and report failure diagnostics.
5. The stdlib bundle manifest records which modules are available to store
   packages and why excluded modules are excluded.

Current implementation status: the iOS SDK now has local and HTTP-index
`OrenAVMPackageStore` verifier/runner slices. It validates package schema,
required manifest fields, AVM ABI floor, indexed manifest SHA-256, `program.obc`
SHA-256, package capabilities, budget/time-mode runtime config, and read-only
package asset mounts before running the OBC. It can fetch `index.json`, download
the selected manifest/OBC plus declared assets into an app-owned install directory,
verify each asset SHA-256, and run the package through the same local verifier
path. The iOS SDK also has a signed download overload for publisher signatures:
host apps pass trusted P-256 public keys by publisher ID, and the SDK verifies
`p256-sha256-der` signatures over indexed manifest hashes before install.
A signed-index overload also fetches and verifies `index.json.sig` with a trusted
P-256 store key before trusting package entries. Signature/cert enforcement is
host policy: apps should default to trusted metadata, but may expose an explicit
user-confirmed "run untrusted OBC" path. The SDK also has persisted app-directory
lifecycle helpers for list, load, and remove installed packages, and remote installs
stage into a temporary package directory before replacing the final package path.
Signed-index installs now expose replace, keep-existing, and fail-if-installed
policies so host apps can make update behavior explicit. The store service also
has a package update-check endpoint that returns the semver-selected latest
published release plus an `update_available` flag, and the iOS SDK exposes
`OrenAVMPackageUpdateStatus` so host apps can consume that endpoint before
choosing an install policy. `OrenAVMOBCTrustBundle`
loads generated `obc_store_trust.json` files into validated SDK key material, so
host apps no longer need to hand-parse trust bundles before signed downloads. The
store service now publishes active signing key IDs on dynamic index signatures and
can serve rotation bundles containing active plus previous store public keys. The
sibling Note repo has a handoff/verifier update at commit `35995ee` that checks
the staged SDK for signed package downloads, install policies, trusted key inputs,
and the external trust issue tool. Remaining store work is richer update
UX/persistence and visible Note install/update/remove UX before a public store is
release-ready.

Key custody rule: private signing keys and any root CA material must live outside
this repo, recommended at `../oren-ca/` for local multi-repo bring-up. This repo
may document paths and commit public trust anchors or test public keys, but must
not commit private keys. Sibling apps such as `../note` should consume a public
trust bundle or a local config path that points at `../oren-ca/` during development.
The helper tool `scripts/issue_obc_store_trust.sh` creates the current P-256 store
and publisher signing material plus a public trust bundle in that external
directory, and can include previous store public keys for root rotation; see
`project-doc/obc_store_trust_tooling_20260601.md`.

## Initial Public Repo Shape

Suggested public repository:

```text
store.hubstack.cn backing store or mirror repo:
  README.md
  index.json
  index.json.sig
  schemas/
    package.v0.schema.json
    index.v0.schema.json
    release-bundle.v0.md
  bundles/
    oren-labs__plot-demo__0.1.0.obc.zip
  packages/
    oren-labs/
      hello/
      plot-demo/
      calculator/
  tools/
    verify_store.py
    pack_obc.py
```

Start with a tiny curated store. Do not accept third-party packages until the
signature, review, package verifier, and app install UX are stable.

## Decision

Create the public OBC store after the GUI bridge reaches its first release gate.
Until then, design the package/index schema and verifier inside this repo so the
iOS app integration can be tested with local fixture packages first.
