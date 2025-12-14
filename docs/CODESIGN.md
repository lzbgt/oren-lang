# macOS Codesigning & Notarization

Oren binaries can self-sign during `oren build` without extra flags (similar to Zig/Go).

## Defaults
- The CLI defaults to `Developer ID Application: Zongbao Lu (US56HHF2Y4)` on macOS and falls back to ad-hoc signing if unavailable.
- Override with `--codesign "<identity>"`, `CODESIGN_IDENTITY`, or `OREN_CODESIGN_ID`.
- Add `--notarize [--notary-profile name]` to submit via `xcrun notarytool` and staple the ticket; the CLI also accepts `APPLE_ID`, `APPLE_ID_PASS`, and `APPLE_TEAM_ID`.

## Installing the identity
1. Open Xcode → Settings → Accounts, sign in with your Apple Developer account.
2. Select your team → **Manage Certificates…** → press `+` and create **Developer ID Application** (and/or Apple Development).
3. Confirm the cert lives in your login keychain with `security find-identity -v -p codesigning`.

## Distribution notes
- End users **do not** need your certificate installed. A Developer ID–signed, notarized binary will satisfy Gatekeeper.
- For local experiments, ad-hoc signing (`-s -`) is fine; for distribution, use Developer ID + notarization.
