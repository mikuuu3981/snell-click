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
assert_contains "$output" "管理 Snell v5"
assert_contains "$output" "管理 Snell v6"
assert_contains "$output" "面板设置 / 升级"
assert_contains "$output" "q) 退出"
assert_not_contains "$output" "选择要管理的实例"
assert_not_contains "$output" "迁移旧版单实例"

output="$(run_menu 1 q q)"
assert_contains "$output" "安装 Snell v5"
assert_contains "$output" "q) 返回主菜单"
assert_not_contains "$output" "生成客户端配置"
assert_not_contains "$output" "服务控制"

printf '#!/usr/bin/env bash\nexit 0\n' > "${BIN_DIR}/snell-server-v5"
chmod 755 "${BIN_DIR}/snell-server-v5"
output="$(run_menu 1 2 q q q)"
assert_contains "$output" "诊断 / 清理残留"
assert_contains "$output" "查看安装详情"
assert_contains "$output" "一键诊断"
assert_contains "$output" "清理残留文件"

setup_instance v5 v5.0.1 23505
output="$(run_menu 1 3 2 q q q q)"
assert_contains "$output" "修改 PSK（留空自动生成）"
assert_not_contains "$output" "切换运行模式"

setup_instance v6 v6.0.0b4 23606
output="$(run_menu 2 4 q 3 5 q 7 q q 5 5 q q q q)"
assert_contains "$output" "重启服务"
assert_contains "$output" "关闭开机自启"
assert_contains "$output" "停止服务"
assert_contains "$output" "切换运行模式"
assert_contains "$output" "日志与维护"
assert_contains "$output" "备份与恢复"

echo "menu_test: all assertions passed"
