#!/usr/bin/env bash
#
# 多核心代理配置管理面板 (Debian/Ubuntu, root)
# Snell v5 / v6 多实例配置管理面板（保留此标记用于旧版自更新校验）
#
# 常用命令:
#   snell                          打开交互式管理面板
#   snell v6 install               安装 / 重装 v6
#   snell v5 status                查看 v5 运行概览
#   snell v6 client [地址]         输出 v6 客户端配置
#   snell xray install             安装最新 Xray 核心
#   snell xray status              查看 Xray 核心状态
#   snell self-update              升级管理面板
#   snell help                     查看全部命令
#
set -euo pipefail

# ---------------- 可自定义 ----------------
SNELL_V5_VERSION="${SNELL_V5_VERSION:-v5.0.1}"
SNELL_V6_VERSION="${SNELL_V6_VERSION:-v6.0.0rc}"
SNELL_PROTOCOL="${SNELL_PROTOCOL:-v6}"         # v5 / v6
SNELL_VERSION_OVERRIDE="${SNELL_VERSION:-}"
SNELL_PORT="${SNELL_PORT:-}"                  # 非交互安装时留空则随机选择 20000-40000
SNELL_MODE="${SNELL_MODE:-default}"           # default / unshaped / unsafe-raw
SNELL_IPV6_OVERRIDE="${SNELL_IPV6:-}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://dl.nssurge.com/snell}"
SNELL_MANAGER_URL="${SNELL_MANAGER_URL:-https://raw.githubusercontent.com/mikuuu3981/snell-click/main/snell.sh}"
XRAY_VERSION="${XRAY_VERSION:-}"
XRAY_RELEASE_API="${XRAY_RELEASE_API:-https://api.github.com/repos/XTLS/Xray-core/releases/latest}"
XRAY_DOWNLOAD_BASE="${XRAY_DOWNLOAD_BASE:-https://github.com/XTLS/Xray-core/releases/download}"
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
XRAY_BIN_PATH="${XRAY_BIN_PATH:-${BIN_DIR}/xray}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
XRAY_CONFIG_PATH="${XRAY_CONFIG_PATH:-${XRAY_CONFIG_DIR}/config.json}"
XRAY_ASSET_DIR="${XRAY_ASSET_DIR:-/usr/local/share/xray}"
XRAY_LOG_DIR="${XRAY_LOG_DIR:-/var/log/xray}"
XRAY_SERVICE_PATH="${XRAY_SERVICE_PATH:-${SYSTEMD_DIR}/xray.service}"
XRAY_SERVICE_NAME="${XRAY_SERVICE_NAME:-xray}"
XRAY_BACKUP_DIR="${XRAY_BACKUP_DIR:-${XRAY_CONFIG_DIR}/backups}"
XRAY_MANAGED_TAG_PREFIX="snell-managed-vless-reality-"

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
    运行中|已安装|已注册|有效|是) printf '%s' "$C_GREEN" ;;
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
  success "管理面板已升级；退出后重新运行 snell 即可使用，所有核心配置与服务均保持不变。"
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

xray_detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "64" ;;
    aarch64|arm64) echo "arm64-v8a" ;;
    i386|i686)     echo "32" ;;
    *) red "Xray 不支持当前架构: $(uname -m)" >&2; return 1 ;;
  esac
}

validate_xray_version() {
  [[ "${1:-}" =~ ^v[0-9][0-9A-Za-z._-]*$ ]]
}

xray_core_installed() {
  [ -x "$XRAY_BIN_PATH" ]
}

xray_is_installed() {
  xray_core_installed && [ -f "$XRAY_CONFIG_PATH" ] && [ -f "$XRAY_SERVICE_PATH" ]
}

xray_has_files() {
  [ -e "$XRAY_BIN_PATH" ] || [ -e "$XRAY_CONFIG_PATH" ] || [ -e "$XRAY_SERVICE_PATH" ] ||
    [ -e "${XRAY_ASSET_DIR}/geoip.dat" ] || [ -e "${XRAY_ASSET_DIR}/geosite.dat" ]
}

xray_has_core_files() {
  [ -e "$XRAY_BIN_PATH" ] || [ -e "$XRAY_SERVICE_PATH" ] ||
    [ -e "${XRAY_ASSET_DIR}/geoip.dat" ] || [ -e "${XRAY_ASSET_DIR}/geosite.dat" ]
}

xray_service_is_active() {
  [ -f "$XRAY_SERVICE_PATH" ] && have_systemd &&
    systemctl is-active --quiet "$XRAY_SERVICE_NAME" 2>/dev/null
}

xray_service_is_enabled() {
  [ -f "$XRAY_SERVICE_PATH" ] && have_systemd &&
    systemctl is-enabled --quiet "$XRAY_SERVICE_NAME" 2>/dev/null
}

xray_installed_version() {
  local output version
  xray_core_installed || { echo "unknown"; return 0; }
  output="$("$XRAY_BIN_PATH" version 2>&1 || true)"
  version="$(printf '%s\n' "$output" | awk '/^Xray[[:space:]]+[0-9]/ { print $2; exit }')"
  [ -n "$version" ] && printf 'v%s\n' "${version#v}" || echo "unknown"
}

