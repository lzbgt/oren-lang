#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/ios}"
TMP_DIR="build/tmp/libavm_ios_verify"
LOG_DIR="build/logs"
FIXTURE_DIR="tests/fixtures/ios_avm"
mkdir -p "$TMP_DIR" "$LOG_DIR"
OREN_COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$OREN_COMPILER" ]]; then
  make oren > "$LOG_DIR/make_oren_for_libavm_ios_verify.log" 2>&1
fi
reserve_tcp_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}
reserve_udp_port() {
  python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}
stop_pid() {
  local pid="${1:-}"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}
./scripts/build_libavm_ios.sh > "$LOG_DIR/build_libavm_ios.log" 2>&1
test -f "$OUT_ROOT/iphoneos-arm64/libavm.a"
test -f "$OUT_ROOT/iphonesimulator-arm64/libavm.a"
test -f "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a"
test -f "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a"
test -d "$OUT_ROOT/LibAVM.xcframework"
test -d "$OUT_ROOT/OrenAVMKit.xcframework"
test -f "$OUT_ROOT/include/avm_embed.h"
test -f "$OUT_ROOT/include/module.modulemap"
test -f "$OUT_ROOT/include/OrenAVMKit/OrenAVMKit.h"

./scripts/verify_libavm_ios_symbols.sh "$OUT_ROOT"

OREN_SRC="$TMP_DIR/embed_chain.oren"
OBC_OUT="$TMP_DIR/embed_chain.obc"
OBC_HEADER="$TMP_DIR/embed_chain_obc.h"
CANCEL_SRC="$TMP_DIR/cancel_spin.oren"
CANCEL_OBC_OUT="$TMP_DIR/cancel_spin.obc"
CANCEL_OBC_HEADER="$TMP_DIR/cancel_spin_obc.h"
CANCEL_WATCH_SRC="$TMP_DIR/cancel_watch.oren"
CANCEL_WATCH_OBC_OUT="$TMP_DIR/cancel_watch.obc"
CANCEL_WATCH_OBC_HEADER="$TMP_DIR/cancel_watch_obc.h"
HOST_FS_SRC="$TMP_DIR/host_fs_chain.oren"
HOST_FS_OBC_OUT="$TMP_DIR/host_fs_chain.obc"
HOST_FS_OBC_HEADER="$TMP_DIR/host_fs_chain_obc.h"
PACKAGE_SRC="$TMP_DIR/package_chain.oren"
PACKAGE_OBC_OUT="$TMP_DIR/package_chain.obc"
PACKAGE_V2_SRC="$TMP_DIR/package_chain_v2.oren"
PACKAGE_V2_OBC_OUT="$TMP_DIR/package_chain_v2.obc"
PACKAGE_SCENE_SRC="$TMP_DIR/package_scene3d.oren"
PACKAGE_SCENE_OBC_OUT="$TMP_DIR/package_scene3d.obc"
cp "$FIXTURE_DIR/embed_chain.oren" "$OREN_SRC"
"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" > "$LOG_DIR/libavm_ios_embed_chain_obc_build.log" 2>&1

cp "$FIXTURE_DIR/cancel_spin.oren" "$CANCEL_SRC"
"$OREN_COMPILER" build "$CANCEL_SRC" --backend bytecode -o "$CANCEL_OBC_OUT" > "$LOG_DIR/libavm_ios_cancel_spin_obc_build.log" 2>&1

cp "$FIXTURE_DIR/cancel_watch.oren" "$CANCEL_WATCH_SRC"
"$OREN_COMPILER" build "$CANCEL_WATCH_SRC" --backend bytecode -o "$CANCEL_WATCH_OBC_OUT" > "$LOG_DIR/libavm_ios_cancel_watch_obc_build.log" 2>&1

cp "$FIXTURE_DIR/host_fs_chain.oren" "$HOST_FS_SRC"
"$OREN_COMPILER" build "$HOST_FS_SRC" --backend bytecode -o "$HOST_FS_OBC_OUT" > "$LOG_DIR/libavm_ios_host_fs_chain_obc_build.log" 2>&1

cp "$FIXTURE_DIR/package_chain.oren" "$PACKAGE_SRC"
"$OREN_COMPILER" build "$PACKAGE_SRC" --backend bytecode -o "$PACKAGE_OBC_OUT" > "$LOG_DIR/libavm_ios_package_chain_obc_build.log" 2>&1

