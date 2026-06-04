#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/deploy_obc_store_service.sh
       scripts/deploy_obc_store_service.sh --print-systemd-unit

Deploys the OBC store Go service binary to a SSH host. This script does not
create private keys and does not copy signing keys unless explicitly requested.

Required:
  OBC_STORE_SSH_TARGET=user@store.hubstack.cn

Optional:
  OBC_STORE_REMOTE_DIR=/opt/oren/obc-store
  OBC_STORE_REMOTE_DATA_DIR=/srv/oren/obc-store
  OBC_STORE_LISTEN_ADDR=127.0.0.1:8080
  OBC_STORE_ADMIN_ENV=../oren-ca/obc-store-admin.env
  OBC_STORE_ADMIN_TOKEN_SHA256_HEX=<sha256 hex of deploy bearer token>
  OBC_STORE_INDEX_SIGN_KEY_PEM=../oren-ca/private/store_oren-store-dev_p256.pem
  OBC_STORE_INDEX_SIGN_KEY_ID=oren-store-dev
  OBC_STORE_COPY_INDEX_SIGNING_KEY=1
  OBC_STORE_TRUST_BUNDLE=../oren-ca/trust/obc_store_trust.json
  OBC_STORE_COPY_TRUST_BUNDLE=1
  OBC_STORE_SSH_OPTS="-o BatchMode=yes"
  OBC_STORE_INSTALL_SYSTEMD=1
  OBC_STORE_SYSTEMD_SERVICE=oren-obc-store.service
  OBC_STORE_SYSTEMD_SUDO="sudo -n"
  OBC_STORE_REMOTE_HEALTHCHECK=1
  OBC_STORE_REMOTE_HEALTH_URL=http://127.0.0.1:8080/api/v0/health

The cloud host Traefik layer owns DNS and HTTPS for store.hubstack.cn. Configure
its route to the service listener chosen by the host operator after deployment.
If Traefik runs in Docker, bind to a host bridge address such as
OBC_STORE_LISTEN_ADDR=172.20.0.1:18080; Dockerized Traefik cannot reach a
backend bound only to host 127.0.0.1.
USAGE
}

