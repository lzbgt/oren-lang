#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/deploy_obc_store_service.sh

Deploys the OBC store Go service binary to a SSH host. This script does not
create private keys and does not copy signing keys unless explicitly requested.

Required:
  OBC_STORE_SSH_TARGET=user@store.hubstack.cn

Optional:
  OBC_STORE_REMOTE_DIR=/opt/oren/obc-store
  OBC_STORE_REMOTE_DATA_DIR=/srv/oren/obc-store
  OBC_STORE_ADMIN_ENV=../oren-ca/obc-store-admin.env
  OBC_STORE_INDEX_SIGN_KEY_PEM=../oren-ca/private/store_oren-store-dev_p256.pem
  OBC_STORE_COPY_INDEX_SIGNING_KEY=1
  OBC_STORE_SSH_OPTS="-o BatchMode=yes"

After deploy, configure Traefik to route store.hubstack.cn to the service
listener chosen by the host operator.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ssh_target="${OBC_STORE_SSH_TARGET:-}"
if [[ -z "$ssh_target" ]]; then
  usage >&2
  echo "ERROR: OBC_STORE_SSH_TARGET is required" >&2
  exit 2
fi

remote_dir="${OBC_STORE_REMOTE_DIR:-/opt/oren/obc-store}"
remote_data_dir="${OBC_STORE_REMOTE_DATA_DIR:-/srv/oren/obc-store}"
admin_env="${OBC_STORE_ADMIN_ENV:-../oren-ca/obc-store-admin.env}"
ssh_opts="${OBC_STORE_SSH_OPTS:-}"
copy_index_key="${OBC_STORE_COPY_INDEX_SIGNING_KEY:-0}"
index_key="${OBC_STORE_INDEX_SIGN_KEY_PEM:-}"

if [[ ! -f "$admin_env" ]]; then
  echo "ERROR: missing admin env: $admin_env" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$admin_env"
: "${OBC_STORE_ADMIN_USERNAME:?missing OBC_STORE_ADMIN_USERNAME in admin env}"
: "${OBC_STORE_ADMIN_PASSWORD:?missing OBC_STORE_ADMIN_PASSWORD in admin env}"

remote_arch="$(ssh $ssh_opts "$ssh_target" 'uname -m')"
case "$remote_arch" in
  x86_64|amd64) goarch=amd64 ;;
  arm64|aarch64) goarch=arm64 ;;
  *)
    echo "ERROR: unsupported remote arch: $remote_arch" >&2
    exit 2
    ;;
esac

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/oren-obc-store-deploy.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
bin="$tmp_dir/obc-store-server"
GOOS=linux GOARCH="$goarch" go build -o "$bin" ./cmd/obc-store-server

ssh $ssh_opts "$ssh_target" "mkdir -p '$remote_dir' '$remote_data_dir'"
scp $ssh_opts "$bin" "$ssh_target:$remote_dir/obc-store-server.new"
ssh $ssh_opts "$ssh_target" "chmod 755 '$remote_dir/obc-store-server.new' && mv '$remote_dir/obc-store-server.new' '$remote_dir/obc-store-server'"

remote_index_key=""
if [[ "$copy_index_key" == "1" ]]; then
  if [[ -z "$index_key" || ! -f "$index_key" ]]; then
    echo "ERROR: OBC_STORE_COPY_INDEX_SIGNING_KEY=1 requires OBC_STORE_INDEX_SIGN_KEY_PEM" >&2
    exit 2
  fi
  ssh $ssh_opts "$ssh_target" "mkdir -p '$remote_dir/private' && chmod 700 '$remote_dir/private'"
  scp $ssh_opts "$index_key" "$ssh_target:$remote_dir/private/index-signing-key.pem"
  ssh $ssh_opts "$ssh_target" "chmod 600 '$remote_dir/private/index-signing-key.pem'"
  remote_index_key="$remote_dir/private/index-signing-key.pem"
fi

env_tmp="$tmp_dir/obc-store.env"
{
  printf 'OBC_STORE_ADMIN_USERNAME=%q\n' "$OBC_STORE_ADMIN_USERNAME"
  printf 'OBC_STORE_ADMIN_PASSWORD=%q\n' "$OBC_STORE_ADMIN_PASSWORD"
  if [[ -n "$remote_index_key" ]]; then
    printf 'OBC_STORE_INDEX_SIGN_KEY_PEM=%q\n' "$remote_index_key"
  fi
} > "$env_tmp"
scp $ssh_opts "$env_tmp" "$ssh_target:$remote_dir/obc-store.env.new"
ssh $ssh_opts "$ssh_target" "chmod 600 '$remote_dir/obc-store.env.new' && mv '$remote_dir/obc-store.env.new' '$remote_dir/obc-store.env'"

cat <<EOF
OBC store binary deployed.
  target:    $ssh_target
  binary:    $remote_dir/obc-store-server
  env:       $remote_dir/obc-store.env
  data dir:  $remote_data_dir

Run command on host:
  cd '$remote_dir' && set -a && . ./obc-store.env && set +a && ./obc-store-server -addr :8080 -data-dir '$remote_data_dir'
EOF
