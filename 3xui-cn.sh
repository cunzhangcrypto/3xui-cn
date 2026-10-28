#!/usr/bin/env bash
# 3X-UI 中文安装向导 | Web3村长 | https://cunzhangblog.com
set -Eeuo pipefail
umask 077
export DEBIAN_FRONTEND=noninteractive
OFFICIAL='https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh'
CONFIG_DIR='/etc/3xui-cn'
CONFIG_FILE="$CONFIG_DIR/access.conf"
LOG_DIR='/var/log/3xui-cn'
PANEL_PORT=2053
NETWORK_TYPE='public'
PUBLIC_HOST=''
DOMAIN=''
EXTERNAL_PORT=''
HTTPS_MODE='none'
WEB_PATH=''
PANEL_USER=''
PANEL_PASS=''

say(){ printf '%s\n' "$*"; }
info(){ printf '\033[36m%s\033[0m\n' "$*"; }
ok(){ printf '\033[32m✔ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m提示：%s\033[0m\n' "$*"; }
err(){ printf '\033[31m错误：%s\033[0m\n' "$*" >&2; }
require_root(){ if (( EUID != 0 )); then err '请以 root 身份运行：sudo bash 3xui-cn.sh'; exit 1; fi; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }
ask(){ local outvar="$1" prompt="$2" default="${3-}" value; read -r -p "$prompt" value || return 1; printf -v "$outvar" '%s' "${value:-$default}"; }
confirm(){ local v; ask v "$1 [Y/n]：" y || return 1; [[ "$v" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; }
wait_enter(){ local unused; read -r -p '按回车返回菜单...' unused || true; }
valid_port(){ [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
valid_domain(){ [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && "$1" == *.* && "$1" != *..* && ${#1} -le 253 ]]; }
valid_ipv4(){ local ip="$1" o; [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1; IFS=. read -r -a oct <<< "$ip"; for o in "${oct[@]}"; do (( 10#$o <= 255 )) || return 1; done; }
random_hex(){ if need_cmd openssl; then openssl rand -hex "$1"; else od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'; fi; }
installed(){ [[ -x /usr/local/x-ui/x-ui ]] || [[ -x /usr/bin/x-ui ]] || [[ -x /usr/local/bin/x-ui ]] || systemctl list-unit-files x-ui.service --no-legend 2>/dev/null | grep -q '^x-ui.service'; }
service_active(){ systemctl is-active --quiet x-ui 2>/dev/null; }
service_action(){ local action="$1"; if ! installed; then err '尚未安装 3X-UI'; return 1; fi; if systemctl "$action" x-ui; then ok "面板已执行：$action"; else err '操作失败，请查看运行日志'; fi; }
load_config(){ [[ -f "$CONFIG_FILE" ]] || return 0; local k v; while IFS='=' read -r k v; do case "$k" in NETWORK_TYPE) NETWORK_TYPE="$v";; PUBLIC_HOST) PUBLIC_HOST="$v";; DOMAIN) DOMAIN="$v";; EXTERNAL_PORT) EXTERNAL_PORT="$v";; PANEL_PORT) PANEL_PORT="$v";; HTTPS_MODE) HTTPS_MODE="$v";; WEB_PATH) WEB_PATH="$v";; esac; done < "$CONFIG_FILE"; }
save_config(){ install -d -m 700 "$CONFIG_DIR"; local tmp; tmp=$(mktemp "$CONFIG_DIR/.access.XXXXXX"); chmod 600 "$tmp"; printf 'NETWORK_TYPE=%s\nPUBLIC_HOST=%s\nDOMAIN=%s\nEXTERNAL_PORT=%s\nPANEL_PORT=%s\nHTTPS_MODE=%s\nWEB_PATH=%s\n' "$NETWORK_TYPE" "$PUBLIC_HOST" "$DOMAIN" "$EXTERNAL_PORT" "$PANEL_PORT" "$HTTPS_MODE" "$WEB_PATH" > "$tmp"; mv -f "$tmp" "$CONFIG_FILE"; }
public_ip(){ local ip=''; ip=$(curl -4fsS --connect-timeout 3 --max-time 6 https://api.ipify.org 2>/dev/null || true); if valid_ipv4 "$ip"; then printf '%s' "$ip"; fi; }
header(){ clear 2>/dev/null || true; say '========== 3X-UI 中文安装向导 =========='; say '       由 Web3村长 优化维护'; say '       仅供技术学习与交流'; say '       村长博客：https://cunzhangblog.com'; say '========================================'; say; }
configure_access(){
  local choice p host ext d
  say '【面板访问方式配置】'; say '1. 普通公网 VPS'; say '2. NAT VPS（共享 IPv4，需要外部端口映射）'; say '0. 返回'; ask choice '请选择 [1/2/0]：' 1 || return 1
  case "$choice" in 1) NETWORK_TYPE=public;; 2) NETWORK_TYPE=nat;; 0) return 0;; *) err '无效选择'; return 1;; esac
  ask p "面板内部端口 [默认 $PANEL_PORT]：" "$PANEL_PORT" || return 1
  valid_port "$p" || { err '内部端口无效'; return 1; }; PANEL_PORT="$p"
  if [[ "$NETWORK_TYPE" == nat ]]; then
    say 'NAT 外部端口由服务商分配，必须在服务商后台完成 TCP 转发。';
    ask ext '请输入 NAT 外部端口（暂未分配可留空）：' "${EXTERNAL_PORT:-}" || return 1
    if [[ -n "$ext" ]] && ! valid_port "$ext"; then err '外部端口无效'; return 1; fi
    EXTERNAL_PORT="$ext"
  else EXTERNAL_PORT="$PANEL_PORT"; fi
  say '1. 使用公网 IPv4'; say '2. 使用自定义域名'; say '3. 暂不设置';
  ask choice '请选择访问地址类型 [1/2/3]：' 1 || return 1
  case "$choice" in
    1) ask host '公网 IPv4（留空则尝试自动检测）：' "${PUBLIC_HOST:-}" || return 1; [[ -n "$host" ]] || host=$(public_ip); if [[ -n "$host" ]] && ! valid_ipv4 "$host"; then err 'IPv4 格式不正确'; return 1; fi; PUBLIC_HOST="$host"; DOMAIN='';;
    2) ask d '请输入域名（不含 https://）：' "${DOMAIN:-}" || return 1; valid_domain "$d" || { err '域名格式不正确'; return 1; }; DOMAIN="${d,,}"; PUBLIC_HOST='';;
    3) PUBLIC_HOST=''; DOMAIN='';;
    *) err '无效选择'; return 1;;
  esac
  save_config; ok '访问方式已保存（仅记录信息，不会自动创建 NAT 转发或 DNS 记录）';
}
show_address(){
  local host port scheme path
  host="${DOMAIN:-$PUBLIC_HOST}"; port="${EXTERNAL_PORT:-}"; path="${WEB_PATH:-/}"
  [[ "$path" == /* ]] || path="/$path"; [[ "$path" == */ ]] || path="$path/"
  say '========== 面板访问地址 ==========';
  if [[ -z "$host" ]]; then warn '尚未设置公网 IPv4 或域名，请先进入访问方式配置。'; else
    if [[ "$NETWORK_TYPE" == nat && -z "$port" ]]; then warn 'NAT 外部端口未配置，暂时无法生成公网访问地址。'; else
      [[ -n "$port" ]] || port="$PANEL_PORT"
      if [[ "$HTTPS_MODE" == verified ]]; then scheme=https; else scheme=http; fi
      say "候选地址：$scheme://$host:$port$path"
      warn '这是根据配置生成的候选地址，不代表公网连通性已验证。'
      if [[ "$HTTPS_MODE" != verified ]]; then warn '当前未确认 HTTPS，禁止通过公网 HTTP 输入管理员密码。'; fi
    fi
  fi
  say; say 'SSH 隧道（安全访问方式）：'; say "  ssh -N -L ${PANEL_PORT}:127.0.0.1:${PANEL_PORT} root@服务器SSH地址 -p SSH外部端口";
  say "  本机浏览器：http://127.0.0.1:${PANEL_PORT}${path}";
  say '注意：如果面板已启用 HTTPS，本机隧道也应使用 https://，浏览器可能提示域名不匹配。';
}
install_dependencies(){
  if need_cmd apt-get; then apt-get update -y && apt-get install -y curl ca-certificates openssl tar gzip;
  elif need_cmd dnf; then dnf install -y curl ca-certificates openssl tar gzip;
  elif need_cmd yum; then yum install -y curl ca-certificates openssl tar gzip;
  elif need_cmd apk; then apk add curl ca-certificates openssl tar gzip;
  else err '无法自动安装依赖，请先安装 curl、openssl、ca-certificates'; return 1; fi
}
new_install(){
  if installed; then warn '检测到已安装的 3X-UI。为保护现有数据库和节点，禁止重复全新安装。'; return 0; fi
  say '【全新安装】'; say '1. 开始设置'; say '0. 返回'; local c
  ask c '请选择 [1/0]：' 1 || return 1; [[ "$c" == 1 ]] || return 0
  configure_access || return 1
  PANEL_USER="admin$(random_hex 4)"; PANEL_PASS="$(random_hex 16)"; WEB_PATH="/$(random_hex 12)";
  say; say '【HTTPS 证书】'; say '1. 安装后再配置 HTTPS（推荐 NAT VPS）'; say '2. 使用官方安装程序的域名证书流程（需要满足官方验证条件）';
  ask c '请选择 [1/2，默认 1]：' 1 || return 1
  case "$c" in 1) HTTPS_MODE=none;; 2) HTTPS_MODE=official;; *) err '无效选择'; return 1;; esac
