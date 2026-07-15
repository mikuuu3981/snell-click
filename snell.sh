#!/usr/bin/env bash
#
# Snell v5 / v6 多实例配置管理面板 (Debian/Ubuntu, root)
#
# 常用命令:
#   snell                          打开交互式管理面板
#   snell v6 install               安装 / 重装 v6
#   snell v5 status                查看 v5 运行概览
#   snell v6 client [地址]         输出 v6 客户端配置
#   snell self-update              升级管理面板
#   snell help                     查看全部命令
#
set -euo pipefail

# ---------------- 可自定义 ----------------
SNELL_V5_VERSION="${SNELL_V5_VERSION:-v5.0.1}"
SNELL_V6_VERSION="${SNELL_V6_VERSION:-v6.0.0b4}"
SNELL_PROTOCOL="${SNELL_PROTOCOL:-v6}"         # v5 / v6
SNELL_VERSION_OVERRIDE="${SNELL_VERSION:-}"
SNELL_PORT="${SNELL_PORT:-}"                  # 留空则随机选择 20000-40000
SNELL_MODE="${SNELL_MODE:-default}"           # default / unshaped / unsafe-raw
SNELL_IPV6_OVERRIDE="${SNELL_IPV6:-}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://dl.nssurge.com/snell}"
SNELL_MANAGER_URL="${SNELL_MANAGER_URL:-https://raw.githubusercontent.com/mikuuu3981/snell-click/main/snell.sh}"
# -------------------------------------------

SNELL_BASE_DIR="${SNELL_BASE_DIR:-/etc/snell}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SNELL_COMMAND_PATH="${SNELL_COMMAND_PATH:-${BIN_DIR}/snell}"
BIN_PATH_OVERRIDE="${BIN_PATH:-}"
CONF_DIR_OVERRIDE="${CONF_DIR:-}"
CONF_PATH_OVERRIDE="${CONF_PATH:-}"
VERSION_PATH_OVERRIDE="${VERSION_PATH:-}"
BACKUP_DIR_OVERRIDE="${BACKUP_DIR:-}"
SERVICE_PATH_OVERRIDE="${SERVICE_PATH:-}"
SERVICE_NAME_OVERRIDE="${SERVICE_NAME:-}"
LEGACY_BIN_PATH="${LEGACY_BIN_PATH:-${BIN_DIR}/snell-server}"
LEGACY_CONF_PATH="${LEGACY_CONF_PATH:-${SNELL_BASE_DIR}/snell-server.conf}"
LEGACY_VERSION_PATH="${LEGACY_VERSION_PATH:-${SNELL_BASE_DIR}/version}"
LEGACY_BACKUP_DIR="${LEGACY_BACKUP_DIR:-${SNELL_BASE_DIR}/backups}"
LEGACY_SERVICE_PATH="${LEGACY_SERVICE_PATH:-${SYSTEMD_DIR}/snell.service}"
LEGACY_SERVICE_NAME="${LEGACY_SERVICE_NAME:-snell}"

use_instance() {
  local protocol="${1:-}"
  case "$protocol" in
    v5|v6) ;;
    *) red "协议实例只能是 v5 或 v6。"; return 1 ;;
  esac
  SNELL_PROTOCOL="$protocol"
  PROTOCOL_VERSION="${protocol#v}"
  if [ -n "$SNELL_VERSION_OVERRIDE" ]; then
    SNELL_VERSION="$SNELL_VERSION_OVERRIDE"
  elif [ "$protocol" = "v5" ]; then
    SNELL_VERSION="$SNELL_V5_VERSION"
  else
    SNELL_VERSION="$SNELL_V6_VERSION"
  fi
  if [ -n "$SNELL_IPV6_OVERRIDE" ]; then
    SNELL_IPV6="$SNELL_IPV6_OVERRIDE"
  elif [ "$protocol" = "v5" ]; then
    SNELL_IPV6="false"
  else
    SNELL_IPV6="true"
  fi
  BIN_PATH="${BIN_PATH_OVERRIDE:-${BIN_DIR}/snell-server-${protocol}}"
  CONF_DIR="${CONF_DIR_OVERRIDE:-${SNELL_BASE_DIR}/${protocol}}"
  CONF_PATH="${CONF_PATH_OVERRIDE:-${CONF_DIR}/snell-server.conf}"
  VERSION_PATH="${VERSION_PATH_OVERRIDE:-${CONF_DIR}/version}"
  BACKUP_DIR="${BACKUP_DIR_OVERRIDE:-${CONF_DIR}/backups}"
  SERVICE_PATH="${SERVICE_PATH_OVERRIDE:-${SYSTEMD_DIR}/snell-${protocol}.service}"
  SERVICE_NAME="${SERVICE_NAME_OVERRIDE:-snell-${protocol}}"
}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
  C_BLUE='\033[94m'; C_MAGENTA='\033[35m'; C_CYAN='\033[36m'
  C_WHITE='\033[97m'; C_GRAY='\033[90m'; C_BOLD='\033[1m'; C_RESET='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
  C_WHITE=''; C_GRAY=''; C_BOLD=''; C_RESET=''
fi

red()    { printf '%b\n' "${C_RED}$*${C_RESET}"; }
green()  { printf '%b\n' "${C_GREEN}$*${C_RESET}"; }
yellow() { printf '%b\n' "${C_YELLOW}$*${C_RESET}"; }
info()   { printf '%b\n' "${C_CYAN}[*]${C_RESET} $*"; }
success(){ printf '%b\n' "${C_GREEN}[ok]${C_RESET} $*"; }
warn()   { printf '%b\n' "${C_YELLOW}[!]${C_RESET} $*"; }

section_title() {
  printf '%b%s%b\n' "${C_BOLD}${C_WHITE}" "$1" "$C_RESET"
  printf '%b%s%b\n' "$C_GRAY" '────────────────────────────────────────' "$C_RESET"
}

menu_option() {
  local number="$1" label="$2" style="${3:-normal}" color="$C_CYAN"
  case "$style" in
    accent) color="$C_MAGENTA" ;;
    danger) color="$C_RED" ;;
    back) color="$C_GRAY" ;;
  esac
  printf '  %b%-2s%b %s\n' "${color}${C_BOLD}" "${number})" "$C_RESET" "$label"
}

state_color() {
  case "${1:-}" in
    运行中|已安装|已注册|是) printf '%s' "$C_GREEN" ;;
    已停止|未安装|否) printf '%s' "$C_YELLOW" ;;
    *) printf '%s' "$C_RED" ;;
  esac
}

detail_row() {
  local label="$1" value="$2" color="${3:-$C_WHITE}"
  printf '  %b%-14s%b %b%s%b\n' "$C_GRAY" "$label" "$C_RESET" "$color" "$value" "$C_RESET"
}

use_instance "$SNELL_PROTOCOL"

need_root() {
  [ "$(id -u)" -eq 0 ] || { red "请使用 root 权限运行此操作。"; exit 1; }
}

is_snell_manager_script() {
  local path="${1:-}"
  [ -f "$path" ] && grep -Fq 'Snell v5 / v6 多实例配置管理面板' "$path" 2>/dev/null
}

