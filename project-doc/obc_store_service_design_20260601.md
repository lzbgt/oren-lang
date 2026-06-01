# OBC Store Service Design

**Date:** 2026-06-01

## Decision

`store.hubstack.cn` should be the public OBC package store site and API service.
It should behave like a small PyPI-style registry for Oren bytecode packages:
publishers upload releases, users browse/search packages, and host apps download
signed package metadata and immutable artifacts for AVM execution.

The service should be implemented as a Go web service behind the existing Traefik
domain proxy on the host. The host is SSH reachable with trusted certs, but
deployment automation and private signing keys must stay outside this repo unless
explicitly requested later.

## External Admin Credential Reference

The initial `store.hubstack.cn` admin credential is intentionally stored outside
this repository:

```text
../oren-ca/obc-store-admin.env
```

Tracked docs must reference only these keys, not the secret value:

```text
OBC_STORE_ADMIN_HOST
OBC_STORE_ADMIN_USERNAME
OBC_STORE_ADMIN_PASSWORD
OBC_STORE_ADMIN_TOKEN_SHA256_HEX
```

Later sessions and sibling projects such as `../note` can read that external file
when they need to administer or smoke-test the store service.

## Boundary

The store service distributes data. It must not become a native execution service.

- OBC packages remain untrusted until the host app verifies hashes/signatures or
  the user explicitly accepts untrusted risk.
- The iOS/macOS/desktop host app decides install/run policy, capabilities,
  permission prompts, budgets, and runtime revocation.
- Private root/store/publisher keys stay outside this repo, recommended under
  `../oren-ca/` for local development.
- `store.hubstack.cn` may store public trust bundles, package metadata, indexes,
  screenshots, manifests, OBC blobs, and assets.

## Service Components

```text
store.hubstack.cn
  -> Traefik TLS/domain routing
  -> Go API service
  -> metadata database
  -> artifact object storage or filesystem
  -> background index/signature builder
```

Recommended Go service modules:

- `cmd/obc-store-server`: HTTP server entry point.
- `internal/auth`: publisher auth, API tokens, optional WebAuthn/OIDC later.
- `internal/packages`: package, version, manifest, and capability validation.
- `internal/artifacts`: immutable artifact storage and hash verification.
- `internal/indexer`: signed index generation and cache invalidation.
- `internal/search`: text/tag/capability search.
- `internal/trust`: public key/trust bundle publication and rotation metadata.
- `internal/audit`: append-only publish/remove/admin audit log.

## Current Implementation Slice

Implemented in this repo:

- `cmd/obc-store-server`: stdlib-only Go HTTP server entry point.
- `internal/obcstore`: file-backed registry implementation.
- Admin write endpoints accept deploy-safe bearer tokens verified by
  `OBC_STORE_ADMIN_TOKEN_SHA256_HEX`; HTTP Basic Auth from
  `OBC_STORE_ADMIN_USERNAME` / `OBC_STORE_ADMIN_PASSWORD` remains available for
  local bring-up and compatibility.
- Publisher package/version/release write endpoints accept publisher-scoped bearer
  tokens verified against the publisher's stored `token_sha256_hex`. A publisher
  token can only write under that publisher id; admin auth still controls
  publisher creation and global operations.
- Publisher tokens can be rotated or revoked through
  `POST`/`DELETE /api/v0/publishers/{publisher}/token` using either admin auth or
  the current publisher token.
- Public endpoints expose `/healthz`/`/api/v0/health`, package list/search, package/version metadata,
  `index.json`, package manifests, `program.obc`, deterministic `.obc.zip`
  release bundles, assets, and hash-addressed artifact lookup.
- Packages are public by default. Publishers or admins can set package visibility
  to `private`; private packages are omitted from the public browser, search,
  signed index, unauthenticated downloads, and hash-addressed artifact lookup.
  Authenticated publisher/admin API access can still read private package metadata
  and artifacts.
- Browser endpoints expose a server-rendered package store surface: `/` for
  search/browse, `/packages/{publisher}/{name}` for release download links, and
  `/ops` for operator API/token lifecycle reference. The machine APIs remain the
  source of truth.
- `index.json.sig` is generated dynamically when the service is configured with
  `--index-signing-key` or `OBC_STORE_INDEX_SIGN_KEY_PEM`, using P-256
  SHA-256 DER signatures over the exact stable `index.json` bytes.
- Publisher endpoints can create publishers, packages, draft versions, upload
  release OBC/assets, publish releases, and yank releases.
- Version uploads validate manifest `permission_defaults` shape before accepting a
  draft release: entries must be objects with non-empty string `domain` and
  `action`, optional string `detail`, and optional boolean `granted`. The service
  stores this metadata for host apps; it does not grant runtime permissions.
- `make verify-libavm-ios` starts this service locally, publishes a signed OBC
  package through the HTTP API, then verifies `OrenAVMPackageStore` can download,
  install, and run that package from the service endpoint.
- Verification target: `make verify-obc-store-service`.

Remaining service work before deployment:

- signed index rotation/key-id publication beyond the current single-key signer;
- richer browser/operator UX beyond the current browse/detail/operator reference
  pages;
- metadata DB or transactional storage backend if filesystem storage is not enough;
- host deployment can use `scripts/deploy_obc_store_service.sh` or
  `make deploy-obc-store-service` with `OBC_STORE_SSH_TARGET` set; the script
  cross-builds the Go binary, uploads external admin env values, and copies the
  index signing key only when `OBC_STORE_COPY_INDEX_SIGNING_KEY=1`. It can also
  install/restart `oren-obc-store.service` when `OBC_STORE_INSTALL_SYSTEMD=1`,
  bind the service to `OBC_STORE_LISTEN_ADDR` for the Traefik backend, and run a
  remote health probe when `OBC_STORE_REMOTE_HEALTHCHECK=1`. Operators can inspect
  the generated unit without SSH via
  `scripts/deploy_obc_store_service.sh --print-systemd-unit`;