cp "$FIXTURE_DIR/package_chain_v2.oren" "$PACKAGE_V2_SRC"
"$OREN_COMPILER" build "$PACKAGE_V2_SRC" --backend bytecode -o "$PACKAGE_V2_OBC_OUT" > "$LOG_DIR/libavm_ios_package_chain_v2_obc_build.log" 2>&1

cp "$FIXTURE_DIR/package_scene3d.oren" "$PACKAGE_SCENE_SRC"
"$OREN_COMPILER" build "$PACKAGE_SCENE_SRC" --backend bytecode -o "$PACKAGE_SCENE_OBC_OUT" > "$LOG_DIR/libavm_ios_package_scene3d_obc_build.log" 2>&1

python3 scripts/obc_to_c_header.py "$OBC_OUT" "$OBC_HEADER" kEmbedChainObc
python3 scripts/obc_to_c_header.py "$CANCEL_OBC_OUT" "$CANCEL_OBC_HEADER" kCancelSpinObc
python3 scripts/obc_to_c_header.py "$CANCEL_WATCH_OBC_OUT" "$CANCEL_WATCH_OBC_HEADER" kCancelWatchObc
python3 scripts/obc_to_c_header.py "$HOST_FS_OBC_OUT" "$HOST_FS_OBC_HEADER" kHostFSChainObc

cp "$FIXTURE_DIR/embed_smoke.c" "$TMP_DIR/embed_smoke.c"

cp "$FIXTURE_DIR/sdk_smoke.m" "$TMP_DIR/sdk_smoke.m"

cp "$FIXTURE_DIR/sdk_module_smoke.m" "$TMP_DIR/sdk_module_smoke.m"

HOST_BIN="$TMP_DIR/embed_smoke_host"
HOST_SDK_BIN="$TMP_DIR/sdk_smoke_host"
./scripts/verify_libavm_ios_compile_smokes.sh "$OUT_ROOT" "$TMP_DIR" "$HOST_BIN" "$HOST_SDK_BIN"
NET_DIR="$TMP_DIR/net_server"
rm -rf "$NET_DIR"
mkdir -p "$NET_DIR"
printf 'net-ok' > "$NET_DIR/net.txt"
NET_READY="$TMP_DIR/net_server.ready"
rm -f "$NET_READY"
NET_PORT="$(reserve_tcp_port)"
TCP_READY="$TMP_DIR/tcp_server.ready"
rm -f "$TCP_READY"
TCP_PORT="$(reserve_tcp_port)"
TCP_LISTEN_PORT="$(reserve_tcp_port)"
UDP_READY="$TMP_DIR/udp_server.ready"
rm -f "$UDP_READY"
UDP_PORT="$(reserve_udp_port)"
WS_READY="$TMP_DIR/ws_server.ready"
rm -f "$WS_READY"
WS_PORT="$(reserve_tcp_port)"
PKG_READY="$TMP_DIR/package_http.ready"
rm -f "$PKG_READY"
PKG_PORT="$(reserve_tcp_port)"
GO_STORE_PORT="$(reserve_tcp_port)"
PACKAGE_DIR="$TMP_DIR/package_store/oren-labs/sdk-package-smoke/0.1.0"
SCENE_PACKAGE_DIR="$TMP_DIR/package_store/oren-labs/sdk-scene3d-package/0.1.0"
REMOTE_STORE_DIR="$TMP_DIR/remote_obc_store"
GO_STORE_DIR="$TMP_DIR/go_obc_store"
REMOTE_PACKAGE_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-remote/0.1.0"
REMOTE_PACKAGE_V2_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-remote/0.2.0"
REMOTE_BAD_ASSET_PACKAGE_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-bad-asset/0.1.0"
REMOTE_BAD_SIGNATURE_PACKAGE_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-bad-signature/0.1.0"
rm -rf "$TMP_DIR/package_store" "$TMP_DIR/downloaded_packages" "$TMP_DIR/downloaded_service_packages" "$REMOTE_STORE_DIR" "$GO_STORE_DIR"
mkdir -p "$PACKAGE_DIR/assets" "$SCENE_PACKAGE_DIR/assets" "$REMOTE_PACKAGE_DIR/assets" "$REMOTE_PACKAGE_V2_DIR/assets" "$REMOTE_BAD_ASSET_PACKAGE_DIR/assets" "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/assets"
cp "$PACKAGE_OBC_OUT" "$PACKAGE_DIR/program.obc"
cp "$PACKAGE_SCENE_OBC_OUT" "$SCENE_PACKAGE_DIR/program.obc"
cp "$PACKAGE_OBC_OUT" "$REMOTE_PACKAGE_DIR/program.obc"
cp "$PACKAGE_V2_OBC_OUT" "$REMOTE_PACKAGE_V2_DIR/program.obc"
cp "$PACKAGE_OBC_OUT" "$REMOTE_BAD_ASSET_PACKAGE_DIR/program.obc"
cp "$PACKAGE_OBC_OUT" "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/program.obc"
printf 'pkg-asset' > "$PACKAGE_DIR/assets/config.txt"
python3 scripts/make_scene3d_bin_v0.py \
  examples/obc_store_demos/assets/scene3d_card.json \
  "$SCENE_PACKAGE_DIR/assets/scene3d_card.os3d"