fetch_manager_script() {
  local destination="$1" local_source=""
  if [ -f "$SNELL_MANAGER_URL" ]; then
    cp "$SNELL_MANAGER_URL" "$destination" || return 1
    return 0
  fi
  if [[ "$SNELL_MANAGER_URL" == file://* ]]; then
    local_source="${SNELL_MANAGER_URL#file://}"
    if [ -f "$local_source" ]; then
      cp "$local_source" "$destination" || return 1
      return 0
    fi
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SNELL_MANAGER_URL" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$destination" "$SNELL_MANAGER_URL"
  else
    red "下载管理脚本需要 curl 或 wget。"
    return 1
  fi
}

validate_manager_script() {
  local path="$1"
  is_snell_manager_script "$path" && bash -n "$path"
}

install_manager_script() {
  local source="$1" target_temp
  if ! mkdir -p "$(dirname "$SNELL_COMMAND_PATH")"; then
    return 1
  fi
  if ! target_temp="$(mktemp "${SNELL_COMMAND_PATH}.tmp.XXXXXX")"; then
    return 1
  fi
  if ! install -m 755 "$source" "$target_temp"; then
    rm -f "$target_temp"
    return 1
  fi
  if ! mv -f "$target_temp" "$SNELL_COMMAND_PATH"; then
    rm -f "$target_temp"
    return 1
  fi
}

register_short_command() {
  local quiet="${1:-false}" source="${BASH_SOURCE[0]}" staged=""
  need_root

  if { [ -e "$SNELL_COMMAND_PATH" ] || [ -L "$SNELL_COMMAND_PATH" ]; } &&
     ! [ "$source" -ef "$SNELL_COMMAND_PATH" ] &&
     ! is_snell_manager_script "$SNELL_COMMAND_PATH"; then
    red "无法注册短命令: ${SNELL_COMMAND_PATH} 已被其他程序占用。"
    return 1
  fi

  if [ -e "$SNELL_COMMAND_PATH" ] && [ "$source" -ef "$SNELL_COMMAND_PATH" ]; then
    if ! chmod 755 "$SNELL_COMMAND_PATH"; then
      red "短命令权限修复失败: ${SNELL_COMMAND_PATH}"
      return 1
    fi
  elif [ -f "$source" ]; then
    if [ -f "$SNELL_COMMAND_PATH" ] && cmp -s "$source" "$SNELL_COMMAND_PATH"; then
      if ! chmod 755 "$SNELL_COMMAND_PATH"; then
        red "短命令权限修复失败: ${SNELL_COMMAND_PATH}"
        return 1
      fi
    elif ! install_manager_script "$source"; then
      red "短命令注册失败: 无法写入 ${SNELL_COMMAND_PATH}。"
      return 1
    fi
  else
    if ! staged="$(mktemp)"; then
      red "短命令注册失败: 无法创建临时文件。"
      return 1
    fi
    if ! fetch_manager_script "$staged"; then
      rm -f "$staged"
      red "短命令注册失败: 无法下载管理脚本。"
      return 1
    fi
    if ! validate_manager_script "$staged"; then
      rm -f "$staged"
      red "短命令注册失败: 下载的文件不是有效的 Snell 管理脚本。"
      return 1
    fi
    if ! install_manager_script "$staged"; then
      rm -f "$staged"
      red "短命令注册失败: 无法写入 ${SNELL_COMMAND_PATH}。"
      return 1
    fi
    rm -f "$staged"
  fi

  [ "$quiet" = "true" ] || success "短命令已注册: 以后可直接运行 snell"
}

update_manager() {
  local staged
  need_root
  if { [ -e "$SNELL_COMMAND_PATH" ] || [ -L "$SNELL_COMMAND_PATH" ]; } &&
     ! is_snell_manager_script "$SNELL_COMMAND_PATH"; then
    red "无法升级面板: ${SNELL_COMMAND_PATH} 已被其他程序占用。"
    return 1
  fi

  if ! staged="$(mktemp)"; then
    red "管理面板升级失败: 无法创建临时文件。"
    return 1
  fi
  info "正在获取最新管理面板..."
  if ! fetch_manager_script "$staged"; then
    rm -f "$staged"
    red "管理面板下载失败，请检查网络连接。"
    return 1
  fi
  if ! validate_manager_script "$staged"; then
    rm -f "$staged"
    red "升级已取消: 下载的文件不是有效的 Snell 管理脚本。"
    return 1
  fi
  if [ -f "$SNELL_COMMAND_PATH" ] && cmp -s "$staged" "$SNELL_COMMAND_PATH"; then
    rm -f "$staged"
    success "当前管理面板已是最新版本。"
    return 0
  fi
  if ! install_manager_script "$staged"; then
    rm -f "$staged"
    red "管理面板安装失败，现有脚本未被修改。"
    return 1
  fi
  rm -f "$staged"
  success "管理面板已升级；退出后重新运行 snell 即可使用，v5/v6 配置与服务均保持不变。"
}

have_systemd() {
  command -v systemctl >/dev/null 2>&1
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "aarch64" ;;
    i386|i686)     echo "i386" ;;
    *) red "不支持的架构: $(uname -m)"; return 1 ;;
  esac
}

is_installed() {
  [ -x "$BIN_PATH" ] && [ -f "$CONF_PATH" ] && [ -f "$SERVICE_PATH" ]
}

has_installation_files() {
  [ -e "$BIN_PATH" ] || [ -e "$CONF_PATH" ] || [ -e "$SERVICE_PATH" ]
}

service_is_active() {
  have_systemd && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

service_is_enabled() {
  have_systemd && systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null
}

validate_port() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

validate_mode() {
  case "${1:-}" in
    default|unshaped|unsafe-raw) return 0 ;;
    *) return 1 ;;
  esac
}

validate_boolean() {
  case "${1:-}" in
    true|false) return 0 ;;
    *) return 1 ;;
  esac
}

validate_version() {
  [[ "${1:-}" =~ ^v[0-9][0-9A-Za-z._-]*$ ]]
}

validate_instance_version() {
  validate_version "${1:-}" && [[ "$1" == "${SNELL_PROTOCOL}."* ]]
}

validate_psk() {
  local value="${1:-}"
  [ "${#value}" -ge 12 ] && [ "${#value}" -le 255 ] &&
    [[ "$value" != *$'\n'* ]] && [[ "$value" != *$'\r'* ]] &&
    [[ "$value" != [[:space:]]* ]] && [[ "$value" != *[[:space:]] ]]
}

config_value() {
  local key="$1"
  [ -r "$CONF_PATH" ] || return 1
  awk -F= -v wanted="$key" '
    /^[[:space:]]*\[/ { in_server = ($0 ~ /^[[:space:]]*\[snell-server\][[:space:]]*$/); next }
    in_server {
      name = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name == wanted) {
        value = substr($0, index($0, "=") + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$CONF_PATH"
}

current_port() {
  local listen
  listen="$(config_value listen 2>/dev/null || true)"
  [ -n "$listen" ] && printf '%s\n' "${listen##*:}"
}

current_psk()  { config_value psk 2>/dev/null || true; }
current_ipv6() {
  local value listen
  value="$(config_value ipv6 2>/dev/null || true)"
  if [ -n "$value" ]; then
    echo "$value"
    return 0
  fi
  listen="$(config_value listen 2>/dev/null || true)"
  [[ "$listen" == *'['* || "$listen" == *'::'* ]] && echo "true" || echo "false"
}
current_mode() {
  local value
  value="$(config_value mode 2>/dev/null || true)"
  echo "${value:-default}"
}
current_dns() { config_value dns 2>/dev/null || true; }
current_dns_preference() { config_value dns-ip-preference 2>/dev/null || true; }
current_egress_interface() { config_value egress-interface 2>/dev/null || true; }

validate_dns() {
  local value="${1:-}"
  [ "${#value}" -le 1024 ] && [[ "$value" != *$'\n'* ]] && [[ "$value" != *$'\r'* ]]
}

validate_dns_preference() {
  case "${1:-}" in
    ''|default|prefer-ipv4|prefer-ipv6|ipv4-only|ipv6-only) return 0 ;;
    *) return 1 ;;
  esac
}

validate_egress_interface() {
  local value="${1:-}"
  [ -z "$value" ] || { [ "${#value}" -le 64 ] && [[ "$value" =~ ^[0-9A-Za-z_.:@-]+$ ]]; }
}

installed_version() {
  if [ -s "$VERSION_PATH" ]; then
    head -n 1 "$VERSION_PATH"
  elif [ -r "$SERVICE_PATH" ]; then
    sed -n 's/^Description=.* \(v[0-9][0-9A-Za-z._-]*\)$/\1/p' "$SERVICE_PATH" | head -n 1
  else
    echo "unknown"
  fi
}

legacy_has_files() {
  [ -e "$LEGACY_BIN_PATH" ] || [ -e "$LEGACY_CONF_PATH" ] || [ -e "$LEGACY_SERVICE_PATH" ]
}

legacy_installed_version() {
  local output="" version=""
  if [ -s "$LEGACY_VERSION_PATH" ]; then
    head -n 1 "$LEGACY_VERSION_PATH"
    return 0
  fi
  if [ -x "$LEGACY_BIN_PATH" ]; then
    output="$("$LEGACY_BIN_PATH" -v 2>&1 || true)"
    version="$(printf '%s\n' "$output" | sed -n 's/.*snell-server \(v[0-9][0-9A-Za-z._-]*\).*/\1/p' | head -n 1)"
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
  fi
  if [ -r "$LEGACY_SERVICE_PATH" ]; then
    sed -n 's/^Description=.* \(v[0-9][0-9A-Za-z._-]*\)$/\1/p' "$LEGACY_SERVICE_PATH" | head -n 1
  fi
}

legacy_protocol() {
  case "$(legacy_installed_version)" in
    v5.*) echo "v5" ;;
    v6.*) echo "v6" ;;
    *) return 1 ;;
  esac
}