- live deployment, Traefik route config, and public health smoke on
  `store.hubstack.cn`;
  the cloud host Traefik layer owns automatic DNS and HTTPS certificate handling,
  so this repo should not manage TLS cert material;

## Registry Model

Core records:

- `publisher`: id, display name, public keys, status.
- `package`: publisher, name, title, summary, tags, visibility, status.
- `release`: package id, version, manifest hash, OBC hash, signature metadata,
  compatibility, capabilities, budgets, created time.
- `asset`: release id, path, media type, size, sha256.
- `artifact`: content hash, size, storage path, immutable flag.
- `audit_event`: actor, action, target, timestamp, request id.

Package identity should be stable:

```text
<publisher>/<name>@<version>
```

Example:

```text
oren-labs/plot-demo@0.1.0
```

## Public APIs

All public machine APIs should be stable JSON over HTTPS.

### Store Metadata

```http
GET /
GET /packages/{publisher}/{name}
GET /ops
GET /healthz
GET /api/v0/health
GET /api/v0/trust/bundle.json
GET /api/v0/index.json
GET /api/v0/index.json.sig
```

`index.json` should remain compatible with `OrenAVMPackageStore` signed-index
download flow. The API can add richer endpoints, but host apps should still be
able to bootstrap from the signed index alone.

### Browse and Search

```http
GET /api/v0/packages?query=plot&tag=science&capability=GFX&limit=50&cursor=...
GET /api/v0/packages/{publisher}/{name}
GET /api/v0/packages/{publisher}/{name}/versions
GET /api/v0/packages/{publisher}/{name}/versions/{version}
```

Search response should include only metadata needed for browsing. Download and
execution should still verify the release manifest and hashes.

### Download and Install

```http
GET /api/v0/packages/{publisher}/{name}/versions/{version}/package.json
GET /api/v0/packages/{publisher}/{name}/versions/{version}/program.obc
GET /api/v0/packages/{publisher}/{name}/versions/{version}/bundle.obc.zip
GET /api/v0/packages/{publisher}/{name}/versions/{version}/assets/{path...}
GET /api/v0/artifacts/sha256/{hex}
```

Only public packages are exposed through unauthenticated download endpoints.
Publisher/admin-authenticated requests may read private package artifacts.

The iOS SDK install flow should use:

1. fetch `index.json` and `index.json.sig`;
2. find package/version;
3. download `package.json`, `program.obc`, and assets;
4. verify hashes/signatures locally;
5. install into app-owned storage;
6. run through `OrenAVMPackageStore`.

### Publisher APIs

```http
POST /api/v0/publishers
GET  /api/v0/me
POST /api/v0/publishers/{publisher}/token
DELETE /api/v0/publishers/{publisher}/token
POST /api/v0/packages
POST /api/v0/packages/{publisher}/{name}/visibility
POST /api/v0/packages/{publisher}/{name}/versions
POST /api/v0/packages/{publisher}/{name}/versions/{version}/artifacts
POST /api/v0/packages/{publisher}/{name}/versions/{version}/publish
POST /api/v0/packages/{publisher}/{name}/versions/{version}/yank
```

Publish flow:

1. Publisher authenticates with a bearer token scoped to its publisher id, or an
   admin performs the publish operation.
2. Publisher uploads manifest, OBC, and assets.
3. Service verifies manifest schema, semantic version, hashes, size limits,
   capability declarations, permission-default metadata shape, and AVM ABI
   compatibility.
4. Service stores immutable artifacts by SHA-256.
5. Publisher reads the returned `manifest_sha256`, signs that lowercase hex string
   outside the service, then calls `publish` with:

   ```json
	 {
	   "signature_alg": "p256-sha256-der",
	   "signature_p256_sha256_der_hex": "<DER signature hex>"
	 }
	 ```
	   If the publisher has registered public keys, the service verifies the detached
	   publisher signature before moving the release to `published`.
6. Release becomes visible only after validation and index regeneration.

Package visibility update:

```json
{
  "visibility": "public"
}
```

Allowed values are `public` and `private`. Omitted visibility at package creation
means `public`.

The service should not hold publisher private keys by default. If a future hosted
signing mode exists, it must use a dedicated key-management design and audit log.

## Host-App Policy

Host apps such as Note should treat the service as an untrusted network source
until package metadata is verified:

- trusted path: require signed index and publisher signatures;
- user-risk path: allow explicit user-confirmed unsigned/untrusted package install;
- all paths: enforce AVM capabilities, budgets, VFS/VNET/VPROC/TIME/GFX policy,
  and permission prompts.

The service may provide UI warnings, but runtime safety belongs to AVM and the
host SDK.

## Operational Gates

Before deployment:

1. Go service unit tests for manifest validation, artifact hashing, index output,
   signed index output, and search filters.
2. End-to-end fixture that publishes a package, fetches signed index, installs via
   `OrenAVMPackageStore`, and runs in AVM.
3. Traefik route smoke for `https://store.hubstack.cn/api/v0/health`.
4. Private key scan proving no private key material is committed.
5. Backup/restore smoke for metadata DB and artifact storage.
6. Rate limits and max upload/package sizes.
7. Audit log append/read smoke.

## TODO Registration

Implementation is intentionally separate from the current AVM SDK turn. Track it
as `OBC-STORE-SERVICE` in `TODOS.md`.