printf 'pkg-asset' > "$REMOTE_PACKAGE_DIR/assets/config.txt"
printf 'pkg-asset-v2' > "$REMOTE_PACKAGE_V2_DIR/assets/config.txt"
printf 'pkg-asset' > "$REMOTE_BAD_ASSET_PACKAGE_DIR/assets/config.txt"
printf 'pkg-asset' > "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/assets/config.txt"
PACKAGE_HASH="$(shasum -a 256 "$PACKAGE_DIR/program.obc" | awk '{print $1}')"
SCENE_PACKAGE_HASH="$(shasum -a 256 "$SCENE_PACKAGE_DIR/program.obc" | awk '{print $1}')"
SCENE_ASSET_HASH="$(shasum -a 256 "$SCENE_PACKAGE_DIR/assets/scene3d_card.os3d" | awk '{print $1}')"
REMOTE_PACKAGE_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/program.obc" | awk '{print $1}')"
REMOTE_PACKAGE_V2_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_V2_DIR/program.obc" | awk '{print $1}')"
REMOTE_ASSET_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/assets/config.txt" | awk '{print $1}')"
REMOTE_ASSET_V2_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_V2_DIR/assets/config.txt" | awk '{print $1}')"
python3 scripts/libavm_ios_verify_package_manifest.py \
  --out "$PACKAGE_DIR/package.json" \
  --name sdk-package-smoke \
  --version 0.1.0 \
  --title "SDK Package Smoke" \
  --summary "Verifies OrenAVMPackageStore local package loading." \
  --obc-sha256 "$PACKAGE_HASH" \
  --capabilities CORE,FS,NET,EXIT \
  --permission-default "NET|connect|tcp://package.example:443|true" \
  --mount "assets|assets|true"
python3 scripts/libavm_ios_verify_package_manifest.py \
  --out "$SCENE_PACKAGE_DIR/package.json" \
  --name sdk-scene3d-package \
  --version 0.1.0 \
  --title "SDK Scene3D Package" \
  --summary "Verifies OrenAVMPackageStore mounts byte-native Scene3D assets." \
  --obc-sha256 "$SCENE_PACKAGE_HASH" \
  --capabilities CORE,FS,EXIT \
  --asset "assets/scene3d_card.os3d|$SCENE_ASSET_HASH|application/vnd.oren.ui.scene3d.bin.v0" \
  --gas 10000000 \
  --mount "assets|assets|true"
python3 scripts/libavm_ios_verify_package_manifest.py \
  --out "$REMOTE_PACKAGE_DIR/package.json" \
  --name sdk-package-remote \
  --version 0.1.0 \
  --title "SDK Remote Package Smoke" \
  --summary "Verifies OrenAVMPackageStore index download." \
  --obc-sha256 "$REMOTE_PACKAGE_HASH" \
  --capabilities CORE,FS,EXIT \
  --asset "assets/config.txt|$REMOTE_ASSET_HASH" \
  --mount "assets|assets|true"
python3 scripts/libavm_ios_verify_package_manifest.py \
  --out "$REMOTE_BAD_ASSET_PACKAGE_DIR/package.json" \
  --name sdk-package-bad-asset \
  --version 0.1.0 \
  --title "SDK Bad Asset Package Smoke" \
  --summary "Verifies asset hash mismatch rejection." \
  --obc-sha256 "$REMOTE_PACKAGE_HASH" \
  --capabilities CORE,FS,EXIT \
  --asset "assets/config.txt|0000000000000000000000000000000000000000000000000000000000000000" \
  --mount "assets|assets|true"