masked_psk() {
  local psk="${1:-}"
  if [ "${#psk}" -le 8 ]; then
    printf '%s\n' '********'
  else
    printf '%s…%s\n' "${psk:0:4}" "${psk: -4}"
  fi
}

gen_psk() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    local value=""
    value="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 32 || true)"
    [ "${#value}" -eq 32 ] || { red "无法生成安全 PSK，请先安装 openssl。"; return 1; }
    echo "$value"
  fi
}

tcp_port_in_use() {
  local port="$1"
  command -v ss >/dev/null 2>&1 || return 1
  CONF_PATH="$CONF_PATH" ss -H -ltn 2>/dev/null | awk -v suffix=":${port}" '$4 ~ suffix "$" { found=1 } END { exit !found }'
}

udp_port_in_use() {
  local port="$1"
  command -v ss >/dev/null 2>&1 || return 1
  CONF_PATH="$CONF_PATH" ss -H -lun 2>/dev/null | awk -v suffix=":${port}" '$4 ~ suffix "$" { found=1 } END { exit !found }'
}

port_in_use() {
  tcp_port_in_use "$1" || udp_port_in_use "$1"
}

transport_label() {
  [ "$SNELL_PROTOCOL" = "v5" ] && echo "TCP/UDP" || echo "TCP"
}

pick_port() {
  local candidate attempts=0
  if [ -n "$SNELL_PORT" ]; then
    validate_port "$SNELL_PORT" || { red "SNELL_PORT 必须是 1-65535 的整数。"; return 1; }
    if port_in_use "$SNELL_PORT"; then
      red "端口 ${SNELL_PORT} 已被占用。"
      return 1
    fi
    echo "$SNELL_PORT"
    return 0
  fi

  while [ "$attempts" -lt 50 ]; do
    candidate=$(( RANDOM % 20001 + 20000 ))
    if ! port_in_use "$candidate"; then
      echo "$candidate"
      return 0
    fi
    attempts=$((attempts + 1))
  done
  red "未能找到可用的随机端口。"
  return 1
}

write_config() {
  local port="$1" psk="$2" ipv6="$3" mode="$4"
  local dns="${5:-}" dns_preference="${6:-}" egress_interface="${7:-}" listen temp
  validate_port "$port" || { red "无效端口: $port"; return 1; }
  validate_psk "$psk" || { red "PSK 长度应为 12-255，且首尾不能有空白。"; return 1; }
  validate_boolean "$ipv6" || { red "IPv6 选项只能是 true 或 false。"; return 1; }
  if [ "$SNELL_PROTOCOL" = "v6" ]; then
    validate_mode "$mode" || { red "无效模式: $mode"; return 1; }
  fi
  validate_dns "$dns" || { red "自定义 DNS 不能包含换行，且最长为 1024 字符。"; return 1; }
  validate_dns_preference "$dns_preference" || { red "无效 DNS IP 偏好: $dns_preference"; return 1; }
  validate_egress_interface "$egress_interface" || { red "出口网卡名称无效。"; return 1; }

  if [ "$ipv6" = "true" ] && [ "$SNELL_PROTOCOL" = "v5" ]; then
    listen="[::]:${port}"
  elif [ "$ipv6" = "true" ]; then
    listen="0.0.0.0:${port},[::]:${port}"
  else
    listen="0.0.0.0:${port}"
  fi
  mkdir -p "$CONF_DIR"
  temp="$(mktemp "${CONF_DIR}/.snell-server.conf.XXXXXX")"
  chmod 600 "$temp"
  {
    echo '[snell-server]'
    printf 'listen = %s\n' "$listen"
    printf 'psk = %s\n' "$psk"
    printf 'ipv6 = %s\n' "$ipv6"
    [ "$SNELL_PROTOCOL" = "v6" ] && printf 'mode = %s\n' "$mode"
    [ -n "$dns" ] && printf 'dns = %s\n' "$dns"
    [ -n "$dns_preference" ] && printf 'dns-ip-preference = %s\n' "$dns_preference"
    [ -n "$egress_interface" ] && printf 'egress-interface = %s\n' "$egress_interface"
  } > "$temp"
  mv -f "$temp" "$CONF_PATH"
  chown root:nogroup "$CONF_PATH"
  chmod 640 "$CONF_PATH"
}

write_service() {
  local version="$1" temp
  temp="$(mktemp "${SERVICE_PATH}.XXXXXX")"
  cat > "$temp" <<EOF
[Unit]
Description=Snell ${SNELL_PROTOCOL} Proxy Server ${version}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=${BIN_PATH} -c ${CONF_PATH}
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$temp"
  mv -f "$temp" "$SERVICE_PATH"
}

ensure_dependencies() {
  local missing=() command_name
  for command_name in wget unzip; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
  done
  command -v ss >/dev/null 2>&1 || missing+=("iproute2")
  [ "${#missing[@]}" -eq 0 ] && return 0

  command -v apt-get >/dev/null 2>&1 || {
    red "缺少依赖: ${missing[*]}，且当前系统没有 apt-get。"
    return 1
  }
  info "安装依赖: ${missing[*]}"
  apt-get update -y >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null
}

download_binary() {
  local version="$1" destination="$2" arch package url temp_dir
  validate_version "$version" || { red "版本格式无效: $version"; return 1; }
  arch="$(detect_arch)"
  package="snell-server-${version}-linux-${arch}.zip"
  url="${DOWNLOAD_BASE}/${package}"
  temp_dir="$(mktemp -d)"

  info "下载 ${url}"
  if ! wget -q --show-progress -O "${temp_dir}/${package}" "$url"; then
    rm -rf "$temp_dir"
    red "下载失败，请检查版本号和网络连接。"
    return 1
  fi
  if ! unzip -oq "${temp_dir}/${package}" -d "$temp_dir" || [ ! -f "${temp_dir}/snell-server" ]; then
    rm -rf "$temp_dir"
    red "安装包无效或缺少 snell-server。"
    return 1
  fi
  install -m 755 "${temp_dir}/snell-server" "$destination"
  rm -rf "$temp_dir"
}

public_ip() {
  local family="$1" result=""
  if command -v curl >/dev/null 2>&1; then
    result="$(curl -sS "-${family}" --max-time 4 https://api.ipify.org 2>/dev/null || true)"
  elif [ "$family" = "4" ] && command -v wget >/dev/null 2>&1; then
    result="$(wget -q -T 4 -O - https://api.ipify.org 2>/dev/null || true)"
  fi
  printf '%s\n' "$result"
}

show_existing() {
  yellow "检测到已有 Snell 文件:"
  [ -e "$BIN_PATH" ]     && echo "  二进制  $BIN_PATH"
  [ -e "$CONF_PATH" ]    && echo "  配置    $CONF_PATH"
  [ -e "$SERVICE_PATH" ] && echo "  服务    $SERVICE_PATH"
  if service_is_active; then
    echo "  状态    运行中"
  else
    echo "  状态    未运行"
  fi
}

