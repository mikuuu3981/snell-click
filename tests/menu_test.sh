#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${ROOT_DIR}/tests/fixtures"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

export PATH="${FIXTURES}:${PATH}"
export NO_COLOR=1
export TERM=xterm
export SNELL_BASE_DIR="${TEMP_DIR}/etc/snell"
export BIN_DIR="${TEMP_DIR}/usr/local/bin"
export SYSTEMD_DIR="${TEMP_DIR}/etc/systemd/system"
export SNELL_COMMAND_PATH="${BIN_DIR}/snell"
export XRAY_BIN_PATH="${BIN_DIR}/xray"
export XRAY_CONFIG_DIR="${TEMP_DIR}/usr/local/etc/xray"
export XRAY_CONFIG_PATH="${XRAY_CONFIG_DIR}/config.json"
export XRAY_ASSET_DIR="${TEMP_DIR}/usr/local/share/xray"
export XRAY_SERVICE_PATH="${SYSTEMD_DIR}/xray.service"
export XRAY_SERVICE_NAME="xray-menu-test"

mkdir -p "$BIN_DIR" "$SYSTEMD_DIR"

assert_contains() {
  local output="$1" expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf '断言失败: 菜单输出中缺少 %q\n--- 输出 ---\n%s\n' "$expected" "$output" >&2
    exit 1
  fi
}

assert_not_contains() {
  local output="$1" unexpected="$2"
  if [[ "$output" == *"$unexpected"* ]]; then
    printf '断言失败: 菜单输出中不应包含 %q\n--- 输出 ---\n%s\n' "$unexpected" "$output" >&2
    exit 1
  fi
}

run_menu() {
  local input
  {
    for input in "$@"; do
      sleep 0.1
      printf '%s\n' "$input"
    done
  } | timeout 10 script -qec "bash ${ROOT_DIR}/snell.sh menu" /dev/null
}

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
  printf '%s\n' "$version" > "${conf_dir}/version"
  printf '[Unit]\nDescription=Snell %s Proxy Server %s\n' "$protocol" "$version" > "${SYSTEMD_DIR}/snell-${protocol}.service"
}

output="$(run_menu q)"
assert_contains "$output" "____ ___  ____  _____"
assert_contains "$output" "Hello World!"
assert_contains "$output" "核心概览"
assert_contains "$output" "Snell 管理"
assert_contains "$output" "Xray 管理"
assert_contains "$output" "检查面板更新"
assert_contains "$output" "q) 退出"
assert_not_contains "$output" "面板设置 / 升级"
assert_not_contains "$output" "注册 / 修复 snell 短命令"
assert_not_contains "$output" "管理 Snell v5"
assert_not_contains "$output" "管理 Snell v6"
assert_not_contains "$output" "选择要管理的实例"
assert_not_contains "$output" "迁移旧版单实例"

output="$(run_menu 1 1 q '' q q)"
assert_contains "$output" "│               Snell 核心管理               │"
assert_contains "$output" "安装 Snell 核心"
assert_contains "$output" "│              安装 Snell 核心               │"
assert_contains "$output" "Snell v5  ·  稳定版 v5.0.1"
assert_contains "$output" "Snell v6  ·  Beta v6.0.0rc"
assert_contains "$output" "q) 返回 Snell 管理"
assert_not_contains "$output" "生成客户端配置"
assert_not_contains "$output" "服务控制"

output="$(run_menu 2 q q)"
assert_contains "$output" "Xray 核心管理"
assert_contains "$output" "│               Xray 核心管理                │"
assert_contains "$output" "安装 / 修复 Xray 核心"

output="$(run_menu 3 n '' q)"
assert_contains "$output" "确认从官方仓库检查并升级管理面板"
assert_contains "$output" "已取消"

printf '#!/usr/bin/env bash\nexit 0\n' > "${BIN_DIR}/snell-server-v5"
chmod 755 "${BIN_DIR}/snell-server-v5"
output="$(run_menu 1 2 q q q)"
assert_contains "$output" "诊断 / 清理残留"
assert_contains "$output" "查看安装详情"
assert_contains "$output" "一键诊断"
assert_contains "$output" "清理残留文件"