python3 scripts/libavm_ios_verify_package_manifest.py \
  --out "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/package.json" \
  --name sdk-package-bad-signature \
  --version 0.1.0 \
  --title "SDK Bad Signature Package Smoke" \
  --summary "Verifies manifest signature rejection." \
  --obc-sha256 "$REMOTE_PACKAGE_HASH" \
  --capabilities CORE,FS,EXIT \
  --asset "assets/config.txt|$REMOTE_ASSET_HASH" \
  --mount "assets|assets|true"
python3 scripts/libavm_ios_verify_package_manifest.py \
  --out "$REMOTE_PACKAGE_V2_DIR/package.json" \
  --name sdk-package-remote \
  --version 0.2.0 \
  --title "SDK Remote Package Smoke v2" \
  --summary "Verifies OrenAVMPackageStore update policy." \
  --obc-sha256 "$REMOTE_PACKAGE_V2_HASH" \
  --capabilities CORE,FS,EXIT \
  --asset "assets/config.txt|$REMOTE_ASSET_V2_HASH" \
  --mount "assets|assets|true"
REMOTE_MANIFEST_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/package.json" | awk '{print $1}')"
REMOTE_MANIFEST_V2_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_V2_DIR/package.json" | awk '{print $1}')"
REMOTE_BAD_ASSET_MANIFEST_HASH="$(shasum -a 256 "$REMOTE_BAD_ASSET_PACKAGE_DIR/package.json" | awk '{print $1}')"
REMOTE_BAD_SIGNATURE_MANIFEST_HASH="$(shasum -a 256 "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/package.json" | awk '{print $1}')"
python3 - "$REMOTE_PACKAGE_DIR" "$REMOTE_PACKAGE_DIR/bundle.obc.zip" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name in ["package.json", "program.obc", "assets/config.txt"]:
        info = zipfile.ZipInfo(name)
        info.date_time = (2026, 1, 1, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, (root / name).read_bytes())
    info = zipfile.ZipInfo("assets/source/main.oren")
    info.date_time = (2026, 1, 1, 0, 0, 0)
    info.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(info, b"print(\"bundle-source\")\n")