emit_systemd_unit() {
  cat <<EOF
[Unit]
Description=Oren OBC Store Service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$remote_dir
EnvironmentFile=$remote_dir/obc-store.env
ExecStart=$remote_dir/obc-store-server -addr $listen_addr -data-dir $remote_data_dir
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=$remote_data_dir $remote_dir

[Install]
WantedBy=multi-user.target
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

remote_dir="${OBC_STORE_REMOTE_DIR:-/opt/oren/obc-store}"
remote_data_dir="${OBC_STORE_REMOTE_DATA_DIR:-/srv/oren/obc-store}"
listen_addr="${OBC_STORE_LISTEN_ADDR:-127.0.0.1:8080}"
admin_env="${OBC_STORE_ADMIN_ENV:-../oren-ca/obc-store-admin.env}"
ssh_opts="${OBC_STORE_SSH_OPTS:-}"
copy_index_key="${OBC_STORE_COPY_INDEX_SIGNING_KEY:-0}"
index_key="${OBC_STORE_INDEX_SIGN_KEY_PEM:-}"
index_key_id="${OBC_STORE_INDEX_SIGN_KEY_ID:-}"
copy_trust_bundle="${OBC_STORE_COPY_TRUST_BUNDLE:-0}"
trust_bundle="${OBC_STORE_TRUST_BUNDLE:-}"
install_systemd="${OBC_STORE_INSTALL_SYSTEMD:-0}"
systemd_service="${OBC_STORE_SYSTEMD_SERVICE:-oren-obc-store.service}"
systemd_sudo="${OBC_STORE_SYSTEMD_SUDO:-sudo -n}"
remote_healthcheck="${OBC_STORE_REMOTE_HEALTHCHECK:-0}"
remote_health_port="${listen_addr##*:}"
if [[ -z "$remote_health_port" || "$remote_health_port" == "$listen_addr" ]]; then
  remote_health_port="8080"
fi
remote_health_url="${OBC_STORE_REMOTE_HEALTH_URL:-http://127.0.0.1:$remote_health_port/api/v0/health}"

if [[ "$systemd_service" != *.service || "$systemd_service" == */* ]]; then
  echo "ERROR: OBC_STORE_SYSTEMD_SERVICE must be a bare *.service unit name" >&2
  exit 2
fi

if [[ "${1:-}" == "--print-systemd-unit" ]]; then
  emit_systemd_unit
  exit 0
fi
if [[ -n "${1:-}" ]]; then
  usage >&2
  echo "ERROR: unsupported argument: $1" >&2
  exit 2
fi

ssh_target="${OBC_STORE_SSH_TARGET:-}"
if [[ -z "$ssh_target" ]]; then
  usage >&2
  echo "ERROR: OBC_STORE_SSH_TARGET is required" >&2
  exit 2
fi

if [[ ! -f "$admin_env" ]]; then
  echo "ERROR: missing admin env: $admin_env" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$admin_env"
: "${OBC_STORE_ADMIN_USERNAME:=admin}"
if [[ -z "${OBC_STORE_ADMIN_PASSWORD:-}" && -z "${OBC_STORE_ADMIN_TOKEN_SHA256_HEX:-}" ]]; then
  echo "ERROR: admin env must set OBC_STORE_ADMIN_PASSWORD or OBC_STORE_ADMIN_TOKEN_SHA256_HEX" >&2
  exit 2
fi

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

remote_trust_bundle=""
if [[ "$copy_trust_bundle" == "1" ]]; then
  if [[ -z "$trust_bundle" || ! -f "$trust_bundle" ]]; then
    echo "ERROR: OBC_STORE_COPY_TRUST_BUNDLE=1 requires OBC_STORE_TRUST_BUNDLE" >&2
    exit 2
  fi
  ssh $ssh_opts "$ssh_target" "mkdir -p '$remote_dir/trust' && chmod 755 '$remote_dir/trust'"
  scp $ssh_opts "$trust_bundle" "$ssh_target:$remote_dir/trust/obc_store_trust.json.new"
  ssh $ssh_opts "$ssh_target" "chmod 644 '$remote_dir/trust/obc_store_trust.json.new' && mv '$remote_dir/trust/obc_store_trust.json.new' '$remote_dir/trust/obc_store_trust.json'"
  remote_trust_bundle="$remote_dir/trust/obc_store_trust.json"
elif [[ -n "$trust_bundle" ]]; then
  remote_trust_bundle="$trust_bundle"
fi

env_tmp="$tmp_dir/obc-store.env"
{
  printf 'OBC_STORE_ADMIN_USERNAME=%q\n' "$OBC_STORE_ADMIN_USERNAME"
  if [[ -n "${OBC_STORE_ADMIN_PASSWORD:-}" ]]; then
    printf 'OBC_STORE_ADMIN_PASSWORD=%q\n' "$OBC_STORE_ADMIN_PASSWORD"
  fi
  if [[ -n "${OBC_STORE_ADMIN_TOKEN_SHA256_HEX:-}" ]]; then
    printf 'OBC_STORE_ADMIN_TOKEN_SHA256_HEX=%q\n' "$OBC_STORE_ADMIN_TOKEN_SHA256_HEX"
  fi
  if [[ -n "$remote_index_key" ]]; then
    printf 'OBC_STORE_INDEX_SIGN_KEY_PEM=%q\n' "$remote_index_key"
  fi
  if [[ -n "$index_key_id" ]]; then
    printf 'OBC_STORE_INDEX_SIGN_KEY_ID=%q\n' "$index_key_id"
  fi
  if [[ -n "$remote_trust_bundle" ]]; then
    printf 'OBC_STORE_TRUST_BUNDLE=%q\n' "$remote_trust_bundle"
  fi
} > "$env_tmp"
scp $ssh_opts "$env_tmp" "$ssh_target:$remote_dir/obc-store.env.new"
ssh $ssh_opts "$ssh_target" "chmod 600 '$remote_dir/obc-store.env.new' && mv '$remote_dir/obc-store.env.new' '$remote_dir/obc-store.env'"

if [[ "$install_systemd" == "1" ]]; then
  unit_tmp="$tmp_dir/$systemd_service"
  emit_systemd_unit > "$unit_tmp"
  scp $ssh_opts "$unit_tmp" "$ssh_target:$remote_dir/$systemd_service.new"
  ssh $ssh_opts "$ssh_target" "$systemd_sudo install -m 0644 '$remote_dir/$systemd_service.new' '/etc/systemd/system/$systemd_service' && rm -f '$remote_dir/$systemd_service.new' && $systemd_sudo systemctl daemon-reload && $systemd_sudo systemctl enable --now '$systemd_service' && $systemd_sudo systemctl restart '$systemd_service'"
fi

if [[ "$remote_healthcheck" == "1" ]]; then
  ssh $ssh_opts "$ssh_target" "for i in 1 2 3 4 5; do curl -fsS '$remote_health_url' >/dev/null && exit 0; sleep 1; done; curl -fsS '$remote_health_url' >/dev/null"
fi

cat <<EOF
OBC store binary deployed.
  target:    $ssh_target
  binary:    $remote_dir/obc-store-server
  env:       $remote_dir/obc-store.env
  data dir:  $remote_data_dir
  listen:    $listen_addr

Run command on host:
  cd '$remote_dir' && set -a && . ./obc-store.env && set +a && ./obc-store-server -addr '$listen_addr' -data-dir '$remote_data_dir'
EOF

if [[ "$install_systemd" == "1" ]]; then
  route_backend_host="${listen_addr%:*}"
  route_backend_port="${listen_addr##*:}"
  route_backend="http://$listen_addr"
  if [[ "$route_backend_host" == "0.0.0.0" || "$route_backend_host" == "::" || "$route_backend_host" == "[::]" ]]; then
    route_backend="http://<host-reachable-ip>:$route_backend_port"
  fi
  cat <<EOF

Systemd service installed:
  $systemd_service

Traefik should route store.hubstack.cn to this backend when Traefik can reach it:
  $route_backend
EOF
fi
