#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${ROOT_DIR}/tests/fixtures"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

export PATH="${FIXTURES}:${PATH}"
export NO_COLOR=1
export BIN_DIR="${TEMP_DIR}/usr/local/bin"
export SYSTEMD_DIR="${TEMP_DIR}/etc/systemd/system"
export SNELL_COMMAND_PATH="${BIN_DIR}/snell"
export XRAY_BIN_PATH="${BIN_DIR}/xray"
export XRAY_CONFIG_DIR="${TEMP_DIR}/usr/local/etc/xray"
export XRAY_CONFIG_PATH="${XRAY_CONFIG_DIR}/config.json"
export XRAY_BACKUP_DIR="${XRAY_CONFIG_DIR}/backups"
export XRAY_ASSET_DIR="${TEMP_DIR}/usr/local/share/xray"
export XRAY_LOG_DIR="${TEMP_DIR}/var/log/xray"
export XRAY_SERVICE_PATH="${SYSTEMD_DIR}/xray.service"
export XRAY_SERVICE_NAME="xray-test"
export XRAY_RELEASE_API="${TEMP_DIR}/release.json"
export XRAY_DOWNLOAD_BASE="${TEMP_DIR}/releases"
export XRAY_UNZIP_FIXTURE=true
export XRAY_UUID_COUNTER_FILE="${TEMP_DIR}/uuid-counter"

mkdir -p "$BIN_DIR" "$SYSTEMD_DIR"
printf '{"tag_name":"v26.3.27"}\n' > "$XRAY_RELEASE_API"