PY
REMOTE_BUNDLE_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/bundle.obc.zip" | awk '{print $1}')"
PACKAGE_SIGN_KEY="$TMP_DIR/package_store_p256.pem"
BAD_STORE_INDEX_KEY="$TMP_DIR/package_store_bad_index_p256.pem"
REMOTE_MANIFEST_HASH_MSG="$TMP_DIR/remote_manifest_hash.txt"
REMOTE_MANIFEST_V2_HASH_MSG="$TMP_DIR/remote_manifest_v2_hash.txt"
REMOTE_BAD_ASSET_HASH_MSG="$TMP_DIR/remote_bad_asset_manifest_hash.txt"
extract_p256_pubkey_b64() {
  python3 - "$1" <<'PY'
import base64
import subprocess
import sys
der = subprocess.check_output(["openssl", "ec", "-in", sys.argv[1], "-pubout", "-outform", "DER"], stderr=subprocess.DEVNULL)
idx = der.rfind(b"\x03\x42\x00\x04")
if idx < 0:
    raise SystemExit("missing P-256 public key bit string")
pub = der[idx + 3:idx + 68]
if len(pub) != 65 or pub[0] != 4:
    raise SystemExit("invalid P-256 public key length")
print(base64.b64encode(pub).decode("ascii"))
PY
}
openssl ecparam -name prime256v1 -genkey -noout -out "$PACKAGE_SIGN_KEY"
openssl ecparam -name prime256v1 -genkey -noout -out "$BAD_STORE_INDEX_KEY"
printf '%s' "$REMOTE_MANIFEST_HASH" > "$REMOTE_MANIFEST_HASH_MSG"
printf '%s' "$REMOTE_MANIFEST_V2_HASH" > "$REMOTE_MANIFEST_V2_HASH_MSG"
printf '%s' "$REMOTE_BAD_ASSET_MANIFEST_HASH" > "$REMOTE_BAD_ASSET_HASH_MSG"
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$TMP_DIR/remote_manifest.sig" "$REMOTE_MANIFEST_HASH_MSG"
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$TMP_DIR/remote_manifest_v2.sig" "$REMOTE_MANIFEST_V2_HASH_MSG"
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$TMP_DIR/remote_bad_asset_manifest.sig" "$REMOTE_BAD_ASSET_HASH_MSG"
REMOTE_SIGNATURE_HEX="$(xxd -p -c 256 "$TMP_DIR/remote_manifest.sig" | tr -d '\n')"
REMOTE_SIGNATURE_V2_HEX="$(xxd -p -c 256 "$TMP_DIR/remote_manifest_v2.sig" | tr -d '\n')"
REMOTE_BAD_ASSET_SIGNATURE_HEX="$(xxd -p -c 256 "$TMP_DIR/remote_bad_asset_manifest.sig" | tr -d '\n')"
PACKAGE_PUBLISHER_KEY_B64="$(extract_p256_pubkey_b64 "$PACKAGE_SIGN_KEY")"
BAD_STORE_INDEX_KEY_B64="$(extract_p256_pubkey_b64 "$BAD_STORE_INDEX_KEY")"
GO_STORE_SERVER_BIN="$TMP_DIR/obc-store-server"
go build -o "$GO_STORE_SERVER_BIN" ./cmd/obc-store-server
TRUST_BUNDLE_JSON="$TMP_DIR/obc_store_trust.json"
cat > "$TRUST_BUNDLE_JSON" <<JSON
{
  "schema": "oren.obc.trust.v0",
  "generated_at": "2026-06-01T00:00:00Z",
  "store_keys": [
    {
      "id": "oren-store-dev",
      "alg": "p256-sha256-der",
      "public_key_x963_b64": "$PACKAGE_PUBLISHER_KEY_B64"
    }
  ],
  "publisher_keys": {
    "oren-labs": {
      "alg": "p256-sha256-der",
      "public_key_x963_b64": "$PACKAGE_PUBLISHER_KEY_B64"
    }
  }
}
JSON
cat > "$REMOTE_STORE_DIR/index.json" <<JSON
{
  "schema": "oren.obc.store.index.v0",
  "generated_at": "2026-06-01T00:00:00Z",
  "packages": [
    {
      "id": "oren-labs/sdk-package-remote",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/sdk-package-remote/0.1.0/package.json",
      "manifest_sha256": "$REMOTE_MANIFEST_HASH",
      "bundle": "packages/oren-labs/sdk-package-remote/0.1.0/bundle.obc.zip",
      "bundle_sha256": "$REMOTE_BUNDLE_HASH",
      "bundle_media_type": "application/vnd.oren.obc.release+zip",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "$REMOTE_SIGNATURE_HEX",
      "tags": ["sdk", "smoke"],
      "min_app": "0.1.0"
    },
    {
      "id": "oren-labs/sdk-package-remote",
      "version": "0.2.0",
      "manifest": "packages/oren-labs/sdk-package-remote/0.2.0/package.json",
      "manifest_sha256": "$REMOTE_MANIFEST_V2_HASH",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "$REMOTE_SIGNATURE_V2_HEX",
      "tags": ["sdk", "smoke", "update"],
      "min_app": "0.1.0"
    },
    {
      "id": "oren-labs/sdk-package-bad-asset",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/sdk-package-bad-asset/0.1.0/package.json",
      "manifest_sha256": "$REMOTE_BAD_ASSET_MANIFEST_HASH",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "$REMOTE_BAD_ASSET_SIGNATURE_HEX",
      "tags": ["sdk", "negative"],
      "min_app": "0.1.0"
    },
    {
      "id": "oren-labs/sdk-package-bad-signature",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/sdk-package-bad-signature/0.1.0/package.json",
      "manifest_sha256": "$REMOTE_BAD_SIGNATURE_MANIFEST_HASH",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "00",
      "tags": ["sdk", "negative"],
      "min_app": "0.1.0"
    }
  ]
}
JSON
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$REMOTE_STORE_DIR/index.json.sig" "$REMOTE_STORE_DIR/index.json"
python3 scripts/libavm_ios_verify_net_helpers.py http-fixed --port "$NET_PORT" --body "$NET_DIR/net.txt" --ready "$NET_READY" > "$LOG_DIR/libavm_ios_sdk_net_server.log" 2>&1 &
NET_SERVER_PID=$!
python3 scripts/libavm_ios_verify_net_helpers.py tcp-ping --port "$TCP_PORT" --ready "$TCP_READY" > "$LOG_DIR/libavm_ios_sdk_tcp_server.log" 2>&1 &
TCP_SERVER_PID=$!
python3 scripts/libavm_ios_verify_net_helpers.py udp-ping --port "$UDP_PORT" --ready "$UDP_READY" > "$LOG_DIR/libavm_ios_sdk_udp_server.log" 2>&1 &
UDP_SERVER_PID=$!
python3 scripts/libavm_ios_verify_net_helpers.py ws-echo --port "$WS_PORT" --ready "$WS_READY" > "$LOG_DIR/libavm_ios_sdk_ws_server.log" 2>&1 &
WS_SERVER_PID=$!
python3 scripts/libavm_ios_verify_net_helpers.py static-http --port "$PKG_PORT" --root "$REMOTE_STORE_DIR" --ready "$PKG_READY" > "$LOG_DIR/libavm_ios_sdk_package_http_server.log" 2>&1 &
PKG_SERVER_PID=$!
OBC_STORE_ADMIN_USERNAME=admin \
OBC_STORE_ADMIN_PASSWORD=secret \
OBC_STORE_INDEX_SIGN_KEY_PEM="$PACKAGE_SIGN_KEY" \
  "$GO_STORE_SERVER_BIN" -addr "127.0.0.1:${GO_STORE_PORT}" -data-dir "$GO_STORE_DIR" > "$LOG_DIR/libavm_ios_sdk_obc_store_server.log" 2>&1 &