do_install() {
  need_root
  have_systemd || { red "未检测到 systemd，无法安装服务。"; return 1; }
  if [ "$SNELL_PROTOCOL" = "v6" ]; then
    validate_mode "$SNELL_MODE" || { red "SNELL_MODE 无效: $SNELL_MODE"; return 1; }
  fi
  validate_boolean "$SNELL_IPV6" || { red "SNELL_IPV6 只能是 true 或 false。"; return 1; }
  validate_instance_version "$SNELL_VERSION" || {
    red "${SNELL_PROTOCOL} 实例只能安装 ${SNELL_PROTOCOL}.x 版本，当前值为 ${SNELL_VERSION}。"
    return 1
  }

  if has_installation_files; then
    echo
    show_existing
    echo
    local answer
    read -r -p "重装 Snell ${SNELL_PROTOCOL} 会生成新的端口和 PSK，是否继续? [y/N] " answer
    case "${answer:-N}" in
      y|Y|yes|YES) backup_config "pre-reinstall" >/dev/null || true ;;
      *) yellow "已取消。"; return 0 ;;
    esac
  fi

  local psk port staged_binary
  ensure_dependencies
  psk="$(gen_psk)"
  port="$(pick_port)"
  staged_binary="$(mktemp)"
  rm -f "$staged_binary"

  download_binary "$SNELL_VERSION" "$staged_binary"
  mkdir -p "$(dirname "$BIN_PATH")" "$(dirname "$SERVICE_PATH")"
  install -m 755 "$staged_binary" "$BIN_PATH"
  rm -f "$staged_binary"
  write_config "$port" "$psk" "$SNELL_IPV6" "$SNELL_MODE" "" "" ""
  write_service "$SNELL_VERSION"
  printf '%s\n' "$SNELL_VERSION" > "$VERSION_PATH"
  chmod 600 "$VERSION_PATH"

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  sleep 1
  echo
  if service_is_active; then
    success "Snell ${SNELL_PROTOCOL} ${SNELL_VERSION} 安装成功"
  else
    red "服务未正常启动。请运行: journalctl -u ${SERVICE_NAME} -e"
    return 1
  fi
  show_status
  echo
  show_client_config
  echo
  warn "请在云服务商安全组及本机防火墙中放行 $(transport_label) ${port}。"
}

do_uninstall() {
  need_root
  if ! has_installation_files; then
    yellow "未检测到 Snell 安装，无需卸载。"
    return 0
  fi
  info "停止并禁用服务"
  if have_systemd; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  fi
  rm -f "$SERVICE_PATH" "$BIN_PATH"
  rm -rf "$CONF_DIR"
  if [ -z "$CONF_DIR_OVERRIDE" ]; then
    rmdir "$SNELL_BASE_DIR" 2>/dev/null || true
  fi
  if have_systemd; then
    systemctl daemon-reload
    systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
  fi
  success "Snell ${SNELL_PROTOCOL} 已卸载，其配置和备份已清理。"
}

migrate_legacy() {
  local requested="${1:-}" detected="" version="" was_active=false was_enabled=false
  need_root
  have_systemd || { red "未检测到 systemd，无法迁移旧实例。"; return 1; }
  legacy_has_files || { yellow "没有检测到旧版单实例安装。"; return 0; }
  if [ ! -x "$LEGACY_BIN_PATH" ] || [ ! -f "$LEGACY_CONF_PATH" ] || [ ! -f "$LEGACY_SERVICE_PATH" ]; then
    red "旧版安装文件不完整，无法自动迁移。"
    return 1
  fi

  detected="$(legacy_protocol 2>/dev/null || true)"
  if [ -n "$requested" ]; then
    case "$requested" in v5|v6) ;; *) red "迁移目标只能是 v5 或 v6。"; return 1 ;; esac
    if [ -n "$detected" ] && [ "$requested" != "$detected" ]; then
      red "旧二进制识别为 ${detected}，不能迁移到 ${requested} 实例。"
      return 1
    fi
    detected="$requested"
  fi
  [ -n "$detected" ] || {
    red "无法识别旧实例版本，请使用 migrate v5 或 migrate v6 明确指定。"
    return 1
  }

  version="$(legacy_installed_version)"
  use_instance "$detected"
  [ -n "$version" ] || version="$SNELL_VERSION"
  validate_instance_version "$version" || {
    red "旧实例版本信息无效: ${version}"
    return 1
  }
  if has_installation_files || [ -e "$CONF_DIR" ]; then
    red "目标 ${detected} 实例已经存在，不能覆盖迁移。"
    return 1
  fi

  systemctl is-active --quiet "$LEGACY_SERVICE_NAME" 2>/dev/null && was_active=true
  systemctl is-enabled --quiet "$LEGACY_SERVICE_NAME" 2>/dev/null && was_enabled=true
  systemctl stop "$LEGACY_SERVICE_NAME" 2>/dev/null || true

  mkdir -p "$(dirname "$BIN_PATH")" "$CONF_DIR" "$(dirname "$SERVICE_PATH")"
  install -m 755 "$LEGACY_BIN_PATH" "$BIN_PATH"
  install -o root -g nogroup -m 640 "$LEGACY_CONF_PATH" "$CONF_PATH"
  printf '%s\n' "$version" > "$VERSION_PATH"
  chmod 600 "$VERSION_PATH"
  write_service "$version"
  systemctl daemon-reload
  if [ "$was_enabled" = "true" ]; then
    systemctl enable "$SERVICE_NAME"
  fi

  if [ "$was_active" = "true" ]; then
    if ! systemctl restart "$SERVICE_NAME" || ! sleep 1 || ! service_is_active; then
      systemctl disable "$SERVICE_NAME" 2>/dev/null || true
      systemctl stop "$SERVICE_NAME" 2>/dev/null || true
      rm -f "$SERVICE_PATH" "$BIN_PATH"
      rm -rf "$CONF_DIR"
      systemctl daemon-reload
      systemctl start "$LEGACY_SERVICE_NAME" 2>/dev/null || true
      red "新实例启动失败，已保留并恢复旧版单实例。"
      return 1
    fi
  fi

  if [ -d "$LEGACY_BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    cp -a "$LEGACY_BACKUP_DIR/." "$BACKUP_DIR/"
  fi
  systemctl disable "$LEGACY_SERVICE_NAME" 2>/dev/null || true
  rm -f "$LEGACY_SERVICE_PATH" "$LEGACY_BIN_PATH" "$LEGACY_CONF_PATH" "$LEGACY_VERSION_PATH"
  rm -rf "$LEGACY_BACKUP_DIR"
  systemctl daemon-reload
  systemctl reset-failed "$LEGACY_SERVICE_NAME" 2>/dev/null || true
  success "旧版单实例已迁移为 ${SERVICE_NAME}.service，端口和 PSK 保持不变。"
}

