#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${ROOT_DIR}/tests/fixtures"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

export PATH="${FIXTURES}:${PATH}"
export NO_COLOR=1
export SNELL_BASE_DIR="${TEMP_DIR}/etc/snell"
export BIN_DIR="${TEMP_DIR}/usr/local/bin"
export SYSTEMD_DIR="${TEMP_DIR}/etc/systemd/system"
unset BIN_PATH CONF_DIR CONF_PATH VERSION_PATH BACKUP_DIR SERVICE_PATH SERVICE_NAME SNELL_VERSION

mkdir -p "$BIN_DIR" "$SYSTEMD_DIR"

setup_instance() {
  local protocol="$1" version="$2" port="$3" conf_dir
  conf_dir="${SNELL_BASE_DIR}/${protocol}"
  mkdir -p "$conf_dir"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BIN_DIR}/snell-server-${protocol}"
  chmod 755 "${BIN_DIR}/snell-server-${protocol}"
  {
    echo '[snell-server]'
    printf 'listen = 0.0.0.0:%s\n' "$port"
    printf 'psk = %s\n' "${protocol}0123456789abcdef0123456789abcd"
    echo 'ipv6 = false'
    [ "$protocol" = "v6" ] && echo 'mode = default'
  } > "${conf_dir}/snell-server.conf"
  chown root:nogroup "${conf_dir}/snell-server.conf"
  chmod 640 "${conf_dir}/snell-server.conf"
  printf '%s\n' "$version" > "${conf_dir}/version"
  printf '[Unit]\nDescription=Snell %s Proxy Server %s\n' "$protocol" "$version" > "${SYSTEMD_DIR}/snell-${protocol}.service"
}

run_snell() {
  bash "${ROOT_DIR}/snell.sh" "$@"
}

assert_contains() {
  local output="$1" expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf '断言失败: 输出中缺少 %q\n--- 输出 ---\n%s\n' "$expected" "$output" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1" expected="$2"
  grep -Fq "$expected" "$file" || { printf '断言失败: %s 中缺少 %q\n' "$file" "$expected" >&2; exit 1; }
}

setup_instance v5 v5.0.1 23505
setup_instance v6 v6.0.0b4 23606

output="$(run_snell status-all)"
assert_contains "$output" "v5"
assert_contains "$output" "v5.0.1"
assert_contains "$output" "v6.0.0b4"
assert_contains "$output" "TCP/UDP"

output="$(run_snell v5 client v5.example.com)"
assert_contains "$output" "Snell-v5 = snell, v5.example.com, 23505"
assert_contains "$output" "version=5"
if [[ "$output" == *"mode="* ]]; then
  echo "断言失败: v5 客户端配置不应包含 v6 mode" >&2
  exit 1
fi

output="$(run_snell v6 client v6.example.com)"
assert_contains "$output" "Snell-v6 = snell, v6.example.com, 23606"
assert_contains "$output" "version=6"
assert_contains "$output" "mode=default"

run_snell v5 set-port 24505 >/dev/null
assert_file_contains "${SNELL_BASE_DIR}/v5/snell-server.conf" "listen = 0.0.0.0:24505"
assert_file_contains "${SNELL_BASE_DIR}/v6/snell-server.conf" "listen = 0.0.0.0:23606"
run_snell v5 set-ipv6 true >/dev/null
assert_file_contains "${SNELL_BASE_DIR}/v5/snell-server.conf" "listen = [::]:24505"
if grep -Fq "mode =" "${SNELL_BASE_DIR}/v5/snell-server.conf"; then
  echo "断言失败: v5 服务端配置不应写入 v6 mode" >&2
  exit 1
fi

if run_snell v5 set-mode unshaped >/dev/null 2>&1; then
  echo "断言失败: v5 不应接受 set-mode" >&2
  exit 1
fi

output="$(run_snell v5 diagnose)"
assert_contains "$output" "UDP 24505 正在监听（v5 QUIC）"
assert_contains "$output" "未发现影响运行的问题"

run_snell v5 uninstall >/dev/null
[ ! -e "${BIN_DIR}/snell-server-v5" ]
[ ! -e "${SNELL_BASE_DIR}/v5" ]
[ -x "${BIN_DIR}/snell-server-v6" ]
[ -f "${SNELL_BASE_DIR}/v6/snell-server.conf" ]
run_snell v6 status >/dev/null

mkdir -p "${SNELL_BASE_DIR}/backups"
printf '#!/usr/bin/env bash\nexit 0\n' > "${BIN_DIR}/snell-server"
chmod 755 "${BIN_DIR}/snell-server"
cat > "${SNELL_BASE_DIR}/snell-server.conf" <<'EOF'
[snell-server]
listen = 0.0.0.0:25505
psk = legacy0123456789abcdef0123456789
ipv6 = false
EOF
printf 'v5.0.1\n' > "${SNELL_BASE_DIR}/version"
printf '[Unit]\nDescription=Snell Proxy Server v5.0.1\n' > "${SYSTEMD_DIR}/snell.service"
printf 'legacy backup\n' > "${SNELL_BASE_DIR}/backups/legacy.conf"

run_snell migrate >/dev/null
[ ! -e "${BIN_DIR}/snell-server" ]
[ ! -e "${SYSTEMD_DIR}/snell.service" ]
[ -x "${BIN_DIR}/snell-server-v5" ]
assert_file_contains "${SNELL_BASE_DIR}/v5/snell-server.conf" "listen = 0.0.0.0:25505"
[ -f "${SNELL_BASE_DIR}/v5/backups/legacy.conf" ]
[ -f "${SNELL_BASE_DIR}/v6/snell-server.conf" ]

echo "coexist_test: all assertions passed"