GO_STORE_PID=$!
python3 - "$GO_STORE_PORT" "$GO_STORE_DIR" "$PACKAGE_OBC_OUT" "$PACKAGE_SIGN_KEY" > "$LOG_DIR/libavm_ios_sdk_obc_store_publish.log" 2>&1 <<'PY'
import base64
import hashlib
import http.client
import io
import json
import pathlib
import subprocess
import sys
import time
import urllib.request
import zipfile

port = int(sys.argv[1])
data_dir = pathlib.Path(sys.argv[2])
obc_path = pathlib.Path(sys.argv[3])
sign_key = pathlib.Path(sys.argv[4])
base = f"http://127.0.0.1:{port}"

for _ in range(100):
    try:
        with urllib.request.urlopen(base + "/api/v0/health", timeout=0.2) as resp:
            if resp.status == 200:
                break
    except Exception:
        time.sleep(0.05)
else:
    raise SystemExit("obc-store service did not become ready")

def post(path, payload, authorization):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(base + path, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", authorization)
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

admin_auth = "Basic " + base64.b64encode(b"admin:secret").decode("ascii")
publisher_token = "sdk-service-publisher-token"
publisher_auth = "Bearer " + publisher_token

pub = subprocess.check_output(
    [
        "python3",
        "-",
        str(sign_key),
    ],
    input=b"""import base64, subprocess, sys
der = subprocess.check_output(["openssl", "ec", "-in", sys.argv[1], "-pubout", "-outform", "DER"], stderr=subprocess.DEVNULL)
idx = der.rfind(b"\\x03\\x42\\x00\\x04")
pub = der[idx + 3:idx + 68]
print(base64.b64encode(pub).decode("ascii"))
""",
).decode("ascii").strip()

post("/api/v0/publishers", {"id": "oren-labs", "display_name": "Oren Labs", "public_keys": [pub], "token_sha256_hex": hashlib.sha256(publisher_token.encode("utf-8")).hexdigest()}, admin_auth)
post("/api/v0/packages", {"publisher": "oren-labs", "name": "sdk-package-service", "title": "SDK Service Package Smoke", "summary": "Verifies SDK install from obc-store-server", "tags": ["sdk", "service"]}, publisher_auth)
manifest_for_bundle = {
    "schema": "oren.obc.package.v0",
    "name": "sdk-package-service",
    "publisher": "oren-labs",
    "version": "0.1.0",
    "title": "SDK Service Package Smoke",
    "summary": "Verifies SDK install from obc-store-server",
    "entry_obc": "program.obc",
    "obc_sha256": hashlib.sha256(obc_path.read_bytes()).hexdigest(),
    "oren_min": "0.0.rolling",
    "avm_abi_min": 8,
    "capabilities": ["CORE", "FS", "EXIT"],
    "time_mode": "deterministic",
    "budgets": {
        "gas": 5000000,
        "heap_bytes": 33554432,
        "io_bytes": 1048576,
        "frame_commands": 1024,
    },
    "vfs_mounts": [
        {"virtual": "assets", "package_path": "assets", "read_only": True}
    ],
    "assets": [
        {
            "path": "assets/config.txt",
            "sha256": hashlib.sha256(b"pkg-asset").hexdigest(),
            "size": len(b"pkg-asset"),
            "media_type": "text/plain",
        }
    ],
}
bundle_io = io.BytesIO()
with zipfile.ZipFile(bundle_io, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name, body in [
        ("package.json", (json.dumps(manifest_for_bundle, indent=2, sort_keys=True) + "\n").encode("utf-8")),
        ("program.obc", obc_path.read_bytes()),
        ("assets/config.txt", b"pkg-asset"),
        ("assets/source/main.oren", b"print(\"service-bundle-source\")\n"),
    ]:
        info = zipfile.ZipInfo(name)
        info.date_time = (2026, 1, 1, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, body)
release = post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions",
    {
        "version": "0.1.0",
        "program_obc_base64": base64.b64encode(obc_path.read_bytes()).decode("ascii"),
        "release_bundle_base64": base64.b64encode(bundle_io.getvalue()).decode("ascii"),
        "tags": ["sdk", "service"],
        "min_app": "0.1.0",
        "manifest": {
            "title": "SDK Service Package Smoke",
            "summary": "Verifies SDK install from obc-store-server",
            "oren_min": "0.0.rolling",
            "avm_abi_min": 8,
            "capabilities": ["CORE", "FS", "EXIT"],
            "time_mode": "deterministic",
            "budgets": {
                "gas": 5000000,
                "heap_bytes": 33554432,
                "io_bytes": 1048576,
                "frame_commands": 1024,
            },
            "vfs_mounts": [
                {"virtual": "assets", "package_path": "assets", "read_only": True}
            ],
        },
        "assets": [
            {
                "path": "assets/config.txt",
                "media_type": "text/plain",
                "content_base64": base64.b64encode(b"pkg-asset").decode("ascii"),
            }
        ],
    },
    publisher_auth,
)
msg = data_dir / "manifest_hash.txt"
sig = data_dir / "manifest_hash.sig"
msg.write_text(release["manifest_sha256"], encoding="utf-8")
subprocess.check_call(["openssl", "dgst", "-sha256", "-sign", str(sign_key), "-out", str(sig), str(msg)], stdout=subprocess.DEVNULL)
post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions/0.1.0/publish",
    {
        "signature_alg": "p256-sha256-der",
        "signature_p256_sha256_der_hex": sig.read_bytes().hex(),
    },
    publisher_auth,
)
manifest_for_bundle_v2 = dict(manifest_for_bundle)
manifest_for_bundle_v2["version"] = "0.2.0"
manifest_for_bundle_v2["title"] = "SDK Service Package Smoke v2"
manifest_for_bundle_v2["summary"] = "Verifies SDK update status from obc-store-server"
bundle_io_v2 = io.BytesIO()
with zipfile.ZipFile(bundle_io_v2, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name, body in [
        ("package.json", (json.dumps(manifest_for_bundle_v2, indent=2, sort_keys=True) + "\n").encode("utf-8")),
        ("program.obc", obc_path.read_bytes()),
        ("assets/config.txt", b"pkg-asset"),
        ("assets/source/main.oren", b"print(\"service-bundle-source\")\n"),
    ]:
        info = zipfile.ZipInfo(name)
        info.date_time = (2026, 1, 1, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, body)
release_v2 = post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions",
    {
        "version": "0.2.0",
        "program_obc_base64": base64.b64encode(obc_path.read_bytes()).decode("ascii"),
        "release_bundle_base64": base64.b64encode(bundle_io_v2.getvalue()).decode("ascii"),
        "tags": ["sdk", "service", "update"],
        "min_app": "0.1.0",
        "manifest": {
            "title": "SDK Service Package Smoke v2",
            "summary": "Verifies SDK update status from obc-store-server",
            "oren_min": "0.0.rolling",
            "avm_abi_min": 8,
            "capabilities": ["CORE", "FS", "EXIT"],
            "time_mode": "deterministic",
            "budgets": {
                "gas": 5000000,
                "heap_bytes": 33554432,
                "io_bytes": 1048576,
                "frame_commands": 1024,
            },
            "vfs_mounts": [
                {"virtual": "assets", "package_path": "assets", "read_only": True}
            ],
        },
        "assets": [
            {
                "path": "assets/config.txt",
                "media_type": "text/plain",
                "content_base64": base64.b64encode(b"pkg-asset").decode("ascii"),
            }
        ],
    },
    publisher_auth,
)
msg.write_text(release_v2["manifest_sha256"], encoding="utf-8")
subprocess.check_call(["openssl", "dgst", "-sha256", "-sign", str(sign_key), "-out", str(sig), str(msg)], stdout=subprocess.DEVNULL)
post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions/0.2.0/publish",
    {
        "signature_alg": "p256-sha256-der",
        "signature_p256_sha256_der_hex": sig.read_bytes().hex(),
    },
    publisher_auth,
)
PY
cleanup_net_server() {
  stop_pid "${NET_SERVER_PID:-}"
  stop_pid "${TCP_SERVER_PID:-}"
  stop_pid "${UDP_SERVER_PID:-}"
  stop_pid "${WS_SERVER_PID:-}"
  stop_pid "${PKG_SERVER_PID:-}"
  stop_pid "${GO_STORE_PID:-}"
}
trap cleanup_net_server EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$NET_READY" && -f "$TCP_READY" && -f "$UDP_READY" && -f "$WS_READY" && -f "$PKG_READY" ]]; then
    break
  fi
  sleep 0.1