fetch_xray_release_metadata() {
  local source="$XRAY_RELEASE_API" local_source
  if [ -f "$source" ]; then
    cat "$source"
  elif [[ "$source" == file://* ]]; then
    local_source="${source#file://}"
    [ -f "$local_source" ] || return 1
    cat "$local_source"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 20 "$source"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 20 -O - "$source"
  else
    return 1
  fi
}

xray_latest_version() {
  local metadata version
  if ! metadata="$(fetch_xray_release_metadata)"; then
    red "无法获取 Xray 最新版本，请检查 GitHub 网络连接。" >&2
    return 1
  fi
  version="$(printf '%s\n' "$metadata" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  validate_xray_version "$version" || {
    red "Xray 发布接口返回了无效版本。" >&2
    return 1
  }
  printf '%s\n' "$version"
}

resolve_xray_version() {
  local requested="${1:-${XRAY_VERSION:-}}"
  if [ -z "$requested" ]; then
    xray_latest_version
    return
  fi
  validate_xray_version "$requested" || {
    red "Xray 版本格式无效: ${requested}" >&2
    return 1
  }
  printf '%s\n' "$requested"
}

xray_ensure_dependencies() {
  local missing=()
  command -v unzip >/dev/null 2>&1 || missing+=("unzip")
  command -v sha256sum >/dev/null 2>&1 || missing+=("coreutils")
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  command -v ss >/dev/null 2>&1 || missing+=("iproute2")
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing+=("curl")
  fi
  [ "${#missing[@]}" -eq 0 ] && return 0
  command -v apt-get >/dev/null 2>&1 || {
    red "缺少 Xray 安装依赖: ${missing[*]}，且当前系统没有 apt-get。"
    return 1
  }
  info "安装 Xray 依赖: ${missing[*]}"
  if ! apt-get update -y >/dev/null ||
     ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null; then
    red "Xray 安装依赖失败。"
    return 1
  fi
}

download_url_to_file() {
  local url="$1" destination="$2" local_source
  if [ -f "$url" ]; then
    cp "$url" "$destination"
  elif [[ "$url" == file://* ]]; then
    local_source="${url#file://}"
    [ -f "$local_source" ] && cp "$local_source" "$destination"
  elif command -v curl >/dev/null 2>&1; then
    curl -fL --retry 2 --connect-timeout 10 "$url" -o "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$destination" "$url"
  else
    return 1
  fi
}

download_xray_package() {
  local version="$1" destination="$2" arch package url archive digest_file expected actual
  validate_xray_version "$version" || { red "Xray 版本格式无效: $version"; return 1; }
  if ! arch="$(xray_detect_arch)"; then return 1; fi
  package="Xray-linux-${arch}.zip"
  url="${XRAY_DOWNLOAD_BASE}/${version}/${package}"
  archive="${destination}/${package}"
  digest_file="${archive}.dgst"
  info "下载 ${url}"
  if ! download_url_to_file "$url" "$archive"; then
    red "Xray 下载失败，请检查版本号和网络连接。"
    return 1
  fi
  if ! download_url_to_file "${url}.dgst" "$digest_file"; then
    red "无法下载 Xray SHA-256 校验摘要，已拒绝安装。"
    return 1
  fi
  expected="$(sed -n 's/^SHA2-256=[[:space:]]*//p' "$digest_file" | head -n 1)"
  actual="$(sha256sum "$archive" | awk '{ print $1 }')"
  if ! [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || [ "${expected,,}" != "${actual,,}" ]; then
    red "Xray 安装包 SHA-256 校验失败。"
    return 1
  fi
  if ! unzip -oq "$archive" -d "$destination" || [ ! -f "${destination}/xray" ]; then
    red "Xray 安装包无效或缺少核心文件。"
    return 1
  fi
  chmod 755 "${destination}/xray"
}

xray_config_is_valid_with() {
  local binary="$1" config="$2"
  [ -x "$binary" ] && [ -r "$config" ] &&
    "$binary" run -test -config "$config" >/dev/null 2>&1
}

xray_config_is_valid() {
  xray_config_is_valid_with "$XRAY_BIN_PATH" "$XRAY_CONFIG_PATH"
}

validate_xray_sni() {
  local value="${1,,}"
  [ "${#value}" -le 253 ] &&
    [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}

validate_xray_user_name() {
  [ -n "${1:-}" ] && [ "${#1}" -le 64 ] && [[ "$1" =~ ^[0-9A-Za-z._@-]+$ ]]
}

warn_xray_reality_choices() {
  local sni="${1,,}" port="$2"
  [ "$port" = "443" ] || warn "官方 Xray 提示：REALITY 使用非 443 端口会增加服务器 IP 被封锁的风险。"
  case "$sni" in
    *.cn|*.ru|*.ir|*apple*|*icloud*|*microsoft*)
      warn "官方 Xray 不建议将 ${sni} 用作 REALITY 目标，请确认你了解封锁风险。"
      ;;
  esac
}

validate_xray_server_address() {
  local value="${1:-}"
  [ -n "$value" ] && [ "${#value}" -le 253 ] &&
    [[ "$value" =~ ^[0-9A-Za-z.-]+$|^[0-9A-Fa-f:]+$ ]]
}

xray_config_supports_management() {
  command -v jq >/dev/null 2>&1 && [ -r "$XRAY_CONFIG_PATH" ] &&
    jq -e '
      type == "object" and
      ((.inbounds // []) | type == "array") and
      ((.outbounds // []) | type == "array")
    ' "$XRAY_CONFIG_PATH" >/dev/null 2>&1
}

normalize_xray_inbound_id() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9]{1,3}$ ]] || return 1
  [ "$((10#$value))" -ge 1 ] && [ "$((10#$value))" -le 999 ] || return 1
  printf '%03d\n' "$((10#$value))"
}

xray_managed_tag() {
  local id
  id="$(normalize_xray_inbound_id "${1:-}")" || return 1
  printf '%s%s\n' "$XRAY_MANAGED_TAG_PREFIX" "$id"
}

xray_managed_inbound_ids() {
  xray_config_supports_management || return 1
  jq -r --arg prefix "$XRAY_MANAGED_TAG_PREFIX" '
    (.inbounds // [])[]
    | select(.protocol == "vless")
    | .tag // ""
    | select(startswith($prefix))
    | ltrimstr($prefix)
    | select(test("^[0-9]{3}$"))
  ' "$XRAY_CONFIG_PATH" | sort -n
}

xray_managed_inbound_count() {
  local count
  if ! count="$(xray_managed_inbound_ids 2>/dev/null | wc -l)"; then
    echo 0
  else
    printf '%s\n' "${count//[[:space:]]/}"
  fi
}

xray_next_inbound_id() {
  local id max=0
  while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]{3}$ ]] || continue
    [ "$((10#$id))" -gt "$max" ] && max="$((10#$id))"
  done < <(xray_managed_inbound_ids 2>/dev/null || true)
  [ "$max" -lt 999 ] || { red "托管入站数量已达到上限。" >&2; return 1; }
  printf '%03d\n' "$((max + 1))"
}

xray_managed_inbound_exists() {
  local tag
  tag="$(xray_managed_tag "${1:-}")" || return 1
  jq -e --arg tag "$tag" 'any((.inbounds // [])[]; .tag == $tag)' \
    "$XRAY_CONFIG_PATH" >/dev/null 2>&1
}

xray_managed_inbound_json() {
  local tag
  tag="$(xray_managed_tag "${1:-}")" || return 1
  jq -c --arg tag "$tag" 'first((.inbounds // [])[] | select(.tag == $tag))' \
    "$XRAY_CONFIG_PATH"
}

xray_managed_inbound_field() {
  local id="$1" filter="$2" inbound
  inbound="$(xray_managed_inbound_json "$id")" || return 1
  jq -r "$filter" <<<"$inbound"
}

xray_managed_port_in_use() {
  local port="$1" excluded_id="${2:-}" excluded_tag=""
  [ -n "$excluded_id" ] && excluded_tag="$(xray_managed_tag "$excluded_id")"
  jq -e --argjson port "$port" --arg excluded "$excluded_tag" '
    any((.inbounds // [])[]; (.port == $port) and (.tag // "") != $excluded)
  ' "$XRAY_CONFIG_PATH" >/dev/null 2>&1
}

xray_reality_port_available() {
  local port="$1" excluded_id="${2:-}" current_port="" status
  validate_port "$port" || return 1
  if [ -n "$excluded_id" ] && xray_managed_inbound_exists "$excluded_id"; then
    current_port="$(xray_managed_inbound_field "$excluded_id" '.port')"
    [ "$port" = "$current_port" ] && return 0
  fi
  xray_managed_port_in_use "$port" "$excluded_id" && return 1
  if port_availability "$port"; then
    return 0
  else
    status=$?
  fi
  return "$status"
}

xray_default_reality_port() {
  local port status
  for port in 443 8443; do
    if xray_reality_port_available "$port"; then
      printf '%s\n' "$port"
      return 0
    else
      status=$?
    fi
    [ "$status" -gt 1 ] && return "$status"
  done
  return 1
}

xray_generate_uuid() {
  local value
  value="$("$XRAY_BIN_PATH" uuid 2>/dev/null | tail -n 1)"
  [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || {
    red "Xray 未能生成有效 UUID。" >&2
    return 1
  }
  printf '%s\n' "${value,,}"
}

xray_generate_reality_keypair() {
  local output private_key public_key
  output="$("$XRAY_BIN_PATH" x25519 2>&1)" || {
    red "Xray 未能生成 REALITY X25519 密钥。" >&2
    return 1
  }
  private_key="$(printf '%s\n' "$output" | sed -nE 's/^(PrivateKey|Private key):[[:space:]]*//p' | head -n 1)"
  public_key="$(printf '%s\n' "$output" | sed -nE 's/^(Password \(PublicKey\)|PublicKey|Public key):[[:space:]]*//p' | head -n 1)"
  if ! [[ "$private_key" =~ ^[0-9A-Za-z_-]{43}$ ]] ||
     ! [[ "$public_key" =~ ^[0-9A-Za-z_-]{43}$ ]]; then
    red "无法解析 Xray 生成的 REALITY 密钥。" >&2
    return 1
  fi
  printf '%s\n%s\n' "$private_key" "$public_key"
}

xray_public_key_from_private() {
  local private_key="$1" output public_key
  output="$("$XRAY_BIN_PATH" x25519 -i "$private_key" 2>&1)" || return 1
  public_key="$(printf '%s\n' "$output" | sed -nE 's/^(Password \(PublicKey\)|PublicKey|Public key):[[:space:]]*//p' | head -n 1)"
  [[ "$public_key" =~ ^[0-9A-Za-z_-]{43}$ ]] || return 1
  printf '%s\n' "$public_key"
}

xray_generate_short_id() {
  local value
  if command -v openssl >/dev/null 2>&1; then
    value="$(openssl rand -hex 8 2>/dev/null)"
  else
    value="$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  fi
  [[ "$value" =~ ^[0-9a-f]{16}$ ]] || { red "无法生成 REALITY shortId。" >&2; return 1; }
  printf '%s\n' "$value"
}

apply_xray_config_candidate() {
  local candidate="$1" action_label="$2" backup temp validation_output was_active=false
  need_root
  xray_is_installed || { red "Xray 尚未完整安装。"; return 1; }
  if ! validation_output="$("$XRAY_BIN_PATH" run -test -config "$candidate" 2>&1)"; then
    red "候选 Xray 配置校验失败，未修改现有配置。"
    printf '%s\n' "$validation_output" >&2
    return 1
  fi
  mkdir -p "$XRAY_BACKUP_DIR" || { red "无法创建 Xray 配置备份目录。"; return 1; }
  chown root:root "$XRAY_BACKUP_DIR" || return 1
  chmod 700 "$XRAY_BACKUP_DIR" || return 1
  backup="$(mktemp "${XRAY_BACKUP_DIR}/config-$(date +%Y%m%d-%H%M%S)-XXXXXX.json")" || return 1
  if ! install -o root -g root -m 600 "$XRAY_CONFIG_PATH" "$backup"; then
    rm -f "$backup"
    red "Xray 配置备份失败。"
    return 1
  fi
  temp="$(mktemp "${XRAY_CONFIG_PATH}.XXXXXX")" || return 1
  if ! install -o root -g nogroup -m 640 "$candidate" "$temp"; then
    rm -f "$temp"
    red "Xray 候选配置写入失败。"
    return 1
  fi
  xray_service_is_active && was_active=true
  if ! mv -f "$temp" "$XRAY_CONFIG_PATH"; then
    rm -f "$temp"
    red "Xray 配置替换失败。"
    return 1
  fi
  if [ "$was_active" = "true" ]; then
    warn "应用配置会重启 Xray；经由该核心的现有连接可能暂时中断。"
    if ! systemctl restart "$XRAY_SERVICE_NAME" || ! sleep 1 || ! xray_service_is_active; then
      install -o root -g nogroup -m 640 "$backup" "$XRAY_CONFIG_PATH" 2>/dev/null || true
      systemctl restart "$XRAY_SERVICE_NAME" 2>/dev/null || true
      red "Xray 服务未能使用新配置启动，已恢复原配置。"
      return 1
    fi
  fi
  success "${action_label}；配置备份: ${backup}"
}

xray_prepare_config_management() {
  need_root
  xray_is_installed || { red "请先安装 Xray 核心。"; return 1; }
  xray_ensure_dependencies || return 1
  if ! xray_config_supports_management; then
    red "当前 config.json 不是可安全管理的标准 JSON，已拒绝自动修改。"
    warn "请先确保根对象中的 inbounds 和 outbounds 为数组；JSONC 注释配置可继续手动使用。"
    return 1
  fi
}

add_xray_reality_inbound() {
  local sni="${1,,}" requested_port="${2:-}" user_name="${3:-user1}"
  local choices_warned="${4:-false}" port id tag uuid short_id candidate status
  local -a keypair=()
  xray_prepare_config_management || return 1
  validate_xray_sni "$sni" || { red "SNI 必须是有效域名，不能包含协议、路径或端口。"; return 1; }
  validate_xray_user_name "$user_name" || { red "用户名称只能包含字母、数字、点、下划线、@ 和连字符。"; return 1; }
  if [ -n "$requested_port" ]; then
    validate_port "$requested_port" || { red "端口必须是 1-65535 的整数。"; return 1; }
    port="$requested_port"
  elif ! port="$(xray_default_reality_port)"; then
    status=$?
    if [ "$status" -gt 1 ]; then
      red "无法检测 443 和 8443 端口是否可用。"
    else
      red "默认端口 443 和 8443 均已占用，请指定其他端口。"
    fi
    return 1
  fi
  if ! xray_reality_port_available "$port"; then
    status=$?
    if [ "$status" -gt 1 ]; then
      red "无法检测端口 ${port} 是否可用。"
    else
      red "端口 ${port} 已被占用。"
    fi
    return 1
  fi
  [ "$choices_warned" = "true" ] || warn_xray_reality_choices "$sni" "$port"
  id="$(xray_next_inbound_id)" || return 1
  tag="$(xray_managed_tag "$id")" || return 1
  uuid="$(xray_generate_uuid)" || return 1
  mapfile -t keypair < <(xray_generate_reality_keypair)
  [ "${#keypair[@]}" -eq 2 ] || return 1
  short_id="$(xray_generate_short_id)" || return 1
  candidate="$(mktemp "${XRAY_CONFIG_DIR}/.candidate.XXXXXX.json")" || return 1
  if ! jq \
      --arg tag "$tag" \
      --argjson port "$port" \
      --arg sni "$sni" \
      --arg target "${sni}:443" \
      --arg uuid "$uuid" \
      --arg user "$user_name" \
      --arg private_key "${keypair[0]}" \
      --arg short_id "$short_id" '
        .inbounds = ((.inbounds // []) + [{
          tag: $tag,
          listen: "0.0.0.0",
          port: $port,
          protocol: "vless",
          settings: {
            clients: [{id: $uuid, flow: "xtls-rprx-vision", email: $user}],
            decryption: "none"
          },
          streamSettings: {
            network: "tcp",
            security: "reality",
            realitySettings: {
              show: false,
              target: $target,
              xver: 0,
              serverNames: [$sni],
              privateKey: $private_key,
              shortIds: [$short_id]
            }
          },
          sniffing: {
            enabled: true,
            destOverride: ["http", "tls", "quic"],
            routeOnly: true
          }
        }])
        | if ((.outbounds // []) | length) == 0 then
            .outbounds = [{tag: "snell-managed-direct", protocol: "freedom"}]
          else . end
      ' "$XRAY_CONFIG_PATH" > "$candidate"; then
    rm -f "$candidate"
    red "生成 VLESS REALITY 候选配置失败。"
    return 1
  fi
  if ! apply_xray_config_candidate "$candidate" "VLESS REALITY 入站 ${id} 已创建"; then
    rm -f "$candidate"
    return 1
  fi
  rm -f "$candidate"
  success "入站 ID: ${id} · 端口: ${port} · SNI: ${sni} · 用户: ${user_name}"
}

edit_xray_reality_inbound() {
  local raw_id="$1" sni="${2,,}" port="$3" choices_warned="${4:-false}" id tag candidate status
  xray_prepare_config_management || return 1
  id="$(normalize_xray_inbound_id "$raw_id")" || { red "无效入站 ID: ${raw_id}"; return 1; }
  xray_managed_inbound_exists "$id" || { red "未找到托管入站 ${id}。"; return 1; }
  validate_xray_sni "$sni" || { red "SNI 必须是有效域名，不能包含协议、路径或端口。"; return 1; }
  validate_port "$port" || { red "端口必须是 1-65535 的整数。"; return 1; }
  if ! xray_reality_port_available "$port" "$id"; then
    status=$?
    if [ "$status" -gt 1 ]; then red "无法检测端口 ${port} 是否可用。"; else red "端口 ${port} 已被占用。"; fi
    return 1
  fi
  [ "$choices_warned" = "true" ] || warn_xray_reality_choices "$sni" "$port"
  tag="$(xray_managed_tag "$id")"
  candidate="$(mktemp "${XRAY_CONFIG_DIR}/.candidate.XXXXXX.json")" || return 1
  if ! jq --arg tag "$tag" --arg sni "$sni" --arg target "${sni}:443" --argjson port "$port" '
      .inbounds |= map(
        if .tag == $tag then
          .port = $port
          | .streamSettings.realitySettings.target = $target
          | .streamSettings.realitySettings.serverNames = [$sni]
        else . end
      )
    ' "$XRAY_CONFIG_PATH" > "$candidate"; then
    rm -f "$candidate"
    red "生成入站修改候选配置失败。"
    return 1
  fi
  if ! apply_xray_config_candidate "$candidate" "VLESS REALITY 入站 ${id} 已更新"; then
    rm -f "$candidate"
    return 1
  fi
  rm -f "$candidate"
}

delete_xray_reality_inbound() {
  local raw_id="$1" id tag candidate
  xray_prepare_config_management || return 1
  id="$(normalize_xray_inbound_id "$raw_id")" || { red "无效入站 ID: ${raw_id}"; return 1; }
  xray_managed_inbound_exists "$id" || { red "未找到托管入站 ${id}。"; return 1; }
  tag="$(xray_managed_tag "$id")"
  candidate="$(mktemp "${XRAY_CONFIG_DIR}/.candidate.XXXXXX.json")" || return 1
  if ! jq --arg tag "$tag" '.inbounds |= map(select(.tag != $tag))' \
      "$XRAY_CONFIG_PATH" > "$candidate"; then
    rm -f "$candidate"
    red "生成入站删除候选配置失败。"
    return 1
  fi
  if ! apply_xray_config_candidate "$candidate" "VLESS REALITY 入站 ${id} 已删除"; then
    rm -f "$candidate"
    return 1
  fi
  rm -f "$candidate"
}

add_xray_reality_user() {
  local raw_id="$1" user_name="$2" id tag uuid candidate
  xray_prepare_config_management || return 1
  id="$(normalize_xray_inbound_id "$raw_id")" || { red "无效入站 ID: ${raw_id}"; return 1; }
  xray_managed_inbound_exists "$id" || { red "未找到托管入站 ${id}。"; return 1; }
  validate_xray_user_name "$user_name" || { red "用户名称只能包含字母、数字、点、下划线、@ 和连字符。"; return 1; }
  tag="$(xray_managed_tag "$id")"
  if jq -e --arg tag "$tag" --arg user "$user_name" '
      any((.inbounds // [])[] | select(.tag == $tag) | .settings.clients[]; (.email // "") == $user)
    ' "$XRAY_CONFIG_PATH" >/dev/null; then
    red "入站 ${id} 已存在用户 ${user_name}。"
    return 1
  fi
  uuid="$(xray_generate_uuid)" || return 1
  candidate="$(mktemp "${XRAY_CONFIG_DIR}/.candidate.XXXXXX.json")" || return 1
  if ! jq --arg tag "$tag" --arg uuid "$uuid" --arg user "$user_name" '
      .inbounds |= map(
        if .tag == $tag then
          .settings.clients += [{id: $uuid, flow: "xtls-rprx-vision", email: $user}]
        else . end
      )
    ' "$XRAY_CONFIG_PATH" > "$candidate"; then
    rm -f "$candidate"
    red "生成用户候选配置失败。"
    return 1
  fi
  if ! apply_xray_config_candidate "$candidate" "用户 ${user_name} 已添加到入站 ${id}"; then
    rm -f "$candidate"
    return 1
  fi
  rm -f "$candidate"
  success "UUID: ${uuid}"
}

delete_xray_reality_user() {
  local raw_id="$1" uuid="$2" id tag candidate count
  xray_prepare_config_management || return 1
  id="$(normalize_xray_inbound_id "$raw_id")" || { red "无效入站 ID: ${raw_id}"; return 1; }
  xray_managed_inbound_exists "$id" || { red "未找到托管入站 ${id}。"; return 1; }
  tag="$(xray_managed_tag "$id")"
  count="$(xray_managed_inbound_field "$id" '.settings.clients | length')"
  [ "$count" -gt 1 ] || { red "不能删除入站的最后一个用户；请直接删除该入站。"; return 1; }
  if ! jq -e --arg tag "$tag" --arg uuid "$uuid" '
      any((.inbounds // [])[] | select(.tag == $tag) | .settings.clients[]; .id == $uuid)
    ' "$XRAY_CONFIG_PATH" >/dev/null; then
    red "入站 ${id} 中不存在该用户。"
    return 1
  fi
  candidate="$(mktemp "${XRAY_CONFIG_DIR}/.candidate.XXXXXX.json")" || return 1
  if ! jq --arg tag "$tag" --arg uuid "$uuid" '
      .inbounds |= map(
        if .tag == $tag then .settings.clients |= map(select(.id != $uuid)) else . end
      )
    ' "$XRAY_CONFIG_PATH" > "$candidate"; then
    rm -f "$candidate"
    red "生成用户删除候选配置失败。"
    return 1
  fi
  if ! apply_xray_config_candidate "$candidate" "用户已从入站 ${id} 删除"; then
    rm -f "$candidate"
    return 1
  fi
  rm -f "$candidate"
}

list_xray_managed_inbounds() {
  local id inbound port sni users
  xray_prepare_config_management || return 1
  section_title "Xray 托管入站"
  printf '%b  %-5s %-9s %-15s %-7s %s%b\n' "$C_GRAY" "ID" "协议" "传输" "端口" "用户" "$C_RESET"
  while IFS= read -r id; do
    inbound="$(xray_managed_inbound_json "$id")"
    port="$(jq -r '.port' <<<"$inbound")"
    sni="$(jq -r '.streamSettings.realitySettings.serverNames[0]' <<<"$inbound")"
    users="$(jq -r '.settings.clients | length' <<<"$inbound")"
    printf '  %-5s %-9s %-15s %-7s %s · %s\n' "$id" "VLESS" "REALITY/TCP" "$port" "$users" "$sni"
  done < <(xray_managed_inbound_ids)
}

show_xray_reality_inbound() {
  local raw_id="$1" id inbound
  id="$(normalize_xray_inbound_id "$raw_id")" || return 1
  xray_managed_inbound_exists "$id" || return 1
  inbound="$(xray_managed_inbound_json "$id")"
  section_title "VLESS REALITY 入站 ${id}"
  detail_row "协议" "VLESS"
  detail_row "传输" "TCP + REALITY"
  detail_row "流控" "xtls-rprx-vision"
  detail_row "端口" "$(jq -r '.port' <<<"$inbound")"
  detail_row "SNI" "$(jq -r '.streamSettings.realitySettings.serverNames[0]' <<<"$inbound")"
  detail_row "目标" "$(jq -r '.streamSettings.realitySettings.target // .streamSettings.realitySettings.dest' <<<"$inbound")"
  detail_row "用户" "$(jq -r '.settings.clients | length' <<<"$inbound")"
}

xray_url_encode() {
  jq -sRr @uri <<<"${1:-}" | sed 's/%0A$//'
}

show_xray_reality_clients() {
  local raw_id="$1" address="${2:-}" id inbound port sni private_key public_key short_id uri_address
  local uuid user label encoded_label
  xray_prepare_config_management || return 1
  id="$(normalize_xray_inbound_id "$raw_id")" || { red "无效入站 ID: ${raw_id}"; return 1; }
  xray_managed_inbound_exists "$id" || { red "未找到托管入站 ${id}。"; return 1; }
  if [ -z "$address" ]; then address="$(public_ip 4)"; fi
  validate_xray_server_address "$address" || { red "请提供有效的服务器域名或 IP 地址。"; return 1; }
  inbound="$(xray_managed_inbound_json "$id")"
  port="$(jq -r '.port' <<<"$inbound")"
  sni="$(jq -r '.streamSettings.realitySettings.serverNames[0]' <<<"$inbound")"
  private_key="$(jq -r '.streamSettings.realitySettings.privateKey' <<<"$inbound")"
  short_id="$(jq -r '.streamSettings.realitySettings.shortIds[0]' <<<"$inbound")"
  public_key="$(xray_public_key_from_private "$private_key")" || { red "无法从 REALITY 私钥推导公钥。"; return 1; }
  uri_address="$address"
  [[ "$address" == *:* ]] && uri_address="[${address}]"
  warn "Mihomo 必须支持 Xray 26.3.27+ REALITY 握手；旧版本可能认证失败。"
  while IFS=$'\t' read -r uuid user; do
    [ -n "$uuid" ] || continue
    [ -n "$user" ] || user="user"
    label="Reality-${id}-${user}"
    encoded_label="$(xray_url_encode "$label")"
    section_title "$label"
    printf '%s\n\n' "vless://${uuid}@${uri_address}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#${encoded_label}"
    printf '%s\n' "mihomo / Clash Meta"
    printf '%s\n' "- name: ${label}"
    printf '%s\n' "  type: vless"
    printf '%s\n' "  server: ${address}"
    printf '%s\n' "  port: ${port}"
    printf '%s\n' "  uuid: ${uuid}"
    printf '%s\n' "  network: tcp"
    printf '%s\n' "  tls: true"
    printf '%s\n' "  udp: true"
    printf '%s\n' "  flow: xtls-rprx-vision"
    printf '%s\n' "  client-fingerprint: chrome"
    printf '%s\n' "  servername: ${sni}"
    printf '%s\n' "  reality-opts:"
    printf '%s\n' "    public-key: ${public_key}"
    printf '%s\n\n' "    short-id: ${short_id}"
  done < <(jq -r '.settings.clients[] | [.id, (.email // "user")] | @tsv' <<<"$inbound")
  warn "请在云服务商安全组及本机防火墙中放行 TCP ${port}。"
}

write_xray_service() {
  local temp
  mkdir -p "$(dirname "$XRAY_SERVICE_PATH")" || return 1
  temp="$(mktemp "${XRAY_SERVICE_PATH}.XXXXXX")" || return 1
  cat > "$temp" <<EOF
[Unit]
Description=Xray Core Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNPROC=10000
LimitNOFILE=1000000
ExecStart=${XRAY_BIN_PATH} run -config ${XRAY_CONFIG_PATH}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$temp"
  mv -f "$temp" "$XRAY_SERVICE_PATH"
}

prepare_xray_logs() {
  local log_file
  mkdir -p "$XRAY_LOG_DIR" || return 1
  chown root:root "$XRAY_LOG_DIR" || return 1
  chmod 755 "$XRAY_LOG_DIR" || return 1
  for log_file in access.log error.log; do
    if [ ! -e "${XRAY_LOG_DIR}/${log_file}" ]; then
      install -o nobody -g nogroup -m 600 /dev/null "${XRAY_LOG_DIR}/${log_file}" || return 1
    else
      chown nobody:nogroup "${XRAY_LOG_DIR}/${log_file}" || return 1
      chmod 600 "${XRAY_LOG_DIR}/${log_file}" || return 1
    fi
  done
}

rollback_xray_install() {
  local rollback_dir="$1" config_created="$2" was_active="$3" was_enabled="$4"
  systemctl stop "$XRAY_SERVICE_NAME" 2>/dev/null || true

  if [ -f "${rollback_dir}/xray" ]; then
    install -m 755 "${rollback_dir}/xray" "$XRAY_BIN_PATH" 2>/dev/null || true
  else
    rm -f "$XRAY_BIN_PATH"
  fi
  mkdir -p "$XRAY_ASSET_DIR"
  if [ -f "${rollback_dir}/geoip.dat" ]; then
    cp -p "${rollback_dir}/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat" 2>/dev/null || true
  else
    rm -f "${XRAY_ASSET_DIR}/geoip.dat"
  fi
  if [ -f "${rollback_dir}/geosite.dat" ]; then
    cp -p "${rollback_dir}/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat" 2>/dev/null || true
  else
    rm -f "${XRAY_ASSET_DIR}/geosite.dat"
  fi
  if [ -f "${rollback_dir}/xray.service" ]; then
    cp -p "${rollback_dir}/xray.service" "$XRAY_SERVICE_PATH" 2>/dev/null || true
  else
    rm -f "$XRAY_SERVICE_PATH"
  fi
  [ "$config_created" = "true" ] && rm -f "$XRAY_CONFIG_PATH"

  systemctl daemon-reload 2>/dev/null || true
  if [ "$was_enabled" = "true" ]; then
    systemctl enable "$XRAY_SERVICE_NAME" 2>/dev/null || true
  else
    systemctl disable "$XRAY_SERVICE_NAME" 2>/dev/null || true
  fi
  if [ "$was_active" = "true" ]; then
    systemctl restart "$XRAY_SERVICE_NAME" 2>/dev/null || true
  fi
}

install_xray_core() {
  local requested="${1:-}" version old_version staged rollback validation_config
  local had_installation=false was_active=false was_enabled=false config_created=false
  need_root
  have_systemd || { red "未检测到 systemd，无法管理 Xray 服务。"; return 1; }
  xray_ensure_dependencies || return 1
  if ! version="$(resolve_xray_version "$requested")"; then return 1; fi
  old_version="$(xray_installed_version)"
  xray_is_installed && had_installation=true
  xray_service_is_active && was_active=true
  xray_service_is_enabled && was_enabled=true
  staged="$(mktemp -d)" || { red "无法创建 Xray 临时目录。"; return 1; }
  rollback="$(mktemp -d)" || { rm -rf "$staged"; red "无法创建 Xray 回滚目录。"; return 1; }

  if ! download_xray_package "$version" "$staged"; then
    rm -rf "$staged" "$rollback"
    return 1
  fi
  if [ -f "$XRAY_CONFIG_PATH" ]; then
    validation_config="$XRAY_CONFIG_PATH"
  else
    validation_config="${staged}/config.json"
    printf '{}\n' > "$validation_config"
  fi
  if ! xray_config_is_valid_with "${staged}/xray" "$validation_config"; then
    rm -rf "$staged" "$rollback"
    red "当前 Xray 配置无法通过新核心校验，已取消安装。"
    return 1
  fi

  if [ -e "$XRAY_BIN_PATH" ] && ! cp -p "$XRAY_BIN_PATH" "${rollback}/xray"; then
    rm -rf "$staged" "$rollback"; red "无法备份现有 Xray 核心。"; return 1
  fi
  if [ -e "${XRAY_ASSET_DIR}/geoip.dat" ] &&
     ! cp -p "${XRAY_ASSET_DIR}/geoip.dat" "${rollback}/geoip.dat"; then
    rm -rf "$staged" "$rollback"; red "无法备份 geoip.dat。"; return 1
  fi
  if [ -e "${XRAY_ASSET_DIR}/geosite.dat" ] &&
     ! cp -p "${XRAY_ASSET_DIR}/geosite.dat" "${rollback}/geosite.dat"; then
    rm -rf "$staged" "$rollback"; red "无法备份 geosite.dat。"; return 1
  fi
  if [ -e "$XRAY_SERVICE_PATH" ] &&
     ! cp -p "$XRAY_SERVICE_PATH" "${rollback}/xray.service"; then
    rm -rf "$staged" "$rollback"; red "无法备份 Xray 服务文件。"; return 1
  fi

  if ! mkdir -p "$(dirname "$XRAY_BIN_PATH")" "$(dirname "$XRAY_CONFIG_PATH")" "$XRAY_ASSET_DIR"; then
    rm -rf "$staged" "$rollback"; red "无法创建 Xray 安装目录。"; return 1
  fi
  if ! install -m 755 "${staged}/xray" "$XRAY_BIN_PATH" ||
     { [ -f "${staged}/geoip.dat" ] && ! install -m 644 "${staged}/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat"; } ||
     { [ -f "${staged}/geosite.dat" ] && ! install -m 644 "${staged}/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat"; }; then
    rollback_xray_install "$rollback" "$config_created" "$was_active" "$was_enabled"
    rm -rf "$staged" "$rollback"
    red "Xray 核心文件安装失败，已恢复原状态。"
    return 1
  fi
  if [ ! -f "$XRAY_CONFIG_PATH" ]; then
    if ! install -o root -g nogroup -m 640 "$validation_config" "$XRAY_CONFIG_PATH"; then
      rollback_xray_install "$rollback" "$config_created" "$was_active" "$was_enabled"
      rm -rf "$staged" "$rollback"
      red "Xray 初始配置写入失败，已恢复原状态。"
      return 1
    fi
    config_created=true
  fi
  if [ ! -f "$XRAY_SERVICE_PATH" ] && ! write_xray_service; then
    rollback_xray_install "$rollback" "$config_created" "$was_active" "$was_enabled"
    rm -rf "$staged" "$rollback"
    red "Xray 服务文件写入失败，已恢复原状态。"
    return 1
  fi
  if ! prepare_xray_logs; then
    rollback_xray_install "$rollback" "$config_created" "$was_active" "$was_enabled"
    rm -rf "$staged" "$rollback"
    red "Xray 日志目录准备失败，已恢复原状态。"
    return 1
  fi
  if ! systemctl daemon-reload || ! systemctl enable "$XRAY_SERVICE_NAME"; then
    rollback_xray_install "$rollback" "$config_created" "$was_active" "$was_enabled"
    rm -rf "$staged" "$rollback"
    red "Xray 服务注册失败，已恢复原状态。"
    return 1
  fi

  if [ "$had_installation" = "false" ] || [ "$was_active" = "true" ]; then
    if ! systemctl restart "$XRAY_SERVICE_NAME" || ! sleep 1 || ! xray_service_is_active; then
      rollback_xray_install "$rollback" "$config_created" "$was_active" "$was_enabled"
      rm -rf "$staged" "$rollback"
      red "Xray 新核心启动失败，已恢复 ${old_version:-原状态}。"
      return 1
    fi
  fi

  rm -rf "$staged" "$rollback"
  if [ "$had_installation" = "true" ]; then
    success "Xray 已从 ${old_version} 更新到 ${version}。"
    [ "$was_active" = "true" ] || success "Xray 服务保持停止状态。"
  else
    success "Xray ${version} 安装成功。"
    [ -s "$XRAY_CONFIG_PATH" ] && [ "$(tr -d '[:space:]' < "$XRAY_CONFIG_PATH")" = "{}" ] &&
      warn "当前是空配置；请从 Xray 管理 → 入站管理创建代理入站。"
  fi
}

xray_service_action() {
  local action="$1" label
  need_root
  xray_is_installed || { red "Xray 尚未完整安装。"; return 1; }
  case "$action" in
    start|restart)
      xray_config_is_valid || { red "Xray 配置校验失败，已拒绝启动。"; return 1; }
      systemctl "$action" "$XRAY_SERVICE_NAME" || return 1
      sleep 1
      xray_service_is_active || { red "Xray 服务未正常启动。"; return 1; }
      [ "$action" = "start" ] && label="启动" || label="重启"
      success "Xray 服务已${label}。"
      ;;
    stop) systemctl stop "$XRAY_SERVICE_NAME" && success "Xray 服务已停止。" ;;
    enable) systemctl enable "$XRAY_SERVICE_NAME" && success "Xray 已开启开机自启。" ;;
    disable) systemctl disable "$XRAY_SERVICE_NAME" && success "Xray 已关闭开机自启。" ;;
    *) red "不支持的 Xray 服务操作: $action"; return 1 ;;
  esac
}

show_xray_status() {
  local state="未安装" service_state="未注册" autostart="否" config_state="缺失"
  xray_core_installed && state="已安装"
  if xray_service_is_active; then service_state="运行中"; elif [ -f "$XRAY_SERVICE_PATH" ]; then service_state="已停止"; fi
  xray_service_is_enabled && autostart="是"
  if [ -f "$XRAY_CONFIG_PATH" ]; then
    if xray_config_is_valid; then config_state="有效"; else config_state="无效"; fi
  fi
  section_title "Xray 核心状态"
  detail_row "核心状态" "$state" "$(state_color "$state")"
  detail_row "核心版本" "$(xray_installed_version)"
  detail_row "服务状态" "$service_state" "$(state_color "$service_state")"
  detail_row "开机自启" "$autostart" "$(state_color "$autostart")"
  detail_row "配置状态" "$config_state"
  detail_row "核心路径" "$XRAY_BIN_PATH"
  detail_row "配置路径" "$XRAY_CONFIG_PATH"
}

show_xray_logs() {
  local lines="${1:-100}"
  [[ "$lines" =~ ^[1-9][0-9]*$ ]] || { red "日志行数必须是正整数。"; return 1; }
  command -v journalctl >/dev/null 2>&1 || { red "系统没有 journalctl。"; return 1; }
  journalctl -u "$XRAY_SERVICE_NAME" -n "$lines" --no-pager
}

follow_xray_logs() {
  command -v journalctl >/dev/null 2>&1 || { red "系统没有 journalctl。"; return 1; }
  journalctl -u "$XRAY_SERVICE_NAME" -f
}

uninstall_xray_core() {
  need_root
  xray_has_core_files || { yellow "未检测到 Xray 核心，无需卸载。"; return 0; }
  if have_systemd; then
    systemctl stop "$XRAY_SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$XRAY_SERVICE_NAME" 2>/dev/null || true
  fi
  rm -f "$XRAY_BIN_PATH" "$XRAY_SERVICE_PATH" \
    "${XRAY_ASSET_DIR}/geoip.dat" "${XRAY_ASSET_DIR}/geosite.dat"
  rmdir "$XRAY_ASSET_DIR" 2>/dev/null || true
  if have_systemd; then
    systemctl daemon-reload
    systemctl reset-failed "$XRAY_SERVICE_NAME" 2>/dev/null || true
  fi
  success "Xray 核心和服务已卸载；配置与日志保持不变。"
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
  local port="$1" output
  command -v ss >/dev/null 2>&1 || return 2
  if ! output="$(CONF_PATH="$CONF_PATH" ss -H -ltn 2>/dev/null)"; then
    return 2
  fi
  awk -v suffix=":${port}" '$4 ~ suffix "$" { found=1 } END { exit !found }' <<<"$output"
}

udp_port_in_use() {
  local port="$1" output
  command -v ss >/dev/null 2>&1 || return 2
  if ! output="$(CONF_PATH="$CONF_PATH" ss -H -lun 2>/dev/null)"; then
    return 2
  fi
  awk -v suffix=":${port}" '$4 ~ suffix "$" { found=1 } END { exit !found }' <<<"$output"
}

port_in_use() {
  local status
  if tcp_port_in_use "$1"; then
    return 0
  else
    status=$?
  fi
  [ "$status" -gt 1 ] && return "$status"
  if udp_port_in_use "$1"; then
    return 0
  else
    status=$?
  fi
  [ "$status" -gt 1 ] && return "$status"
  return 1
}

# Return 0 when the port is free, 1 when occupied, and 2 when it cannot be
# inspected. Callers must reject the third state instead of treating it as
# availability.
port_availability() {
  local status
  if port_in_use "$1"; then
    return 1
  else
    status=$?
  fi
  [ "$status" -eq 1 ] && return 0
  return 2
}

transport_label() {
  [ "$SNELL_PROTOCOL" = "v5" ] && echo "TCP/UDP" || echo "TCP"
}

pick_port() {
  local candidate attempts=0 status
  if [ -n "$SNELL_PORT" ]; then
    validate_port "$SNELL_PORT" || { red "SNELL_PORT 必须是 1-65535 的整数。" >&2; return 1; }
    if port_availability "$SNELL_PORT"; then
      echo "$SNELL_PORT"
      return 0
    else
      status=$?
      if [ "$status" -eq 1 ]; then
        red "端口 ${SNELL_PORT} 已被占用。" >&2
      else
        red "无法检测端口 ${SNELL_PORT} 是否被占用。" >&2
      fi
      return 1
    fi
  fi

  while [ "$attempts" -lt 50 ]; do
    candidate=$(( RANDOM % 20001 + 20000 ))
    if port_availability "$candidate"; then
      echo "$candidate"
      return 0
    else
      status=$?
    fi
    if [ "$status" -gt 1 ]; then
      red "无法检测随机端口是否被占用。" >&2
      return 1
    fi
    attempts=$((attempts + 1))
  done
  red "未能找到可用的随机端口。" >&2
  return 1
}

install_port_available() {
  local requested="$1" current="" status
  if port_availability "$requested"; then
    return 0
  else
    status=$?
  fi
  [ "$status" -gt 1 ] && return "$status"
  if is_installed && service_is_active; then
    current="$(current_port)"
    [ "$requested" = "$current" ] && return 0
  fi
  return 1
}

read_install_port() {
  local prompt="$1" tty_fd
  if [ -t 0 ]; then
    read -r -p "$prompt" REPLY
  elif [ -r /dev/tty ] && exec {tty_fd}</dev/tty 2>/dev/null; then
    # A script piped to bash has a non-terminal stdin, but can still use the
    # controlling terminal for the install prompt.
    if ! read -r -u "$tty_fd" -p "$prompt" REPLY; then
      exec {tty_fd}<&-
      return 1
    fi
    exec {tty_fd}<&-
  else
    return 1
  fi
}

choose_install_port() {
  local requested="${1:-${SNELL_PORT:-}}" current="" status
  if is_installed; then
    current="$(current_port)"
    validate_port "$current" || current=""
  fi

  if [ -n "$requested" ]; then
    validate_port "$requested" || { red "SNELL_PORT 必须是 1-65535 的整数。" >&2; return 1; }
    if install_port_available "$requested"; then
      printf '%s\n' "$requested"
    else
      status=$?
      if [ "$status" -eq 2 ]; then
        red "无法检测端口 ${requested} 是否被占用。" >&2
      else
        red "端口 ${requested} 已被占用。" >&2
      fi
      return 1
    fi
    return 0
  fi

  if [ -t 0 ] || [ -r /dev/tty ]; then
    while true; do
      if [ -n "$current" ]; then
        read_install_port "监听端口 [当前 ${current}，留空保留]: " || break
        requested="$REPLY"
        requested="${requested:-$current}"
      else
        read_install_port "监听端口 [留空自动选择 20000-40000]: " || break
        requested="$REPLY"
        if [ -z "$requested" ]; then
          pick_port
          return
        fi
      fi
      if ! validate_port "$requested"; then
        red "端口必须是 1-65535 的整数，请重新输入。" >&2
        continue
      fi
      if install_port_available "$requested"; then
        printf '%s\n' "$requested"
        return 0
      else
        status=$?
        if [ "$status" -eq 2 ]; then
          red "无法检测端口 ${requested} 是否被占用，请稍后重试。" >&2
          return 1
        fi
        red "端口 ${requested} 已被占用，请选择其他端口。" >&2
      fi
    done
  fi

  pick_port
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
  command -v ss >/dev/null 2>&1 || {
    red "端口检测工具 ss 安装失败，已中止安装。"
    return 1
  }
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
  local requested_port="${1:-}" answer psk port staged_binary
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
    read -r -p "重装 Snell ${SNELL_PROTOCOL} 会重新生成 PSK，是否继续? [y/N] " answer
    case "${answer:-N}" in
      y|Y|yes|YES) backup_config "pre-reinstall" >/dev/null || true ;;
      *) yellow "已取消。"; return 0 ;;
    esac
  fi

  # Port inspection must run after dependencies are available; otherwise a
  # missing `ss` would make every port look available.
  ensure_dependencies || return 1
  port="$(choose_install_port "$requested_port")" || return 1
  info "监听端口: ${port}"
  psk="$(gen_psk)" || return 1
  staged_binary="$(mktemp)" || { red "无法创建临时文件。"; return 1; }
  rm -f "$staged_binary"

  if ! download_binary "$SNELL_VERSION" "$staged_binary"; then
    rm -f "$staged_binary"
    return 1
  fi
  mkdir -p "$(dirname "$BIN_PATH")" "$(dirname "$SERVICE_PATH")" || return 1
  install -m 755 "$staged_binary" "$BIN_PATH" || { rm -f "$staged_binary"; return 1; }
  rm -f "$staged_binary"
  write_config "$port" "$psk" "$SNELL_IPV6" "$SNELL_MODE" "" "" "" || return 1
  write_service "$SNELL_VERSION" || return 1
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
  local port="${1:-}" old_port status
  old_port="$(current_port)"
  validate_port "$port" || { red "端口必须是 1-65535 的整数。"; return 1; }
  if [ "$port" != "$old_port" ]; then
    if port_availability "$port"; then
      :
    else
      status=$?
      if [ "$status" -eq 2 ]; then
        red "无法检测端口 ${port} 是否被占用。"
      else
        red "端口 ${port} 已被其他程序占用。"
      fi
      return 1
    fi
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
  [ "$SNELL_PROTOCOL" = "v6" ] && detail_row "发布通道" "Beta" "$C_YELLOW"
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

prompt_server_update() {
  local version answer
  read -r -p "目标版本 [${SNELL_VERSION}]: " version
  version="${version:-$SNELL_VERSION}"
  warn "更新会重启 Snell ${SNELL_PROTOCOL}；现有代理连接可能暂时中断。"
  warn "如果当前 SSH 经由该实例连接，断线本身不代表更新失败，请重连后查看状态。"
  read -r -p "确认更新 Snell ${SNELL_PROTOCOL} 内核到 ${version}? [y/N] " answer
  if [[ "$answer" =~ ^[yY]$ ]]; then
    update_server "$version"
  else
    yellow "已取消。"
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
    [ "$SNELL_PROTOCOL" = "v6" ] && version="${version} Beta"
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

advanced_configuration_menu() {
  local choice value current dns_state dns_preference_label egress_interface
  while true; do
    current="$(current_dns_preference)"
    case "$current" in
      ''|default) dns_preference_label="自动选择" ;;
      prefer-ipv4) dns_preference_label="优先 IPv4" ;;
      prefer-ipv6) dns_preference_label="优先 IPv6" ;;
      ipv4-only) dns_preference_label="仅 IPv4" ;;
      ipv6-only) dns_preference_label="仅 IPv6" ;;
      *) dns_preference_label="$current" ;;
    esac
    [ -n "$(current_dns)" ] && dns_state="已设置" || dns_state="系统默认"
    egress_interface="$(current_egress_interface)"
    egress_interface="${egress_interface:-未绑定}"

    clear_screen
    panel_header
    section_title "高级配置"
    menu_option 1 "自定义 DNS  ·  ${dns_state}"
    menu_option 2 "DNS IP 偏好  ·  ${dns_preference_label}"
    menu_option 3 "出口网卡  ·  ${egress_interface}"
    [ "$SNELL_PROTOCOL" = "v6" ] && menu_option 4 "运行模式  ·  $(current_mode)"
    menu_option q "返回配置" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        echo "当前值: $(current_dns | sed 's/^$/系统默认/')"
        read -r -p "DNS 地址，多个用逗号分隔（留空清除）: " value
        set_dns "$value" || true
        pause_screen
        ;;
      2)
        menu_option 1 "自动选择（默认）"
        menu_option 2 "优先 IPv4"
        menu_option 3 "优先 IPv6"
        menu_option 4 "仅 IPv4"
        menu_option 5 "仅 IPv6"
        menu_option q "返回" back
        read -r -p "请选择 [当前 ${dns_preference_label}]: " value
        case "$value" in
          1) set_dns_preference "" || true ;;
          2) set_dns_preference prefer-ipv4 || true ;;
          3) set_dns_preference prefer-ipv6 || true ;;
          4) set_dns_preference ipv4-only || true ;;
          5) set_dns_preference ipv6-only || true ;;
          0|q|Q) continue ;;
          *) yellow "未修改。" ;;
        esac
        pause_screen
        ;;
      3)
        echo "当前值: $(current_egress_interface | sed 's/^$/未绑定/')"
        read -r -p "出口网卡名称（留空清除）: " value
        set_egress_interface "$value" || true
        pause_screen
        ;;
      4)
        if [ "$SNELL_PROTOCOL" != "v6" ]; then
          yellow "无效选择。"
        else
          menu_option 1 "default    兼容性优先"
          menu_option 2 "unshaped   不使用流量整形"
          menu_option 3 "unsafe-raw 原始模式"
          menu_option q "返回" back
          read -r -p "请选择 [当前 $(current_mode)]: " value
          case "$value" in
            1) set_mode default || true ;;
            2) set_mode unshaped || true ;;
            3) set_mode unsafe-raw || true ;;
            0|q|Q) continue ;;
            *) yellow "未修改。" ;;
          esac
        fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