setup_instance v5 v5.0.1 23505
output="$(run_menu 1 2 q q q)"
assert_contains "$output" "1) 生成客户端配置"
assert_contains "$output" "5) 更新 Snell 内核"
assert_not_contains "$output" "重装 Snell"
assert_contains "$output" "修改配置"
assert_contains "$output" "监听端口  ·  23505"
assert_contains "$output" "IPv6  ·  已关闭"
assert_contains "$output" "高级配置"
assert_not_contains "$output" "自定义 DNS"

output="$(run_menu 1 2 4 q q q q)"
assert_contains "$output" "自定义 DNS  ·  系统默认"
assert_not_contains "$output" "运行模式  ·"

setup_instance v6 v6.0.0rc 23606
output="$(run_menu 1 2 2 4 q q q q q)"
assert_contains "$output" "v5 与 v6 同时存在"
assert_contains "$output" "Snell v6 Beta"
assert_contains "$output" "高级配置"
assert_contains "$output" "自定义 DNS  ·  系统默认"
assert_contains "$output" "DNS IP 偏好  ·  自动选择"
assert_contains "$output" "出口网卡  ·  未绑定"
assert_contains "$output" "运行模式  ·  default"

output="$(run_menu 1 2 3 q q q q)"
assert_contains "$output" "重启服务"
assert_contains "$output" "关闭开机自启"
assert_contains "$output" "停止服务"

output="$(run_menu 1 2 5 '' n '' q q q)"
assert_contains "$output" "更新 Snell 内核"
assert_contains "$output" "目标版本 [v6.0.0rc]"
assert_contains "$output" "SSH 经由该实例连接"
assert_contains "$output" "已取消"

output="$(run_menu 1 2 4 5 q q q q q)"
assert_contains "$output" "日志与维护"
assert_contains "$output" "备份与恢复"
assert_contains "$output" "更新 Snell 内核"
assert_contains "$output" "6) 卸载 Snell"
assert_not_contains "$output" "6) 更新 Snell 内核"

mkdir -p "$XRAY_CONFIG_DIR"
cat > "$XRAY_BIN_PATH" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  version) echo 'Xray 26.3.27 (Xray, Penetrates Everything.) test' ;;
  uuid) echo '00000000-0000-4000-8000-000000000001' ;;
  x25519)
    echo 'PrivateKey: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    echo 'Password (PublicKey): BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
    ;;
  run) exit 0 ;;
esac
EOF
chmod 755 "$XRAY_BIN_PATH"
printf '{}\n' > "$XRAY_CONFIG_PATH"
printf '[Unit]\nDescription=Xray test service\n' > "$XRAY_SERVICE_PATH"

output="$(run_menu 2 q q)"
assert_contains "$output" "1) 入站管理"
assert_contains "$output" "3) 服务控制"
assert_contains "$output" "4) 查看最近日志"
assert_contains "$output" "5) 实时跟踪日志"
assert_not_contains "$output" "检查配置"
assert_not_contains "$output" "5) 日志"

output="$(run_menu 2 1 q q q)"
assert_contains "$output" "托管入站"
assert_contains "$output" "暂无托管入站"
assert_contains "$output" "添加 VLESS Reality 入站"

output="$(run_menu 2 1 a www.example.com '' '' y '' q q q)"
assert_contains "$output" "REALITY SNI"
assert_contains "$output" "监听端口 [443]"
assert_contains "$output" "入站 ID: 001 · 端口: 443"
assert_contains "$output" "vless://00000000-0000-4000-8000-000000000001@203.0.113.10:443"
[ "$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_PATH")" = "443" ]
[ "$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$XRAY_CONFIG_PATH")" = "www.example.com" ]

output="$(run_menu 2 4 '' q q)"
assert_contains "$output" "snell test log"

echo "menu_test: all assertions passed"