done
OREN_AVM_SDK_NET_PREFETCH=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="http://127.0.0.1:${NET_PORT}" \
OREN_AVM_SDK_PACKAGE_DIR="$PACKAGE_DIR" \
OREN_AVM_SDK_SCENE_PACKAGE_DIR="$SCENE_PACKAGE_DIR" \
OREN_AVM_SDK_PACKAGE_INDEX_URL="http://127.0.0.1:${PKG_PORT}/index.json" \
OREN_AVM_SDK_PACKAGE_DOWNLOAD_DIR="$TMP_DIR/downloaded_packages" \
OREN_AVM_SDK_SERVICE_PACKAGE_INDEX_URL="http://127.0.0.1:${GO_STORE_PORT}/api/v0/index.json" \
OREN_AVM_SDK_SERVICE_PACKAGE_DOWNLOAD_DIR="$TMP_DIR/downloaded_service_packages" \
OREN_AVM_SDK_STORE_INDEX_KEY_B64="$PACKAGE_PUBLISHER_KEY_B64" \
OREN_AVM_SDK_BAD_STORE_INDEX_KEY_B64="$BAD_STORE_INDEX_KEY_B64" \
OREN_AVM_SDK_PACKAGE_PUBLISHER_KEY_B64="$PACKAGE_PUBLISHER_KEY_B64" \
OREN_AVM_SDK_TRUST_BUNDLE_PATH="$TRUST_BUNDLE_JSON" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="http://127.0.0.1:${NET_PORT}" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp://127.0.0.1:${TCP_PORT}" OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp://127.0.0.1:$((TCP_PORT + 1))" \
OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" OREN_AVM_SDK_EXPECT_EXIT=57 "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp://127.0.0.1:${TCP_PORT}" \
OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" \
OREN_AVM_SDK_SESSION_BYTE_LIMIT=7 \
OREN_AVM_SDK_EXPECT_EXIT=60 \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},udp://127.0.0.1:${UDP_PORT}" \
OREN_AVM_SDK_TCP_URL="udp://127.0.0.1:${UDP_PORT}" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},ws://127.0.0.1:${WS_PORT}" \
OREN_AVM_SDK_TCP_URL="ws://127.0.0.1:${WS_PORT}/echo" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp-listen://127.0.0.1:${TCP_LISTEN_PORT}" \
OREN_AVM_SDK_TCP_LISTEN_URL="tcp-listen://127.0.0.1:${TCP_LISTEN_PORT}" \
  "$HOST_SDK_BIN" > "$LOG_DIR/libavm_ios_sdk_tcp_listen_host.log" 2>&1 &
TCP_LISTEN_HOST_PID=$!
python3 scripts/libavm_ios_verify_net_helpers.py tcp-listen-client --port "$TCP_LISTEN_PORT" > "$LOG_DIR/libavm_ios_sdk_tcp_listen_client.log" 2>&1
wait "$TCP_LISTEN_HOST_PID"
cleanup_net_server
trap - EXIT

echo "libavm iOS verify OK"