configuration_menu() {
  local choice value current ipv6_state
  while true; do
    current="$(current_ipv6)"
    [ "$current" = "true" ] && ipv6_state="已开启" || ipv6_state="已关闭"
    clear_screen
    panel_header
    section_title "修改配置"
    menu_option 1 "监听端口  ·  $(current_port)"
    menu_option 2 "更新 PSK"
    menu_option 3 "IPv6  ·  ${ipv6_state}"
    menu_option 4 "高级配置"
    menu_option q "返回" back
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
        read -r -s -p "新 PSK [留空自动生成，输入 q 取消]: " value; echo
        if [[ "$value" =~ ^[qQ]$ ]] || [ "$value" = "0" ]; then
          continue
        else
          read -r -p "修改后旧客户端配置将失效，确认继续? [y/N] " choice
          if [[ "$choice" =~ ^[yY]$ ]]; then set_psk "$value" || true; else yellow "已取消。"; fi
        fi
        pause_screen
        ;;
      3)
        current="$(current_ipv6)"
        [ "$current" = "true" ] && value="false" || value="true"
        [ "$value" = "true" ] && current="开启" || current="关闭"
        read -r -p "确认${current} IPv6? [y/N] " choice
        if [[ "$choice" =~ ^[yY]$ ]]; then set_ipv6 "$value" || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      4) advanced_configuration_menu ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

