# macOS Codesigning & Notarization

On macOS, the OS security model can reject/kill unsigned executables (especially newly-built binaries in developer workflows). To keep local iteration smooth, Oren uses **ad-hoc signing** by default for macOS native outputs.

## Defaults (rolling)

- For `--backend native --target macos`, `oren build` defaults to **ad-hoc signing**:

```bash
codesign -s - --force <output>
```

- To sign for distribution, pass a Developer ID identity:
  - `--codesign "Developer ID Application: ..."`
  - or env `OREN_CODESIGN_ID="Developer ID Application: ..."`

- Oren’s macOS-native outputs are expected to be signed for local execution. Disabling signing is not supported because the OS may kill the process at runtime.

- Deterministic builds (`--deterministic`) avoid post-processing steps that mutate the output (including external signing). A deterministic output is therefore **not guaranteed runnable** on macOS until you sign it (for local use, ad-hoc signing is typically sufficient):

```bash
codesign -s - --force <output>
```

## Embedded signatures (compiler)

- The Mach-O emitters do **not** attempt to embed a custom code signature blob.
- For reliable local execution on macOS, the build pipeline signs outputs externally via `codesign` (ad-hoc by default).

## Notarization

- `--notarize [--notary-profile name]` submits via `xcrun notarytool` and staples the ticket.
- Notarization requires a **Developer ID** identity; it is rejected when:
  - `--codesign` is missing
  - or `--codesign -` (ad-hoc)

## Installing a signing identity

1. Open Xcode → Settings → Accounts, sign in with your Apple Developer account.
2. Select your team → **Manage Certificates…** → press `+` and create **Developer ID Application**.
3. Confirm the cert exists in your login keychain:

```bash
security find-identity -v -p codesigning
```

## Distribution notes

- End users **do not** need your certificate installed. A Developer ID–signed, notarized binary satisfies Gatekeeper.
- For local experiments/testing, ad-hoc signing is sufficient.