backup_config() {
  local label="${1:-manual}" timestamp destination entry index
  local -a auto_backups=()
  [ -f "$CONF_PATH" ] || { red "没有可备份的配置。"; return 1; }
  timestamp="$(date '+%Y%m%d-%H%M%S-%N')"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  destination="${BACKUP_DIR}/${timestamp}-${label}.conf"
  cp -p "$CONF_PATH" "$destination"
  chmod 600 "$destination"
  mapfile -d '' -t auto_backups < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f -name '*-auto.conf' -printf '%T@ %p\0' 2>/dev/null | sort -zrn
  )
  for ((index = 10; index < ${#auto_backups[@]}; index++)); do
    entry="${auto_backups[$index]}"
    rm -f -- "${entry#* }"
  done
  printf '%s\n' "$destination"
}

apply_config() {
  local port="$1" psk="$2" ipv6="$3" mode="$4"
  local dns dns_preference egress_interface rollback was_active=false
  if [ "$#" -ge 5 ]; then dns="$5"; else dns="$(current_dns)"; fi
  if [ "$#" -ge 6 ]; then dns_preference="$6"; else dns_preference="$(current_dns_preference)"; fi
  if [ "$#" -ge 7 ]; then egress_interface="$7"; else egress_interface="$(current_egress_interface)"; fi
  need_root
  is_installed || { red "Snell 尚未完整安装。"; return 1; }
  validate_port "$port" || { red "端口必须是 1-65535 的整数。"; return 1; }
  validate_psk "$psk" || { red "PSK 长度应为 12-255，且首尾不能有空白。"; return 1; }
  validate_boolean "$ipv6" || { red "IPv6 选项只能是 true 或 false。"; return 1; }
  if [ "$SNELL_PROTOCOL" = "v6" ]; then
    validate_mode "$mode" || { red "模式只能是 default、unshaped 或 unsafe-raw。"; return 1; }
  fi
  validate_dns "$dns" || { red "自定义 DNS 不能包含换行，且最长为 1024 字符。"; return 1; }
  validate_dns_preference "$dns_preference" || { red "DNS IP 偏好无效。"; return 1; }
  validate_egress_interface "$egress_interface" || { red "出口网卡名称无效。"; return 1; }

  rollback="$(backup_config auto)"
  service_is_active && was_active=true
  write_config "$port" "$psk" "$ipv6" "$mode" "$dns" "$dns_preference" "$egress_interface"

  if [ "$was_active" = "true" ]; then
    if systemctl restart "$SERVICE_NAME" && sleep 1 && service_is_active; then
      success "配置已保存，服务已重启。"
    else
      install -o root -g nogroup -m 640 "$rollback" "$CONF_PATH"
      systemctl restart "$SERVICE_NAME" 2>/dev/null || true
      red "新配置启动失败，已自动恢复上一份配置。"
      return 1
    fi
  else
    success "配置已保存。服务当前为停止状态，因此未自动启动。"
  fi
}

set_port() {
  local port="${1:-}" old_port
  old_port="$(current_port)"
  validate_port "$port" || { red "端口必须是 1-65535 的整数。"; return 1; }
  if [ "$port" != "$old_port" ] && port_in_use "$port"; then
    red "端口 ${port} 已被其他程序占用。"
    return 1
  fi
  apply_config "$port" "$(current_psk)" "$(current_ipv6)" "$(current_mode)"
}

set_psk() {
  local psk="${1:-}"
  [ -n "$psk" ] || psk="$(gen_psk)"
  apply_config "$(current_port)" "$psk" "$(current_ipv6)" "$(current_mode)" || return 1
  success "当前 PSK: ${psk}"
}

set_mode() {
  local mode="${1:-}"
  [ "$SNELL_PROTOCOL" = "v6" ] || { red "运行模式设置仅适用于 Snell v6。"; return 1; }
  apply_config "$(current_port)" "$(current_psk)" "$(current_ipv6)" "$mode"
}

set_ipv6() {
  local ipv6="${1:-}"
  apply_config "$(current_port)" "$(current_psk)" "$ipv6" "$(current_mode)"
}

set_dns() {
  local dns="${1:-}"
  apply_config "$(current_port)" "$(current_psk)" "$(current_ipv6)" "$(current_mode)" \
    "$dns" "$(current_dns_preference)" "$(current_egress_interface)"
}

set_dns_preference() {
  local preference="${1:-}"
  apply_config "$(current_port)" "$(current_psk)" "$(current_ipv6)" "$(current_mode)" \
    "$(current_dns)" "$preference" "$(current_egress_interface)"
}

set_egress_interface() {
  local interface="${1:-}"
  apply_config "$(current_port)" "$(current_psk)" "$(current_ipv6)" "$(current_mode)" \
    "$(current_dns)" "$(current_dns_preference)" "$interface"
}

show_status() {
  local state enabled version port psk mode ipv6 listen_state pid uptime ip4 dns dns_preference egress_interface
  local status_style enabled_style
  if ! has_installation_files; then
    yellow "Snell 尚未安装。"
    return 1
  fi

  is_installed && state="已安装" || state="安装不完整"
  if service_is_active; then
    state="运行中"
  elif [ "$state" = "已安装" ]; then
    state="已停止"
  fi
  service_is_enabled && enabled="是" || enabled="否"
  version="$(installed_version)"
  port="$(current_port)"
  psk="$(current_psk)"
  mode="$(current_mode)"
  ipv6="$(current_ipv6)"
  dns="$(current_dns)"
  dns_preference="$(current_dns_preference)"
  egress_interface="$(current_egress_interface)"
  listen_state="未监听"
  if [ -n "$port" ] && [ "$SNELL_PROTOCOL" = "v5" ]; then
    if tcp_port_in_use "$port" && udp_port_in_use "$port"; then
      listen_state="TCP/UDP ${port}"
    elif tcp_port_in_use "$port"; then
      listen_state="仅 TCP ${port}"
    elif udp_port_in_use "$port"; then
      listen_state="仅 UDP ${port}"
    fi
  elif [ -n "$port" ] && tcp_port_in_use "$port"; then
    listen_state="TCP ${port}"
  fi
  pid=""
  if service_is_active; then
    pid="$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || true)"
  fi
  uptime=""
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && command -v ps >/dev/null 2>&1; then
    uptime="$(ps -o etime= -p "$pid" 2>/dev/null | xargs || true)"
  fi
  ip4="$(public_ip 4)"
  status_style="$(state_color "$state")"
  enabled_style="$(state_color "$enabled")"

  section_title "Snell ${SNELL_PROTOCOL} 运行概览"
  detail_row "状态" "$state" "$status_style"
  detail_row "开机自启" "$enabled" "$enabled_style"
  detail_row "版本" "${version:-unknown}" "$C_MAGENTA"
  detail_row "监听" "$listen_state" "$C_YELLOW"
  [ "$SNELL_PROTOCOL" = "v6" ] && detail_row "模式" "${mode:-未知}" "$C_BLUE"
  detail_row "IPv6" "${ipv6:-未知}" "$C_CYAN"
  [ -n "$dns" ] && detail_row "自定义 DNS" "$dns"
  [ -n "$dns_preference" ] && detail_row "DNS IP 偏好" "$dns_preference"
  [ -n "$egress_interface" ] && detail_row "出口网卡" "$egress_interface"
  detail_row "PSK" "$(masked_psk "$psk")" "$C_GRAY"
  [ -n "$ip4" ] && detail_row "公网 IPv4" "$ip4" "$C_CYAN"
  [ -n "$pid" ] && detail_row "进程" "PID ${pid}${uptime:+ · 已运行 ${uptime}}" "$C_GREEN"
}

client_address() {
  local requested="${1:-}" ip4
  if [ -n "$requested" ]; then
    echo "$requested"
    return 0
  fi
  ip4="$(public_ip 4)"
  [ -n "$ip4" ] && echo "$ip4" || echo "你的服务器IP"
}

show_client_config() {
  local address="${1:-}" port psk mode
  is_installed || { red "Snell 尚未完整安装。"; return 1; }
  address="$(client_address "$address")"
  port="$(current_port)"
  psk="$(current_psk)"
  mode="$(current_mode)"

  printf '%b\n' "${C_CYAN}${C_BOLD}Surge${C_RESET}"
  if [ "$SNELL_PROTOCOL" = "v6" ]; then
    printf 'Snell-v6 = snell, %s, %s, psk=%s, version=6, mode=%s, reuse=true, tfo=true\n' \
      "$address" "$port" "$psk" "$mode"
  else
    printf 'Snell-v5 = snell, %s, %s, psk=%s, version=5, reuse=true, tfo=true\n' \
      "$address" "$port" "$psk"
  fi
  echo
  printf '%b\n' "${C_MAGENTA}${C_BOLD}mihomo / Clash Meta${C_RESET}"
  cat <<EOF
- name: Snell-${SNELL_PROTOCOL}
  type: snell
  server: ${address}
  port: ${port}
  psk: ${psk}
  version: ${PROTOCOL_VERSION}
  udp: true
EOF
}

service_action() {
  local action="$1" action_label
  need_root
  is_installed || { red "Snell 尚未完整安装。"; return 1; }
  case "$action" in
    start|restart)
      if ! systemctl "$action" "$SERVICE_NAME"; then
        red "服务操作失败，请查看日志。"
        return 1
      fi
      sleep 1
      [ "$action" = "start" ] && action_label="启动" || action_label="重启"
      if service_is_active; then
        success "服务已${action_label}。"
      else
        red "服务操作失败，请查看日志。"
        return 1
      fi
      ;;
    stop)
      systemctl stop "$SERVICE_NAME"
      success "服务已停止。"
      ;;
    enable)
      systemctl enable "$SERVICE_NAME"
      success "已开启开机自启。"
      ;;
    disable)
      systemctl disable "$SERVICE_NAME"
      success "已关闭开机自启。"
      ;;
    *) red "不支持的服务操作: $action"; return 1 ;;
  esac
}