make_release() {
  local version="$1" package digest
  mkdir -p "${XRAY_DOWNLOAD_BASE}/${version}"
  for package in Xray-linux-64.zip Xray-linux-32.zip Xray-linux-arm64-v8a.zip; do
    printf 'xray archive fixture\n' > "${XRAY_DOWNLOAD_BASE}/${version}/${package}"
    digest="$(sha256sum "${XRAY_DOWNLOAD_BASE}/${version}/${package}" | awk '{ print $1 }')"
    printf 'SHA2-256= %s\n' "$digest" > "${XRAY_DOWNLOAD_BASE}/${version}/${package}.dgst"
  done
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

make_release v26.3.27
export XRAY_FIXTURE_VERSION=26.3.27
output="$(run_snell xray latest)"
[ "$output" = "v26.3.27" ]

make_release v26.0.0
printf 'SHA2-256= %064d\n' 0 > "${XRAY_DOWNLOAD_BASE}/v26.0.0/Xray-linux-64.zip.dgst"
if run_snell xray install v26.0.0 >/dev/null 2>&1; then
  echo "断言失败: SHA-256 不匹配的 Xray 安装包应被拒绝" >&2
  exit 1
fi
[ ! -e "$XRAY_BIN_PATH" ]

output="$(run_snell xray install)"
assert_contains "$output" "Xray v26.3.27 安装成功"
assert_contains "$output" "Xray 管理 → 入站管理"
[ -x "$XRAY_BIN_PATH" ]
[ -f "$XRAY_CONFIG_PATH" ]
[ -f "$XRAY_SERVICE_PATH" ]
[ -f "${XRAY_ASSET_DIR}/geoip.dat" ]
[ -f "${XRAY_LOG_DIR}/access.log" ]
[ "$(stat -c '%a' "${XRAY_LOG_DIR}/access.log")" = "600" ]
[ "$(stat -c '%a' "$XRAY_CONFIG_PATH")" = "640" ]
assert_file_contains "$XRAY_SERVICE_PATH" "ExecStart=${XRAY_BIN_PATH} run -config ${XRAY_CONFIG_PATH}"

output="$(run_snell xray status)"
assert_contains "$output" "v26.3.27"
assert_contains "$output" "运行中"
assert_contains "$output" "有效"
run_snell xray test | grep -Fq "配置有效"

printf '{"log":{"loglevel":"warning"}}\n' > "$XRAY_CONFIG_PATH"
make_release v26.4.1
export XRAY_FIXTURE_VERSION=26.4.1
output="$(run_snell xray update v26.4.1)"
assert_contains "$output" "Xray 已从 v26.3.27 更新到 v26.4.1"
assert_file_contains "$XRAY_CONFIG_PATH" '"loglevel":"warning"'

make_release v26.5.1
export XRAY_FIXTURE_VERSION=26.5.1
export SYSTEMCTL_FAIL_FILE="${TEMP_DIR}/fail-restart"
touch "$SYSTEMCTL_FAIL_FILE"
if run_snell xray update v26.5.1 >/dev/null 2>&1; then
  echo "断言失败: 新 Xray 核心启动失败时更新应返回失败" >&2
  exit 1
fi
rm -f "$SYSTEMCTL_FAIL_FILE"
unset SYSTEMCTL_FAIL_FILE
output="$(run_snell xray status)"
assert_contains "$output" "v26.4.1"
assert_file_contains "$XRAY_CONFIG_PATH" '"loglevel":"warning"'

if run_snell xray reality-add 'https://invalid.example/path' >/dev/null 2>&1; then
  echo "断言失败: 非法 SNI 应被拒绝" >&2
  exit 1
fi

output="$(run_snell xray reality-add www.example.com)"
assert_contains "$output" "入站 001 已创建"
assert_contains "$output" "端口: 443"
jq -e '
  .log.loglevel == "warning" and
  (.inbounds | length) == 1 and
  .inbounds[0].tag == "snell-managed-vless-reality-001" and
  .inbounds[0].port == 443 and
  .inbounds[0].settings.decryption == "none" and
  .inbounds[0].settings.clients[0].flow == "xtls-rprx-vision" and
  .inbounds[0].streamSettings.security == "reality" and
  .inbounds[0].streamSettings.realitySettings.serverNames[0] == "www.example.com" and
  .inbounds[0].streamSettings.realitySettings.target == "www.example.com:443"
' "$XRAY_CONFIG_PATH" >/dev/null

output="$(run_snell xray reality-add cdn.example.net)"
assert_contains "$output" "入站 002 已创建"
assert_contains "$output" "端口: 8443"
assert_contains "$output" "非 443 端口"
[ "$(jq -r '.inbounds[] | select(.tag == "snell-managed-vless-reality-002") | .port' "$XRAY_CONFIG_PATH")" = "8443" ]

output="$(run_snell xray inbounds)"
assert_contains "$output" "001"
assert_contains "$output" "REALITY/TCP"
assert_contains "$output" "www.example.com"

output="$(run_snell xray user-add 1 alice)"
assert_contains "$output" "用户 alice 已添加"
[ "$(jq -r '.inbounds[] | select(.tag == "snell-managed-vless-reality-001") | .settings.clients | length' "$XRAY_CONFIG_PATH")" = "2" ]

output="$(run_snell xray reality-edit 1 edge.example.org 9443)"
assert_contains "$output" "入站 001 已更新"
[ "$(jq -r '.inbounds[] | select(.tag == "snell-managed-vless-reality-001") | .port' "$XRAY_CONFIG_PATH")" = "9443" ]
assert_file_contains "$XRAY_CONFIG_PATH" 'edge.example.org:443'

output="$(run_snell xray reality-client 1 proxy.example.net)"
assert_contains "$output" "vless://00000000-0000-4000-8000-000000000001@proxy.example.net:9443"
assert_contains "$output" "security=reality"
assert_contains "$output" "pbk=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
assert_contains "$output" "mihomo / Clash Meta"
assert_contains "$output" "Mihomo 必须支持 Xray 26.3.27+ REALITY 握手"
assert_contains "$output" "servername: edge.example.org"

config_checksum="$(sha256sum "$XRAY_CONFIG_PATH")"
export SYSTEMCTL_FAIL_FILE="${TEMP_DIR}/fail-config-restart"
touch "$SYSTEMCTL_FAIL_FILE"
if run_snell xray user-add 1 rollback-test >/dev/null 2>&1; then
  echo "断言失败: Xray 配置应用后服务启动失败时操作应返回失败" >&2
  exit 1
fi
rm -f "$SYSTEMCTL_FAIL_FILE"
unset SYSTEMCTL_FAIL_FILE
[ "$(sha256sum "$XRAY_CONFIG_PATH")" = "$config_checksum" ]

run_snell xray user-delete 1 00000000-0000-4000-8000-000000000003 | grep -Fq "用户已从入站 001 删除"
[ "$(jq -r '.inbounds[] | select(.tag == "snell-managed-vless-reality-001") | .settings.clients | length' "$XRAY_CONFIG_PATH")" = "1" ]
run_snell xray reality-delete 2 | grep -Fq "入站 002 已删除"
[ "$(jq '[.inbounds[] | select(.tag | startswith("snell-managed-vless-reality-"))] | length' "$XRAY_CONFIG_PATH")" = "1" ]
[ "$(find "$XRAY_BACKUP_DIR" -maxdepth 1 -type f -name 'config-*.json' | wc -l)" -ge 6 ]

run_snell xray restart | grep -Fq "服务已重启"
run_snell xray logs 20 | grep -Fq "snell test log"

output="$(run_snell xray uninstall)"
assert_contains "$output" "配置与日志保持不变"
[ ! -e "$XRAY_BIN_PATH" ]
[ ! -e "$XRAY_SERVICE_PATH" ]
[ -f "$XRAY_CONFIG_PATH" ]
[ -f "${XRAY_LOG_DIR}/access.log" ]

echo "xray_test: all assertions passed"
