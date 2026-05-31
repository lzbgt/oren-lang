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
and validates the trust JSON.

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
longer need them. Private key escrow, revocation publication, and production CA
operations remain outside this repo.