show_logs() {
  local lines="${1:-100}"
  [[ "$lines" =~ ^[1-9][0-9]*$ ]] || { red "日志行数必须是正整数。"; return 1; }
  command -v journalctl >/dev/null 2>&1 || { red "系统没有 journalctl。"; return 1; }
  journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
}

follow_logs() {
  command -v journalctl >/dev/null 2>&1 || { red "系统没有 journalctl。"; return 1; }
  info "正在跟踪日志，按 Ctrl+C 返回。"
  journalctl -u "$SERVICE_NAME" -n 50 -f
}

diagnose() {
  local failures=0 port psk ipv6 mode dns dns_preference egress_interface permissions
  echo "Snell ${SNELL_PROTOCOL} 诊断结果"
  if [ -x "$BIN_PATH" ]; then success "服务端程序存在且可执行"; else red "[fail] 缺少服务端程序: $BIN_PATH"; failures=$((failures + 1)); fi
  if [ -r "$CONF_PATH" ]; then success "配置文件可读取"; else red "[fail] 缺少配置文件: $CONF_PATH"; failures=$((failures + 1)); fi
  if [ -r "$SERVICE_PATH" ]; then success "systemd 服务文件存在"; else red "[fail] 缺少服务文件: $SERVICE_PATH"; failures=$((failures + 1)); fi

  port="$(current_port)"; psk="$(current_psk)"; ipv6="$(current_ipv6)"; mode="$(current_mode)"
  dns="$(current_dns)"; dns_preference="$(current_dns_preference)"; egress_interface="$(current_egress_interface)"
  if validate_port "$port"; then success "端口配置有效: ${port}"; else red "[fail] 端口配置无效"; failures=$((failures + 1)); fi
  if validate_psk "$psk"; then success "PSK 格式有效"; else red "[fail] PSK 缺失或格式无效"; failures=$((failures + 1)); fi
  if validate_boolean "$ipv6"; then success "IPv6 配置有效: ${ipv6}"; else red "[fail] IPv6 配置无效"; failures=$((failures + 1)); fi
  if [ "$SNELL_PROTOCOL" = "v6" ]; then
    if validate_mode "$mode"; then success "模式配置有效: ${mode}"; else red "[fail] 模式配置无效"; failures=$((failures + 1)); fi
  fi
  if validate_dns "$dns"; then success "自定义 DNS 配置格式有效"; else red "[fail] 自定义 DNS 配置无效"; failures=$((failures + 1)); fi
  if validate_dns_preference "$dns_preference"; then success "DNS IP 偏好有效: ${dns_preference:-默认}"; else red "[fail] DNS IP 偏好无效"; failures=$((failures + 1)); fi
  if validate_egress_interface "$egress_interface"; then success "出口网卡配置格式有效"; else red "[fail] 出口网卡配置无效"; failures=$((failures + 1)); fi

  if service_is_active; then success "服务正在运行"; else red "[fail] 服务未运行"; failures=$((failures + 1)); fi
  if [ "$SNELL_PROTOCOL" = "v5" ]; then
    if [ -n "$port" ] && tcp_port_in_use "$port"; then success "TCP ${port} 正在监听"; else red "[fail] TCP ${port:-未知} 没有监听"; failures=$((failures + 1)); fi
    if [ -n "$port" ] && udp_port_in_use "$port"; then success "UDP ${port} 正在监听（v5 QUIC）"; else red "[fail] UDP ${port:-未知} 没有监听"; failures=$((failures + 1)); fi
  elif [ -n "$port" ] && tcp_port_in_use "$port"; then
    success "TCP ${port} 正在监听"
  else
    red "[fail] TCP ${port:-未知} 没有监听"
    failures=$((failures + 1))
  fi
  if service_is_enabled; then success "已开启开机自启"; else warn "未开启开机自启"; fi
  if [ "$SNELL_PROTOCOL" = "v5" ] && [ "$ipv6" = "true" ] &&
     [ -r /proc/sys/net/ipv6/bindv6only ] && [ "$(cat /proc/sys/net/ipv6/bindv6only)" = "1" ]; then
    warn "系统 bindv6only=1，v5 的 [::] 监听不会接收 IPv4 连接。"
  fi

  if [ -e "$CONF_PATH" ]; then
    permissions="$(stat -c '%a' "$CONF_PATH" 2>/dev/null || true)"
    if [ "$permissions" = "640" ]; then success "配置文件权限安全: 640"; else warn "配置权限为 ${permissions:-未知}，建议使用 640"; fi
  fi
  echo
  if [ "$failures" -eq 0 ]; then
    success "未发现影响运行的问题。"
  else
    red "发现 ${failures} 个需要处理的问题。"
    if command -v journalctl >/dev/null 2>&1; then
      echo
      echo "最近的服务错误:"
      journalctl -u "$SERVICE_NAME" -p warning -n 5 --no-pager 2>/dev/null || true
    fi
    return 1
  fi
}

update_server() {
  local target="${1:-$SNELL_VERSION}" old_version staged_binary old_binary was_active=false
  need_root
  is_installed || { red "Snell 尚未完整安装。"; return 1; }
  validate_instance_version "$target" || {
    red "${SNELL_PROTOCOL} 实例只能更新到 ${SNELL_PROTOCOL}.x 版本。"
    return 1
  }
  ensure_dependencies
  old_version="$(installed_version)"
  staged_binary="$(mktemp)"; rm -f "$staged_binary"
  old_binary="$(mktemp)"; rm -f "$old_binary"
  download_binary "$target" "$staged_binary"
  cp -p "$BIN_PATH" "$old_binary"
  service_is_active && was_active=true

  install -m 755 "$staged_binary" "$BIN_PATH"
  rm -f "$staged_binary"
  write_service "$target"
  printf '%s\n' "$target" > "$VERSION_PATH"
  systemctl daemon-reload

  if [ "$was_active" = "true" ]; then
    if systemctl restart "$SERVICE_NAME" && sleep 1 && service_is_active; then
      rm -f "$old_binary"
      success "Snell 已从 ${old_version} 更新到 ${target}。"
    else
      install -m 755 "$old_binary" "$BIN_PATH"
      rm -f "$old_binary"
      write_service "$old_version"
      printf '%s\n' "$old_version" > "$VERSION_PATH"
      systemctl daemon-reload
      systemctl restart "$SERVICE_NAME" 2>/dev/null || true
      red "新版本启动失败，已恢复 ${old_version}。"
      return 1
    fi
  else
    rm -f "$old_binary"
    success "服务端已更新到 ${target}；服务仍保持停止。"
  fi
}

restore_backup() {
  local source="${1:-}" port psk ipv6 mode dns dns_preference egress_interface
  need_root
  if [ -z "$source" ] || [ ! -f "$source" ]; then
    red "备份文件不存在: ${source:-未指定}"
    return 1
  fi
  port="$(CONF_PATH="$source" current_port)"
  psk="$(CONF_PATH="$source" current_psk)"
  ipv6="$(CONF_PATH="$source" current_ipv6)"
  mode="$(CONF_PATH="$source" current_mode)"
  dns="$(CONF_PATH="$source" current_dns)"
  dns_preference="$(CONF_PATH="$source" current_dns_preference)"
  egress_interface="$(CONF_PATH="$source" current_egress_interface)"
  if ! validate_port "$port" || ! validate_psk "$psk" ||
     ! validate_boolean "$ipv6" ||
     ! validate_dns "$dns" || ! validate_dns_preference "$dns_preference" ||
     ! validate_egress_interface "$egress_interface"; then
    red "备份文件内容无效，已拒绝恢复。"
    return 1
  fi
  if [ "$SNELL_PROTOCOL" = "v6" ] && ! validate_mode "$mode"; then
    red "备份中的 v6 运行模式无效，已拒绝恢复。"
    return 1
  fi
  apply_config "$port" "$psk" "$ipv6" "$mode" "$dns" "$dns_preference" "$egress_interface"
}

pause_screen() {
  [ -t 0 ] || return 0
  echo
  read -r -p "按 Enter 返回面板..." _
}

clear_screen() {
  if [ -t 1 ] && command -v clear >/dev/null 2>&1; then
    clear
  fi
}

