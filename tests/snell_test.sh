#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${ROOT_DIR}/tests/fixtures"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

export PATH="${FIXTURES}:${PATH}"
export NO_COLOR=1
export BIN_PATH="${TEMP_DIR}/usr/local/bin/snell-server"
export CONF_DIR="${TEMP_DIR}/etc/snell"
export CONF_PATH="${CONF_DIR}/snell-server.conf"
export VERSION_PATH="${CONF_DIR}/version"
export BACKUP_DIR="${CONF_DIR}/backups"
export SERVICE_PATH="${TEMP_DIR}/etc/systemd/system/snell.service"
export SERVICE_NAME="snell-test"

mkdir -p "$(dirname "$BIN_PATH")" "$CONF_DIR" "$(dirname "$SERVICE_PATH")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN_PATH"
chmod 755 "$BIN_PATH"
cat > "$CONF_PATH" <<'EOF'
[snell-server]
listen = ::0:23333
psk = 0123456789abcdef0123456789abcdef
ipv6 = true
mode = default
dns = 1.1.1.1,8.8.8.8
dns-ip-preference = default
egress-interface = eth9
EOF
chown root:nogroup "$CONF_PATH"
chmod 640 "$CONF_PATH"
printf 'v6.0.0b4\n' > "$VERSION_PATH"
printf '[Unit]\nDescription=Snell Proxy Server v6.0.0b4\n' > "$SERVICE_PATH"

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
  if ! grep -Fq "$expected" "$file"; then
    printf '断言失败: %s 中缺少 %q\n' "$file" "$expected" >&2
    exit 1
  fi
}

output="$(run_snell status)"
assert_contains "$output" "运行中"
assert_contains "$output" "0123…cdef"
if [[ "$output" == *"0123456789abcdef0123456789abcdef"* ]]; then
  echo "断言失败: 状态页泄露了完整 PSK" >&2
  exit 1
fi

output="$(run_snell client snell.example.com)"
assert_contains "$output" "Snell-v6 = snell, snell.example.com, 23333"
assert_contains "$output" "type: snell"
assert_contains "$output" "version: 6"

run_snell set-port 24444 >/dev/null
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444,[::]:24444"
[ "$(stat -c '%a' "$CONF_PATH")" = "640" ]

export SS_OCCUPIED_TCP_PORT=25554
if run_snell set-port 25554 >/dev/null 2>&1; then
  echo "断言失败: 已占用 TCP 端口应被拒绝" >&2
  exit 1
fi
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444,[::]:24444"
unset SS_OCCUPIED_TCP_PORT

export SS_OCCUPIED_UDP_PORT=25555
if run_snell set-port 25555 >/dev/null 2>&1; then
  echo "断言失败: 已占用 UDP 端口应被拒绝" >&2
  exit 1
fi
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444,[::]:24444"
unset SS_OCCUPIED_UDP_PORT

export SS_FAIL=true
if run_snell set-port 25556 >/dev/null 2>&1; then
  echo "断言失败: 端口探测失败时应拒绝修改" >&2
  exit 1
fi
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444,[::]:24444"
unset SS_FAIL

run_snell set-mode unshaped >/dev/null
assert_file_contains "$CONF_PATH" "mode = unshaped"

run_snell set-ipv6 false >/dev/null
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444"
assert_file_contains "$CONF_PATH" "ipv6 = false"
assert_file_contains "$CONF_PATH" "dns = 1.1.1.1,8.8.8.8"
assert_file_contains "$CONF_PATH" "egress-interface = eth9"

backup="$(run_snell backup)"
run_snell set-dns 9.9.9.9,149.112.112.112 >/dev/null
run_snell set-dns-preference prefer-ipv4 >/dev/null
run_snell set-egress eth0 >/dev/null
run_snell set-psk abcdefgh12345678 >/dev/null
assert_file_contains "$CONF_PATH" "psk = abcdefgh12345678"
assert_file_contains "$CONF_PATH" "dns = 9.9.9.9,149.112.112.112"
assert_file_contains "$CONF_PATH" "dns-ip-preference = prefer-ipv4"
assert_file_contains "$CONF_PATH" "egress-interface = eth0"
run_snell restore "$backup" >/dev/null
assert_file_contains "$CONF_PATH" "psk = 0123456789abcdef0123456789abcdef"
assert_file_contains "$CONF_PATH" "dns = 1.1.1.1,8.8.8.8"
assert_file_contains "$CONF_PATH" "dns-ip-preference = default"
assert_file_contains "$CONF_PATH" "egress-interface = eth9"

if run_snell set-port 70000 >/dev/null 2>&1; then
  echo "断言失败: 非法端口应被拒绝" >&2
  exit 1
fi
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444"

export SYSTEMCTL_FAIL_FILE="${TEMP_DIR}/fail-restart"
touch "$SYSTEMCTL_FAIL_FILE"
if run_snell set-port 25555 >/dev/null 2>&1; then
  echo "断言失败: 服务重启失败时配置变更也应失败" >&2
  exit 1
fi
rm -f "$SYSTEMCTL_FAIL_FILE"
assert_file_contains "$CONF_PATH" "listen = 0.0.0.0:24444"
[ "$(stat -c '%a' "$CONF_PATH")" = "640" ]

output="$(run_snell diagnose)"
assert_contains "$output" "未发现影响运行的问题"

run_snell logs 20 | grep -Fq "snell test log"
run_snell uninstall >/dev/null
[ ! -e "$BIN_PATH" ]
[ ! -e "$CONF_DIR" ]
[ ! -e "$SERVICE_PATH" ]

echo "snell_test: all assertions passed"