service_menu() {
  local choice primary_action primary_label autostart_action autostart_label
  while true; do
    clear_screen
    panel_header
    section_title "服务控制"
    if service_is_active; then
      primary_action="restart"
      primary_label="重启服务"
    else
      primary_action="start"
      primary_label="启动服务"
    fi
    if service_is_enabled; then
      autostart_action="disable"
      autostart_label="关闭开机自启"
    else
      autostart_action="enable"
      autostart_label="开启开机自启"
    fi
    menu_option 1 "$primary_label"
    menu_option 2 "$autostart_label"
    service_is_active && menu_option 3 "停止服务"
    menu_option q "返回" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) service_action "$primary_action" || true; pause_screen ;;
      2) service_action "$autostart_action" || true; pause_screen ;;
      3)
        if service_is_active; then service_action stop || true; else yellow "无效选择。"; fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

maintenance_menu() {
  local choice answer
  while true; do
    has_installation_files || return 0
    clear_screen
    panel_header
    section_title "日志与维护"
    if is_installed; then
      menu_option 1 "查看运行详情"
      menu_option 2 "查看最近日志"
      menu_option 3 "实时跟踪日志"
      menu_option 4 "一键诊断"
      menu_option 5 "备份与恢复"
      menu_option 6 "卸载 Snell" danger
    else
      menu_option 1 "查看安装详情"
      menu_option 2 "一键诊断"
      menu_option 3 "清理残留文件" danger
    fi
    menu_option q "返回" back
    echo
    read -r -p "请选择: " choice
    if ! is_installed; then
      case "$choice" in
        1) clear_screen; show_status || true; pause_screen ;;
        2) clear_screen; diagnose || true; pause_screen ;;
        3)
          read -r -p "确认清理当前残留的程序、配置和备份? [y/N] " answer
          if [[ "$answer" =~ ^[yY]$ ]]; then do_uninstall; else yellow "已取消。"; fi
          pause_screen
          ;;
        0|q|Q) return 0 ;;
        *) yellow "无效选择。"; pause_screen ;;
      esac
      continue
    fi
    case "$choice" in
      1) clear_screen; show_status || true; pause_screen ;;
      2) clear_screen; show_logs 100 || true; pause_screen ;;
      3) clear_screen; follow_logs || true; pause_screen ;;
      4) clear_screen; diagnose || true; pause_screen ;;
      5) backup_menu ;;
      6)
        read -r -p "这会删除程序、配置和备份，确认卸载? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then do_uninstall; else yellow "已取消。"; fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
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
    menu_option q "返回" back
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
        menu_option q "取消" back
        read -r -p "选择备份: " choice
        if [[ "$choice" =~ ^[qQ]$ ]] || [ "$choice" = "0" ]; then
          continue
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#backups[@]}" ]; then
          backup="${backups[$((choice - 1))]}"
          read -r -p "确认恢复 $(basename "$backup")? [y/N] " answer
          if [[ "$answer" =~ ^[yY]$ ]]; then restore_backup "$backup" || true; else yellow "已取消。"; fi
        else
          yellow "已取消。"
        fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