panel_header() {
  local state="未安装" version="-" port="-" status_style
  if is_installed; then
    service_is_active && state="运行中" || state="已停止"
    version="$(installed_version)"
    port="$(current_port)"
  elif has_installation_files; then
    state="安装不完整"
  fi
  status_style="$(state_color "$state")"
  printf '%b\n' "${C_CYAN}${C_BOLD}╭────────────────────────────────────────────╮${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}│${C_RESET}          ${C_WHITE}${C_BOLD}Snell ${SNELL_PROTOCOL} 实例管理控制台${C_RESET}           ${C_CYAN}${C_BOLD}│${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}╰────────────────────────────────────────────╯${C_RESET}"
  printf '  %b状态%b  %b%-10s%b  %b版本%b  %b%-12s%b  %b端口%b  %b%s%b\n\n' \
    "$C_GRAY" "$C_RESET" "$status_style" "$state" "$C_RESET" \
    "$C_GRAY" "$C_RESET" "$C_MAGENTA" "$version" "$C_RESET" \
    "$C_GRAY" "$C_RESET" "$C_YELLOW" "$port" "$C_RESET"
}

configuration_menu() {
  local choice value current
  while true; do
    clear_screen
    panel_header
    section_title "配置管理"
    menu_option 1 "修改监听端口"
    menu_option 2 "重新生成 PSK"
    menu_option 3 "设置自定义 PSK"
    if [ "$SNELL_PROTOCOL" = "v6" ]; then
      menu_option 4 "切换运行模式"
    else
      menu_option 4 "运行模式（仅 v6）" back
    fi
    menu_option 5 "开启 / 关闭 IPv6"
    menu_option 6 "设置自定义 DNS"
    menu_option 7 "设置 DNS IP 偏好"
    menu_option 8 "绑定出口网卡"
    menu_option 0 "返回" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        current="$(current_port)"
        read -r -p "新端口 [当前 ${current}]: " value
        if [ -n "$value" ]; then set_port "$value" || true; else yellow "未修改。"; fi
        pause_screen
        ;;
      2)
        read -r -p "这会使旧客户端配置失效，确认重新生成? [y/N] " value
        if [[ "$value" =~ ^[yY]$ ]]; then set_psk || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      3)
        read -r -s -p "输入新 PSK (12-255 字符): " value; echo
        if [ -n "$value" ]; then set_psk "$value" || true; else yellow "未修改。"; fi
        pause_screen
        ;;
      4)
        if [ "$SNELL_PROTOCOL" = "v5" ]; then
          yellow "Snell v5 没有可管理的 mode 参数。"
        else
          menu_option 1 "default    兼容性优先"
          menu_option 2 "unshaped   不使用流量整形"
          menu_option 3 "unsafe-raw 原始模式"
          read -r -p "请选择 [当前 $(current_mode)]: " value
          case "$value" in
            1) set_mode default || true ;;
            2) set_mode unshaped || true ;;
            3) set_mode unsafe-raw || true ;;
            *) yellow "未修改。" ;;
          esac
        fi
        pause_screen
        ;;
      5)
        current="$(current_ipv6)"
        [ "$current" = "true" ] && value="false" || value="true"
        read -r -p "将 IPv6 从 ${current} 切换为 ${value}? [y/N] " choice
        if [[ "$choice" =~ ^[yY]$ ]]; then set_ipv6 "$value" || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      6)
        echo "当前值: $(current_dns | sed 's/^$/系统默认/')"
        read -r -p "DNS 地址，多个用逗号分隔（留空清除）: " value
        set_dns "$value" || true
        pause_screen
        ;;
      7)
        menu_option 1 "default"
        menu_option 2 "prefer-ipv4"
        menu_option 3 "prefer-ipv6"
        menu_option 4 "ipv4-only"
        menu_option 5 "ipv6-only"
        menu_option 6 "清除显式设置" back
        read -r -p "请选择 [当前 $(current_dns_preference | sed 's/^$/default/')]: " value
        case "$value" in
          1) set_dns_preference default || true ;;
          2) set_dns_preference prefer-ipv4 || true ;;
          3) set_dns_preference prefer-ipv6 || true ;;
          4) set_dns_preference ipv4-only || true ;;
          5) set_dns_preference ipv6-only || true ;;
          6) set_dns_preference "" || true ;;
          *) yellow "未修改。" ;;
        esac
        pause_screen
        ;;
      8)
        echo "当前值: $(current_egress_interface | sed 's/^$/未绑定/')"
        read -r -p "出口网卡名称（留空清除）: " value
        set_egress_interface "$value" || true
        pause_screen
        ;;
      0) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

service_menu() {
  local choice
  while true; do
    clear_screen
    panel_header
    section_title "服务控制"
    menu_option 1 "启动"
    menu_option 2 "停止"
    menu_option 3 "重启"
    menu_option 4 "开启开机自启"
    menu_option 5 "关闭开机自启"
    menu_option 0 "返回" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) service_action start || true; pause_screen ;;
      2) service_action stop || true; pause_screen ;;
      3) service_action restart || true; pause_screen ;;
      4) service_action enable || true; pause_screen ;;
      5) service_action disable || true; pause_screen ;;
      0) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

backup_menu() {
  local choice backup answer
  local -a backups=()
  while true; do
    clear_screen
    panel_header
    section_title "备份与恢复"
    menu_option 1 "创建配置备份"
    menu_option 2 "恢复配置备份"
    menu_option 0 "返回" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        backup="$(backup_config manual)" && success "备份已保存: ${backup}"
        pause_screen
        ;;
      2)
        backups=()
        if [ -d "$BACKUP_DIR" ]; then
          while IFS= read -r backup; do backups+=("$backup"); done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.conf' -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
        fi
        if [ "${#backups[@]}" -eq 0 ]; then
          yellow "没有可用备份。"; pause_screen; continue
        fi
        echo
        for choice in "${!backups[@]}"; do menu_option "$((choice + 1))" "$(basename "${backups[$choice]}")"; done
        menu_option 0 "取消" back
        read -r -p "选择备份: " choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#backups[@]}" ]; then
          backup="${backups[$((choice - 1))]}"
          read -r -p "确认恢复 $(basename "$backup")? [y/N] " answer
          if [[ "$answer" =~ ^[yY]$ ]]; then restore_backup "$backup" || true; else yellow "已取消。"; fi
        else
          yellow "已取消。"
        fi
        pause_screen
        ;;
      0) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

instance_menu() {
  local choice answer version
  need_root
  [ -t 0 ] || { red "交互式面板需要在终端中运行。"; return 1; }
  while true; do
    clear_screen
    panel_header
    section_title "实例操作"
    menu_option 1 "安装 / 重装 Snell ${SNELL_PROTOCOL}"
    menu_option 2 "查看运行概览"
    menu_option 3 "配置管理"
    menu_option 4 "生成客户端配置"
    menu_option 5 "服务控制"
    menu_option 6 "更新服务端版本" accent
    menu_option 7 "查看最近日志"
    menu_option 8 "实时跟踪日志"
    menu_option 9 "一键诊断"
    menu_option 10 "备份与恢复"
    menu_option 11 "卸载 Snell" danger
    menu_option 0 "返回版本选择" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) do_install || true; pause_screen ;;
      2) clear_screen; show_status || true; pause_screen ;;
      3) if is_installed; then configuration_menu; else yellow "请先完成安装。"; pause_screen; fi ;;
      4) clear_screen; show_client_config || true; pause_screen ;;
      5) if is_installed; then service_menu; else yellow "请先完成安装。"; pause_screen; fi ;;
      6)
        if is_installed; then
          read -r -p "目标版本 [${SNELL_VERSION}]: " version
          version="${version:-$SNELL_VERSION}"
          read -r -p "确认更新到 ${version}? [y/N] " answer
          if [[ "$answer" =~ ^[yY]$ ]]; then update_server "$version" || true; else yellow "已取消。"; fi
        else
          yellow "请先完成安装。"
        fi
        pause_screen
        ;;
      7) clear_screen; show_logs 100 || true; pause_screen ;;
      8) clear_screen; follow_logs || true; pause_screen ;;
      9) clear_screen; diagnose || true; pause_screen ;;
      10) if is_installed; then backup_menu; else yellow "请先完成安装。"; pause_screen; fi ;;
      11)
        read -r -p "这会删除程序、配置和备份，确认卸载? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then do_uninstall; else yellow "已取消。"; fi
        pause_screen
        ;;
      0) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

