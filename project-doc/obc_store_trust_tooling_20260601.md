# OBC Store Trust Tooling

**Last updated:** 2026-06-01

OBC package trust material must be generated outside this repository. The repo
ships tooling and public formats, but private store/publisher keys must not be
committed here.

## Tool

Use:

```bash
scripts/issue_obc_store_trust.sh --out-dir ../oren-ca --store-id oren-store-dev --publisher-id oren-labs
```

During store-root rotation, issue the new active store key and keep previous
public keys in the bundle before switching clients or the service:

```bash
scripts/issue_obc_store_trust.sh \
  --out-dir ../oren-ca \
  --store-id oren-store-2026q2 \
  --previous-store-id oren-store-2026q1 \
  --publisher-id oren-labs
```

or:

```bash
make issue-obc-store-trust OREN_CA_DIR=../oren-ca
```

The tool writes:

- `../oren-ca/private/*.pem`: private P-256 store and publisher keys, mode `600`.
- `../oren-ca/public/*.pem`: public PEM keys.
- `../oren-ca/public/*.p256.x963.b64`: SDK-ready public key bytes for
  `OrenAVMPackageStore`.
- `../oren-ca/trust/obc_store_trust.json`: host-app trust bundle.

The script also signs and verifies a local smoke message with both generated keys
and validates the trust JSON. The active store key is written first in
`store_keys`; repeated `--previous-store-id` values append already-issued public
store keys without touching their private keys.

## Host App Consumption

Sibling host apps such as `../note` should not infer trust material from this repo.
They should read a public trust bundle or a local config path, for example:

```bash
OREN_OBC_TRUST_BUNDLE=../oren-ca/trust/obc_store_trust.json
```

The iOS SDK now exposes `OrenAVMOBCTrustBundle.loadTrustBundleAtURL(...)` for
this file. Host apps can pass the loaded bundle directly to
`OrenAVMPackageStore.downloadPackageFromSignedIndexURL(... trustBundle: ...)`
instead of hand-parsing key bytes.

Manual consumption is still possible: use `defaultStorePublicKey` as
`trustedIndexPublicKey` and `publisherPublicKeys` as
`trustedPublisherPublicKeys`.

## Policy

Signature enforcement remains host policy. A host app may require trusted index and
publisher signatures by default, or expose an explicit user-confirmed path for
running unsigned/untrusted OBC. In both cases, the OBC program still runs inside
AVM capability gates and only sees virtual resources.

## Rotation

Key rotation should add new public keys to the trust bundle before packages depend
on them. Old keys should stay accepted until installed packages and store indexes no
longer need them. The store service accepts `OBC_STORE_INDEX_SIGN_KEY_ID` and
`OBC_STORE_TRUST_BUNDLE`; dynamic `index.json.sig` responses include
`X-Oren-Signing-Key-ID`, and `/ops/status` reports the active signer plus
trust-bundle store-key IDs, including whether the active signer is trusted by the
served bundle. Private key escrow, revocation publication, and production CA
operations remain outside this repo.