instance_menu() {
  local choice
  need_root
  [ -t 0 ] || { red "交互式面板需要在终端中运行。"; return 1; }
  while true; do
    clear_screen
    panel_header
    section_title "常用操作"
    if is_installed; then
      menu_option 1 "生成客户端配置"
      menu_option 2 "修改配置"
      menu_option 3 "服务控制"
      menu_option 4 "日志与维护"
      menu_option 5 "更新 Snell 内核" accent
    elif has_installation_files; then
      menu_option 1 "修复 Snell ${SNELL_PROTOCOL} 安装"
      menu_option 2 "诊断 / 清理残留"
    else
      menu_option 1 "安装 Snell ${SNELL_PROTOCOL}"
    fi
    menu_option q "返回上一级" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        if is_installed; then
          clear_screen
          show_client_config || true
        else
          do_install || true
        fi
        pause_screen
        ;;
      2)
        if is_installed; then
          configuration_menu
        elif has_installation_files; then
          maintenance_menu
        else
          yellow "无效选择。"
          pause_screen
        fi
        ;;
      3) if is_installed; then service_menu; else yellow "无效选择。"; pause_screen; fi ;;
      4) if is_installed; then maintenance_menu; else yellow "无效选择。"; pause_screen; fi ;;
      5)
        if is_installed; then
          prompt_server_update || true
        else
          yellow "无效选择。"
        fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
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
    [ "$protocol" = "v6" ] && version="${version} Beta"
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

