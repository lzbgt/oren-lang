#!/usr/bin/env bash
set -euo pipefail

out_dir="${OREN_CA_DIR:-../oren-ca}"
store_id="${OREN_OBC_STORE_ID:-oren-store-dev}"
publisher_id="${OREN_OBC_PUBLISHER_ID:-oren-labs}"
force=0

usage() {
  cat <<'USAGE'
usage: scripts/issue_obc_store_trust.sh [options]

Issues OBC store signing material into an external directory. Private keys are
never written into this repository unless you explicitly point --out-dir here.

Options:
  --out-dir DIR        output trust/key directory (default: ${OREN_CA_DIR:-../oren-ca})
  --store-id ID       logical store key id (default: ${OREN_OBC_STORE_ID:-oren-store-dev})
  --publisher-id ID   logical publisher id (default: ${OREN_OBC_PUBLISHER_ID:-oren-labs})
  --force             replace existing private keys
  -h, --help          show this help

Outputs:
  DIR/private/*.pem              private P-256 keys, mode 600
  DIR/public/*.pem               public PEM keys
  DIR/public/*.p256.x963.b64     SDK-ready public key bytes
  DIR/trust/obc_store_trust.json host-app trust bundle
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      out_dir="${2:?missing --out-dir value}"
      shift 2
      ;;
    --store-id)
      store_id="${2:?missing --store-id value}"
      shift 2
      ;;
    --publisher-id)
      publisher_id="${2:?missing --publisher-id value}"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

safe_id() {
  printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9_.-' '_'
}

extract_x963_b64() {
  python3 - "$1" <<'PY'
import base64
import subprocess
import sys

der = subprocess.check_output(
    ["openssl", "ec", "-in", sys.argv[1], "-pubout", "-outform", "DER"],
    stderr=subprocess.DEVNULL,
)
idx = der.rfind(b"\x03\x42\x00\x04")
if idx < 0:
    raise SystemExit("missing P-256 public key bit string")
pub = der[idx + 3:idx + 68]
if len(pub) != 65 or pub[0] != 4:
    raise SystemExit("invalid P-256 public key length")
print(base64.b64encode(pub).decode("ascii"))
PY
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

store_safe="$(safe_id "$store_id")"
publisher_safe="$(safe_id "$publisher_id")"
private_dir="$out_dir/private"
public_dir="$out_dir/public"
trust_dir="$out_dir/trust"
store_key="$private_dir/store_${store_safe}_p256.pem"
publisher_key="$private_dir/publisher_${publisher_safe}_p256.pem"
store_pub_pem="$public_dir/store_${store_safe}_p256.pub.pem"
publisher_pub_pem="$public_dir/publisher_${publisher_safe}_p256.pub.pem"
store_pub_b64="$public_dir/store_${store_safe}.p256.x963.b64"
publisher_pub_b64="$public_dir/publisher_${publisher_safe}.p256.x963.b64"
trust_json="$trust_dir/obc_store_trust.json"

mkdir -p "$private_dir" "$public_dir" "$trust_dir"
chmod 700 "$private_dir"

make_key() {
  local path="$1"
  if [[ -e "$path" && "$force" -ne 1 ]]; then
    printf 'keeping existing private key: %s\n' "$path"
    return
  fi
  umask 077
  openssl ecparam -name prime256v1 -genkey -noout -out "$path"
  chmod 600 "$path"
  printf 'wrote private key: %s\n' "$path"
}

make_key "$store_key"
make_key "$publisher_key"

openssl ec -in "$store_key" -pubout -out "$store_pub_pem" >/dev/null 2>&1
openssl ec -in "$publisher_key" -pubout -out "$publisher_pub_pem" >/dev/null 2>&1
extract_x963_b64 "$store_key" > "$store_pub_b64"
extract_x963_b64 "$publisher_key" > "$publisher_pub_b64"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
store_key_b64="$(cat "$store_pub_b64")"
publisher_key_b64="$(cat "$publisher_pub_b64")"
store_id_json="$(json_escape "$store_id")"
publisher_id_json="$(json_escape "$publisher_id")"
generated_at_json="$(json_escape "$generated_at")"
store_key_json="$(json_escape "$store_key_b64")"
publisher_key_json="$(json_escape "$publisher_key_b64")"

cat > "$trust_json" <<JSON
{
  "schema": "oren.obc.trust.v0",
  "generated_at": $generated_at_json,
  "store_keys": [
    {
      "id": $store_id_json,
      "alg": "p256-sha256-der",
      "public_key_x963_b64": $store_key_json
    }
  ],
  "publisher_keys": {
    $publisher_id_json: {
      "alg": "p256-sha256-der",
      "public_key_x963_b64": $publisher_key_json
    }
  }
}
JSON

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/oren-obc-trust.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
printf 'oren-obc-store-trust-smoke' > "$tmp_dir/message.txt"
openssl dgst -sha256 -sign "$store_key" -out "$tmp_dir/store.sig" "$tmp_dir/message.txt"
openssl dgst -sha256 -verify "$store_pub_pem" -signature "$tmp_dir/store.sig" "$tmp_dir/message.txt" >/dev/null
openssl dgst -sha256 -sign "$publisher_key" -out "$tmp_dir/publisher.sig" "$tmp_dir/message.txt"
openssl dgst -sha256 -verify "$publisher_pub_pem" -signature "$tmp_dir/publisher.sig" "$tmp_dir/message.txt" >/dev/null
python3 -m json.tool "$trust_json" >/dev/null

cat <<EOF
OBC store trust material ready.
  private: $private_dir
  public:  $public_dir
  trust:   $trust_json

Host app hint:
  OREN_OBC_TRUST_BUNDLE=$trust_json
EOF