instance_summary_row() {
  local protocol="$1" state="未安装" version="-" port="-" transport="-" status_style
  use_instance "$protocol"
  if is_installed; then
    service_is_active && state="运行中" || state="已停止"
    version="$(installed_version)"
    port="$(current_port)"
    transport="$(transport_label)"
  elif has_installation_files; then
    state="安装不完整"
  fi
  status_style="$(state_color "$state")"
  printf '  %b%-4s%b %b%-10s%b %b%-12s%b %-9s %b%s%b\n' \
    "${C_CYAN}${C_BOLD}" "$protocol" "$C_RESET" \
    "$status_style" "$state" "$C_RESET" \
    "$C_MAGENTA" "$version" "$C_RESET" "$transport" \
    "$C_YELLOW" "$port" "$C_RESET"
}

show_all_status() {
  local selected="$SNELL_PROTOCOL"
  printf '%b\n' "${C_BOLD}${C_WHITE}Snell 双实例概览${C_RESET}"
  printf '%b  %-4s %-10s %-12s %-9s %s%b\n' "$C_GRAY" "实例" "状态" "版本" "传输" "端口" "$C_RESET"
  instance_summary_row v5
  instance_summary_row v6
  use_instance "$selected"
}

multi_panel_header() {
  printf '%b\n' "${C_CYAN}${C_BOLD}╭────────────────────────────────────────────╮${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}│${C_RESET}          ${C_WHITE}${C_BOLD}Snell v5 / v6 管理控制台${C_RESET}          ${C_CYAN}${C_BOLD}│${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}╰────────────────────────────────────────────╯${C_RESET}"
  show_all_status
  if legacy_has_files; then
    printf '  %b旧实例%b  检测到 snell.service (%s)，可从菜单迁移\n' "$C_YELLOW" "$C_RESET" "$(legacy_installed_version | sed 's/^$/版本未知/')"
  fi
  echo
}

instance_selector_menu() {
  local choice
  while true; do
    clear_screen
    multi_panel_header
    section_title "选择要管理的实例"
    menu_option 1 "Snell v5"
    menu_option 2 "Snell v6"
    menu_option 0 "返回主菜单" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) use_instance v5; instance_menu ;;
      2) use_instance v6; instance_menu ;;
      0) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

manager_settings_menu() {
  local choice answer command_state="未注册" command_style
  while true; do
    clear_screen
    multi_panel_header
    if is_snell_manager_script "$SNELL_COMMAND_PATH"; then
      command_state="已注册"
    else
      command_state="未注册"
    fi
    command_style="$(state_color "$command_state")"
    section_title "面板设置 / 升级"
    printf '  %b短命令%b  %b%s%b\n' "$C_GRAY" "$C_RESET" "$command_style" "$SNELL_COMMAND_PATH" "$C_RESET"
    printf '  %b状态%b    %b%s%b\n\n' "$C_GRAY" "$C_RESET" "$command_style" "$command_state" "$C_RESET"
    menu_option 1 "注册 / 修复 snell 短命令"
    menu_option 2 "检查并升级管理面板" accent
    menu_option 0 "返回主菜单" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) register_short_command || true; pause_screen ;;
      2)
        read -r -p "确认从官方仓库检查并升级管理面板? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then update_manager || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      0) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

menu() {
  local choice detected answer
  need_root
  [ -t 0 ] || { red "交互式面板需要在终端中运行。"; return 1; }
  if ! register_short_command true; then
    echo
    warn "管理面板仍可继续使用；请处理上面的短命令冲突后运行 register-command。"
    pause_screen
  fi
  while true; do
    clear_screen
    multi_panel_header
    section_title "主菜单"
    menu_option 1 "管理 Snell"
    menu_option 2 "查看双实例详细状态"
    menu_option 3 "迁移旧版单实例"
    menu_option 4 "面板设置 / 升级" accent
    menu_option 0 "退出" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) instance_selector_menu ;;
      2)
        clear_screen
        use_instance v5; show_status || true
        echo
        use_instance v6; show_status || true
        pause_screen
        ;;
      3)
        if ! legacy_has_files; then
          yellow "没有检测到旧版单实例。"
          pause_screen
          continue
        fi
        detected="$(legacy_protocol 2>/dev/null || true)"
        if [ -z "$detected" ]; then
          read -r -p "无法自动识别版本，请输入 v5 或 v6: " detected
        fi
        read -r -p "将旧实例迁移为 ${detected:-未知} 独立实例? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then migrate_legacy "$detected" || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      4) manager_settings_menu ;;
      0) echo "已退出。"; return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

usage() {
  cat <<'EOF'
Snell v5 / v6 多实例安装与配置管理

用法:
  snell [v5|v6] [命令] [参数]

命令:
  menu                       打开统一交互面板（默认）
  manage                     打开所选版本的实例面板
  status-all                 查看 v5 与 v6 概览
  register-command           注册 / 更新 snell 短命令
  self-update                检查并升级管理面板
  migrate [v5|v6]            将旧 snell.service 迁移为独立实例
  install                    安装或重装所选实例
  uninstall                  卸载并清理所选实例
  status                     查看运行概览
  client [服务器地址]        输出 Surge 与 mihomo 客户端配置
  set-port <端口>            修改监听端口
  set-psk [PSK]              设置 PSK；省略参数时自动生成
  set-mode <模式>            v6: default / unshaped / unsafe-raw
  set-ipv6 <true|false>      开启或关闭 IPv6 监听
  set-dns [地址列表]          设置自定义 DNS；省略时清除
  set-dns-preference [偏好]  设置 DNS IP 偏好；省略时清除
  set-egress [网卡]          绑定出口网卡；省略时清除
  start|stop|restart         控制 Snell 服务
  enable|disable             控制开机自启
  logs [行数]                查看最近日志（默认 100 行）
  logs-follow                实时跟踪日志
  diagnose                   检查安装、配置、服务与端口
  backup                     创建配置备份
  restore <备份文件>         恢复指定配置备份
  update [版本]              更新服务端（默认使用脚本内版本）
  help                       显示帮助

可用环境变量:
  SNELL_PROTOCOL, SNELL_VERSION, SNELL_V5_VERSION, SNELL_V6_VERSION,
  SNELL_PORT, SNELL_MODE, SNELL_IPV6, DOWNLOAD_BASE, SNELL_COMMAND_PATH,
  SNELL_MANAGER_URL, NO_COLOR

示例:
  snell v5 install
  snell v6 install
  snell status-all
  snell self-update
  snell migrate
  snell v5 client snell.example.com
EOF
}

if [ "${1:-}" = "v5" ] || [ "${1:-}" = "v6" ]; then
  use_instance "$1"
  shift
fi

case "${1:-menu}" in
  install)      do_install ;;
  uninstall)    do_uninstall ;;
  status)       show_status ;;
  client|config) show_client_config "${2:-}" ;;
  set-port)     set_port "${2:-}" ;;
  set-psk)      set_psk "${2:-}" ;;
  set-mode)     set_mode "${2:-}" ;;
  set-ipv6)     set_ipv6 "${2:-}" ;;
  set-dns)      set_dns "${2:-}" ;;
  set-dns-preference) set_dns_preference "${2:-}" ;;
  set-egress)   set_egress_interface "${2:-}" ;;
  start|stop|restart|enable|disable) service_action "$1" ;;
  logs)         show_logs "${2:-100}" ;;
  logs-follow)  follow_logs ;;
  diagnose)     diagnose ;;
  backup)       backup_config manual ;;
  restore)      restore_backup "${2:-}" ;;
  update)       update_server "${2:-$SNELL_VERSION}" ;;
  status-all)   show_all_status ;;
  register-command) register_short_command ;;
  self-update)  update_manager ;;
  migrate)      migrate_legacy "${2:-}" ;;
  manage)       instance_menu ;;
  menu)         menu ;;
  help|-h|--help) usage ;;
  *) red "未知命令: $1"; echo; usage; exit 1 ;;
esac