snell_panel_header() {
  local -a protocols=()
  mapfile -t protocols < <(snell_present_protocols)
  printf '%b\n' "${C_CYAN}${C_BOLD}╭────────────────────────────────────────────╮${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}│${C_RESET}               ${C_WHITE}${C_BOLD}Snell 核心管理${C_RESET}               ${C_CYAN}${C_BOLD}│${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}╰────────────────────────────────────────────╯${C_RESET}"
  if [ "${#protocols[@]}" -eq 0 ]; then
    core_summary_row "Snell" "未安装" "-"
  else
    show_all_status
  fi
  if legacy_has_files; then
    printf '  %b旧实例%b  检测到 snell.service (%s)，可从菜单迁移\n' "$C_YELLOW" "$C_RESET" "$(legacy_installed_version | sed 's/^$/版本未知/')"
  fi
  echo
}

core_summary_row() {
  local name="$1" state="$2" detail="$3" status_style
  status_style="$(state_color "$state")"
  printf '  %b%-7s%b %b%-10s%b %s\n' \
    "${C_CYAN}${C_BOLD}" "$name" "$C_RESET" \
    "$status_style" "$state" "$C_RESET" "$detail"
}

show_core_status() {
  local selected="$SNELL_PROTOCOL" protocol state detail version
  local snell_state="未安装" snell_detail="-" active_count=0 installed_count=0 partial_count=0
  local -a instance_details=()

  for protocol in v5 v6; do
    use_instance "$protocol"
    if is_installed; then
      installed_count=$((installed_count + 1))
      version="$(installed_version)"
      if service_is_active; then
        active_count=$((active_count + 1))
        [ "$protocol" = "v6" ] && version="${version} Beta"
        instance_details+=("${version}")
      else
        [ "$protocol" = "v6" ] && version="${version} Beta"
        instance_details+=("${version}")
      fi
    elif has_installation_files; then
      partial_count=$((partial_count + 1))
      instance_details+=("${protocol} 待修复")
    fi
  done
  use_instance "$selected"
  if [ "${#instance_details[@]}" -eq 1 ]; then
    snell_detail="${instance_details[0]}"
  elif [ "${#instance_details[@]}" -gt 1 ]; then
    snell_detail="v5 / v6 共存（兼容模式）"
  fi
  if [ "$active_count" -gt 0 ]; then
    snell_state="运行中"
  elif [ "$installed_count" -gt 0 ]; then
    snell_state="已停止"
  elif [ "$partial_count" -gt 0 ]; then
    snell_state="安装不完整"
  fi

  if xray_service_is_active; then
    state="运行中"
  elif xray_core_installed; then
    state="已停止"
  elif xray_has_core_files; then
    state="安装不完整"
  else
    state="未安装"
  fi
  if xray_core_installed; then
    detail="$(xray_installed_version)"
  elif [ -f "$XRAY_CONFIG_PATH" ]; then
    detail="已保留配置"
  else
    detail="-"
  fi

  printf '%b\n' "${C_BOLD}${C_WHITE}核心概览${C_RESET}"
  printf '%b  %-7s %-10s %s%b\n' "$C_GRAY" "核心" "状态" "详情" "$C_RESET"
  core_summary_row "Snell" "$snell_state" "$snell_detail"
  core_summary_row "Xray" "$state" "$detail"
  echo
}

main_panel_header() {
  printf '%b\n' "${C_CYAN}${C_BOLD}   ____ ___  ____  _____${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}  / ___/ _ \\|  _ \\| ____|${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD} | |  | | | | |_) |  _|${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD} | |__| |_| |  _ <| |___${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}  \\____\\___/|_| \\_\\_____|${C_RESET}"
  printf '%b\n\n' "${C_MAGENTA}${C_BOLD}          Hello World!${C_RESET}"
  show_core_status
}

xray_panel_header() {
  local state="未安装" version="-" config_state="缺失" status_style
  if xray_service_is_active; then
    state="运行中"
  elif xray_core_installed; then
    state="已停止"
  elif xray_has_core_files; then
    state="安装不完整"
  fi
  xray_core_installed && version="$(xray_installed_version)"
  if [ -f "$XRAY_CONFIG_PATH" ]; then
    if xray_core_installed && xray_config_is_valid; then config_state="有效"; else config_state="待检查"; fi
  fi
  status_style="$(state_color "$state")"
  printf '%b\n' "${C_CYAN}${C_BOLD}╭────────────────────────────────────────────╮${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}│${C_RESET}               ${C_WHITE}${C_BOLD}Xray 核心管理${C_RESET}                ${C_CYAN}${C_BOLD}│${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}╰────────────────────────────────────────────╯${C_RESET}"
  printf '  %b状态%b  %b%-10s%b  %b版本%b  %b%-14s%b  %b配置%b  %s\n\n' \
    "$C_GRAY" "$C_RESET" "$status_style" "$state" "$C_RESET" \
    "$C_GRAY" "$C_RESET" "$C_MAGENTA" "$version" "$C_RESET" \
    "$C_GRAY" "$C_RESET" "$config_state"
}

prompt_xray_install() {
  local action="$1" version answer action_label default_label="${XRAY_VERSION:-最新稳定版}"
  [ "$action" = "update" ] && action_label="更新" || action_label="安装"
  read -r -p "目标版本 [${default_label}]: " version
  if [ "$action" = "update" ]; then
    warn "更新会重启 Xray；经由该核心的现有连接可能暂时中断。"
  fi
  read -r -p "确认${action_label} Xray ${version:-${default_label}}? [y/N] " answer
  if [[ "$answer" =~ ^[yY]$ ]]; then
    install_xray_core "$version"
  else
    yellow "已取消。"
  fi
}

prompt_add_xray_reality_inbound() {
  local sni port user_name answer default_port="" id
  xray_prepare_config_management || return 1
  default_port="$(xray_default_reality_port 2>/dev/null || true)"
  while true; do
    read -r -p "REALITY SNI（必填，如 www.example.com）: " sni
    sni="${sni,,}"
    validate_xray_sni "$sni" && break
    red "请输入有效域名，不要包含 https://、路径或端口。"
  done
  while true; do
    if [ -n "$default_port" ]; then
      read -r -p "监听端口 [${default_port}]: " port
      port="${port:-$default_port}"
    else
      read -r -p "监听端口 [443 和 8443 均被占用]: " port
    fi
    if validate_port "$port" && xray_reality_port_available "$port"; then break; fi
    red "端口无效、已占用或无法确认可用，请重新输入。"
  done
  read -r -p "首个用户名称 [user1]: " user_name
  user_name="${user_name:-user1}"
  validate_xray_user_name "$user_name" || { red "用户名称格式无效。"; return 1; }
  echo
  detail_row "协议" "VLESS + TCP + REALITY + Vision"
  detail_row "SNI" "$sni"
  detail_row "目标" "${sni}:443"
  detail_row "端口" "$port"
  detail_row "用户" "$user_name"
  warn_xray_reality_choices "$sni" "$port"
  read -r -p "确认创建入站? [y/N] " answer
  if ! [[ "$answer" =~ ^[yY]$ ]]; then yellow "已取消。"; return 0; fi
  add_xray_reality_inbound "$sni" "$port" "$user_name" true || return 1
  id="$(xray_managed_inbound_ids | tail -n 1)"
  if [ -n "$id" ]; then show_xray_reality_clients "$id" || true; fi
}

prompt_edit_xray_reality_inbound() {
  local id="$1" inbound current_sni current_port sni port answer
  inbound="$(xray_managed_inbound_json "$id")" || return 1
  current_sni="$(jq -r '.streamSettings.realitySettings.serverNames[0]' <<<"$inbound")"
  current_port="$(jq -r '.port' <<<"$inbound")"
  read -r -p "REALITY SNI [${current_sni}]: " sni
  sni="${sni:-$current_sni}"
  sni="${sni,,}"
  validate_xray_sni "$sni" || { red "SNI 必须是有效域名。"; return 1; }
  read -r -p "监听端口 [${current_port}]: " port
  port="${port:-$current_port}"
  validate_port "$port" || { red "端口必须是 1-65535 的整数。"; return 1; }
  if [ "$sni" = "$current_sni" ] && [ "$port" = "$current_port" ]; then
    yellow "配置没有变化。"
    return 0
  fi
  warn_xray_reality_choices "$sni" "$port"
  read -r -p "确认更新入站 ${id}? [y/N] " answer
  if [[ "$answer" =~ ^[yY]$ ]]; then
    edit_xray_reality_inbound "$id" "$sni" "$port" true
  else
    yellow "已取消。"
  fi
}

xray_reality_users_menu() {
  local id="$1" choice user_name answer selected uuid index
  local -a records=()
  while xray_managed_inbound_exists "$id"; do
    clear_screen
    xray_panel_header
    show_xray_reality_inbound "$id"
    section_title "用户管理"
    mapfile -t records < <(xray_managed_inbound_field "$id" '.settings.clients[] | [.id, (.email // "user")] | @tsv')
    for index in "${!records[@]}"; do
      uuid="${records[$index]%%$'\t'*}"
      user_name="${records[$index]#*$'\t'}"
      printf '  %d) %-20s %s…\n' "$((index + 1))" "$user_name" "${uuid:0:8}"
    done
    echo
    menu_option a "添加用户" accent
    menu_option d "删除用户" danger
    menu_option q "返回入站" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      a|A)
        read -r -p "用户名称 [user$(( ${#records[@]} + 1 ))]: " user_name
        user_name="${user_name:-user$(( ${#records[@]} + 1 ))}"
        add_xray_reality_user "$id" "$user_name" || true
        pause_screen
        ;;
      d|D)
        read -r -p "要删除的用户编号: " selected
        if ! [[ "$selected" =~ ^[1-9][0-9]*$ ]] || [ "$selected" -gt "${#records[@]}" ]; then
          yellow "无效用户编号。"; pause_screen; continue
        fi
        uuid="${records[$((selected - 1))]%%$'\t'*}"
        user_name="${records[$((selected - 1))]#*$'\t'}"
        read -r -p "确认删除用户 ${user_name}? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then delete_xray_reality_user "$id" "$uuid" || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

xray_reality_inbound_menu() {
  local id="$1" choice answer address default_address
  while xray_managed_inbound_exists "$id"; do
    clear_screen
    xray_panel_header
    show_xray_reality_inbound "$id"
    section_title "入站操作"
    menu_option 1 "生成客户端配置"
    menu_option 2 "用户管理"
    menu_option 3 "修改 SNI / 端口"
    menu_option 4 "删除入站" danger
    menu_option q "返回入站列表" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        default_address="$(public_ip 4)"
        if [ -n "$default_address" ]; then
          read -r -p "服务器地址 [${default_address}]: " address
          address="${address:-$default_address}"
        else
          read -r -p "服务器域名或 IP: " address
        fi
        clear_screen
        show_xray_reality_clients "$id" "$address" || true
        pause_screen
        ;;
      2) xray_reality_users_menu "$id" ;;
      3) prompt_edit_xray_reality_inbound "$id" || true; pause_screen ;;
      4)
        read -r -p "确认删除入站 ${id} 及其全部用户? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then delete_xray_reality_inbound "$id" || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

xray_inbounds_menu() {
  local choice id inbound port sni users index
  local -a ids=()
  xray_prepare_config_management || { pause_screen; return 1; }
  while true; do
    clear_screen
    xray_panel_header
    section_title "托管入站"
    mapfile -t ids < <(xray_managed_inbound_ids)
    if [ "${#ids[@]}" -eq 0 ]; then
      printf '  %b暂无托管入站%b\n\n' "$C_YELLOW" "$C_RESET"
    else
      for index in "${!ids[@]}"; do
        id="${ids[$index]}"
        inbound="$(xray_managed_inbound_json "$id")"
        port="$(jq -r '.port' <<<"$inbound")"
        sni="$(jq -r '.streamSettings.realitySettings.serverNames[0]' <<<"$inbound")"
        users="$(jq -r '.settings.clients | length' <<<"$inbound")"
        menu_option "$((index + 1))" "VLESS Reality  ·  TCP ${port}  ·  ${users} 用户  ·  ${sni}"
      done
      echo
    fi
    menu_option a "添加 VLESS Reality 入站" accent
    menu_option q "返回 Xray 管理" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      a|A) prompt_add_xray_reality_inbound || true; pause_screen ;;
      0|q|Q) return 0 ;;
      *)
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#ids[@]}" ]; then
          xray_reality_inbound_menu "${ids[$((choice - 1))]}"
        else
          yellow "无效选择。"; pause_screen
        fi
        ;;
    esac
  done
}

xray_service_menu() {
  local choice primary_action primary_label autostart_action autostart_label
  while true; do
    clear_screen
    xray_panel_header
    section_title "Xray 服务控制"
    if xray_service_is_active; then primary_action="restart"; primary_label="重启服务"; else primary_action="start"; primary_label="启动服务"; fi
    if xray_service_is_enabled; then autostart_action="disable"; autostart_label="关闭开机自启"; else autostart_action="enable"; autostart_label="开启开机自启"; fi
    menu_option 1 "$primary_label"
    menu_option 2 "$autostart_label"
    xray_service_is_active && menu_option 3 "停止服务"
    menu_option q "返回 Xray 管理" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) xray_service_action "$primary_action" || true; pause_screen ;;
      2) xray_service_action "$autostart_action" || true; pause_screen ;;
      3) if xray_service_is_active; then xray_service_action stop || true; else yellow "无效选择。"; fi; pause_screen ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

xray_menu() {
  local choice answer
  need_root
  [ -t 0 ] || { red "交互式面板需要在终端中运行。"; return 1; }
  while true; do
    clear_screen
    xray_panel_header
    section_title "常用操作"
    if xray_is_installed; then
      menu_option 1 "入站管理"
      menu_option 2 "更新 Xray 核心" accent
      menu_option 3 "服务控制"
      menu_option 4 "查看最近日志"
      menu_option 5 "实时跟踪日志"
      menu_option 6 "卸载 Xray 核心（保留配置）" danger
    else
      menu_option 1 "安装 / 修复 Xray 核心" accent
      xray_has_files && menu_option 2 "查看现有文件状态"
      xray_has_core_files && menu_option 3 "清理 Xray 核心（保留配置）" danger
    fi
    menu_option q "返回主菜单" back
    echo
    read -r -p "请选择: " choice
    if ! xray_is_installed; then
      case "$choice" in
        1) prompt_xray_install install || true; pause_screen ;;
        2) if xray_has_files; then clear_screen; show_xray_status; else yellow "无效选择。"; fi; pause_screen ;;
        3)
          if ! xray_has_core_files; then yellow "无效选择。"; pause_screen; continue; fi
          read -r -p "确认清理 Xray 核心和服务并保留配置? [y/N] " answer
          if [[ "$answer" =~ ^[yY]$ ]]; then uninstall_xray_core; else yellow "已取消。"; fi
          pause_screen
          ;;
        0|q|Q) return 0 ;;
        *) yellow "无效选择。"; pause_screen ;;
      esac
      continue
    fi
    case "$choice" in
      1) xray_inbounds_menu ;;
      2) prompt_xray_install update || true; pause_screen ;;
      3) xray_service_menu ;;
      4) clear_screen; show_xray_logs 100 || true; pause_screen ;;
      5) clear_screen; follow_xray_logs || true; pause_screen ;;
      6)
        read -r -p "确认卸载 Xray 核心和服务并保留配置? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then uninstall_xray_core; else yellow "已取消。"; fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

snell_present_protocols() {
  local selected="$SNELL_PROTOCOL" protocol
  for protocol in v5 v6; do
    use_instance "$protocol"
    if has_installation_files; then printf '%s\n' "$protocol"; fi
  done
  use_instance "$selected"
}

choose_snell_install_version() {
  local choice answer
  clear_screen
  printf '%b\n' "${C_CYAN}${C_BOLD}╭────────────────────────────────────────────╮${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}│${C_RESET}              ${C_WHITE}${C_BOLD}安装 Snell 核心${C_RESET}               ${C_CYAN}${C_BOLD}│${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD}╰────────────────────────────────────────────╯${C_RESET}"
  section_title "选择协议版本"
  menu_option 1 "Snell v5  ·  稳定版 ${SNELL_V5_VERSION}"
  menu_option 2 "Snell v6  ·  Beta ${SNELL_V6_VERSION}" accent
  menu_option q "返回 Snell 管理" back
  echo
  read -r -p "请选择: " choice
  case "$choice" in
    1) use_instance v5; do_install ;;
    2)
      warn "Snell v6 当前仍为 Beta，服务端与客户端可能发生不兼容变更。"
      warn "请确保 Surge 客户端同步更新到支持 ${SNELL_V6_VERSION} 的版本。"
      read -r -p "确认安装 Snell v6 Beta? [y/N] " answer
      if [[ "$answer" =~ ^[yY]$ ]]; then use_instance v6; do_install; else yellow "已取消。"; fi
      ;;
    0|q|Q) return 0 ;;
    *) yellow "无效选择。" ;;
  esac
}

snell_menu() {
  local choice detected answer
  local -a protocols=()
  while true; do
    mapfile -t protocols < <(snell_present_protocols)
    if [ "${#protocols[@]}" -eq 1 ]; then
      use_instance "${protocols[0]}"
      instance_menu
      return
    fi
    clear_screen
    snell_panel_header
    section_title "Snell 管理"
    if [ "${#protocols[@]}" -eq 0 ]; then
      menu_option 1 "安装 Snell" accent
      legacy_has_files && menu_option 2 "迁移旧版单实例"
    else
      warn "检测到 v5 与 v6 同时存在，以下版本选择仅用于兼容现有双实例。"
      menu_option 1 "管理现有 Snell v5"
      menu_option 2 "管理现有 Snell v6 Beta"
      legacy_has_files && menu_option 3 "迁移旧版单实例"
    fi
    menu_option q "返回主菜单" back
    echo
    read -r -p "请选择: " choice
    if [ "${#protocols[@]}" -eq 0 ]; then
      case "$choice" in
        1) choose_snell_install_version || true; pause_screen ;;
        2)
          if ! legacy_has_files; then yellow "无效选择。"; pause_screen; continue; fi
          detected="$(legacy_protocol 2>/dev/null || true)"
          if [ -z "$detected" ]; then read -r -p "无法自动识别版本，请输入 v5 或 v6: " detected; fi
          read -r -p "将旧实例迁移为 ${detected:-未知} 独立实例? [y/N] " answer
          if [[ "$answer" =~ ^[yY]$ ]]; then migrate_legacy "$detected" || true; else yellow "已取消。"; fi
          pause_screen
          ;;
        0|q|Q) return 0 ;;
        *) yellow "无效选择。"; pause_screen ;;
      esac
      continue
    fi
    case "$choice" in
      1) use_instance v5; instance_menu ;;
      2) use_instance v6; instance_menu ;;
      3)
        if ! legacy_has_files; then yellow "无效选择。"; pause_screen; continue; fi
        detected="$(legacy_protocol 2>/dev/null || true)"
        if [ -z "$detected" ]; then read -r -p "无法自动识别版本，请输入 v5 或 v6: " detected; fi
        read -r -p "将旧实例迁移为 ${detected:-未知} 独立实例? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then migrate_legacy "$detected" || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      0|q|Q) return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

menu() {
  local choice answer
  need_root
  [ -t 0 ] || { red "交互式面板需要在终端中运行。"; return 1; }
  if ! register_short_command true; then
    echo
    warn "管理面板仍可继续使用；请处理上面的短命令冲突后运行 register-command。"
    pause_screen
  fi
  while true; do
    clear_screen
    main_panel_header
    section_title "主菜单"
    menu_option 1 "Snell 管理"
    menu_option 2 "Xray 管理"
    menu_option 3 "检查面板更新" accent
    menu_option q "退出" back
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) snell_menu ;;
      2) xray_menu ;;
      3)
        read -r -p "确认从官方仓库检查并升级管理面板? [y/N] " answer
        if [[ "$answer" =~ ^[yY]$ ]]; then update_manager || true; else yellow "已取消。"; fi
        pause_screen
        ;;
      0|q|Q) echo "已退出。"; return 0 ;;
      *) yellow "无效选择。"; pause_screen ;;
    esac
  done
}

xray_usage() {
  cat <<'EOF'
Xray 核心管理

用法:
  snell xray <命令> [参数]

命令:
  manage                     打开 Xray 交互面板
  status                     查看核心、配置和服务状态
  latest                     查询 GitHub 最新稳定版本
  install [版本]             安装或修复 Xray；省略版本时安装最新版
  update [版本]              更新 Xray；省略版本时更新到最新版
  test                       校验当前 config.json
  start|stop|restart         控制 Xray 服务
  enable|disable             控制开机自启
  logs [行数]                查看最近日志（默认 100 行）
  logs-follow                实时跟踪日志
  inbounds                   列出面板托管的入站
  reality-add <SNI> [端口] [用户]
                             添加 VLESS TCP REALITY Vision 入站
  reality-edit <ID> <SNI> <端口>
                             修改托管入站的 SNI 和端口
  reality-client <ID> [地址] 输出 VLESS 链接和 Mihomo 配置
  reality-delete <ID>        删除托管入站及其用户
  user-add <ID> <用户>       向托管入站添加用户
  user-delete <ID> <UUID>    从托管入站删除用户
  uninstall                 卸载核心和服务，保留 config.json
EOF
}

usage() {
  cat <<'EOF'
多核心代理安装与配置管理

用法:
  snell [v5|v6] [命令] [参数]
  snell xray <命令> [参数]

通用命令:
  menu                       打开统一交互面板（默认）
  xray <命令>                管理 Xray 核心
  status-all                 查看 Snell v5 与 v6 概览
  register-command           注册 / 更新 snell 短命令
  self-update                检查并升级管理面板
  help                       显示帮助

Snell 命令:
  manage                     打开所选版本的实例面板
  migrate [v5|v6]            将旧 snell.service 迁移为独立实例
  install [端口]             安装或重装所选实例；交互时可指定端口
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
  update [版本]              更新 Snell 内核（默认使用脚本内版本）

可用环境变量:
  SNELL_PROTOCOL, SNELL_VERSION, SNELL_V5_VERSION, SNELL_V6_VERSION,
  SNELL_PORT, SNELL_MODE, SNELL_IPV6, DOWNLOAD_BASE, SNELL_COMMAND_PATH,
  SNELL_MANAGER_URL, XRAY_VERSION, XRAY_RELEASE_API, XRAY_DOWNLOAD_BASE,
  XRAY_BIN_PATH, XRAY_CONFIG_PATH, XRAY_ASSET_DIR, XRAY_LOG_DIR,
  XRAY_SERVICE_PATH, XRAY_BACKUP_DIR, NO_COLOR

示例:
  snell v5 install [端口]
  snell v6 install [端口]
  snell status-all
  snell xray install
  snell xray status
  snell self-update
  snell migrate
  snell v5 client snell.example.com
EOF
}

if [ "${1:-}" = "xray" ]; then
  shift
  case "${1:-manage}" in
    manage|menu) xray_menu ;;
    status) show_xray_status ;;
    latest) xray_latest_version ;;
    install) install_xray_core "${2:-}" ;;
    update)
      xray_is_installed || { red "Xray 尚未完整安装，请先运行: snell xray install"; exit 1; }
      install_xray_core "${2:-}"
      ;;
    test)
      if xray_config_is_valid; then success "Xray 配置有效。"; else red "Xray 配置校验失败。"; exit 1; fi
      ;;
    start|stop|restart|enable|disable) xray_service_action "$1" ;;
    logs) show_xray_logs "${2:-100}" ;;
    logs-follow) follow_xray_logs ;;
    inbounds) list_xray_managed_inbounds ;;
    reality-add)
      [ -n "${2:-}" ] || { red "用法: snell xray reality-add <SNI> [端口] [用户]"; exit 1; }
      add_xray_reality_inbound "$2" "${3:-}" "${4:-user1}"
      ;;
    reality-edit)
      if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
        red "用法: snell xray reality-edit <ID> <SNI> <端口>"; exit 1;
      fi
      edit_xray_reality_inbound "$2" "$3" "$4"
      ;;
    reality-client)
      [ -n "${2:-}" ] || { red "用法: snell xray reality-client <ID> [服务器地址]"; exit 1; }
      show_xray_reality_clients "$2" "${3:-}"
      ;;
    reality-delete)
      [ -n "${2:-}" ] || { red "用法: snell xray reality-delete <ID>"; exit 1; }
      delete_xray_reality_inbound "$2"
      ;;
    user-add)
      if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then red "用法: snell xray user-add <ID> <用户>"; exit 1; fi
      add_xray_reality_user "$2" "$3"
      ;;
    user-delete)
      if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then red "用法: snell xray user-delete <ID> <UUID>"; exit 1; fi
      delete_xray_reality_user "$2" "$3"
      ;;
    uninstall) uninstall_xray_core ;;
    help|-h|--help) xray_usage ;;
    *) red "未知 Xray 命令: $1"; echo; xray_usage; exit 1 ;;
  esac
  exit
fi

if [ "${1:-}" = "v5" ] || [ "${1:-}" = "v6" ]; then
  use_instance "$1"
  shift
fi

case "${1:-menu}" in
  install)      do_install "${2:-}" ;;
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
