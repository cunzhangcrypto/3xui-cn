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
  case "$c" in 1) HTTPS_MODE=none;; 2) HTTPS_MODE=official; if [[ -z "$DOMAIN" ]]; then err '官方域名证书模式必须先填写域名。NAT VPS 建议选择 1，安装后使用 Cloudflare DNS 申请证书。'; return 1; fi;; *) err '无效选择'; return 1;; esac
  say; say '========== 安装前确认 ==========';
  say "网络类型：$NETWORK_TYPE"; say "内部端口：$PANEL_PORT"; say "NAT 外部端口：${EXTERNAL_PORT:-未设置}"; say "域名：${DOMAIN:-未设置}";
  say "HTTPS：$HTTPS_MODE"; say '1. 确认安装'; say '2. 返回主菜单';
  ask c '请选择 [1/2]：' 2 || return 1; [[ "$c" == 1 ]] || return 0
  install -d -m 700 "$LOG_DIR"
  local installer log rc=0
  installer=$(mktemp /tmp/3xui-official.XXXXXX.sh)
  log=$(mktemp "$LOG_DIR/install.XXXXXX.log")
  chmod 600 "$installer" "$log"
  if ! need_cmd curl; then err '系统缺少 curl，请先安装 curl'; rm -f "$installer"; return 1; fi
  info '正在下载 3X-UI 官方安装脚本...'
  if ! curl -fLsS --retry 2 --connect-timeout 10 --max-time 90 "$OFFICIAL" -o "$installer"; then err '下载失败，请检查网络'; rm -f "$installer"; return 1; fi
  if ! bash -n "$installer"; then err '官方脚本语法校验失败，已停止'; rm -f "$installer"; return 1; fi
  info '正在安装依赖与 3X-UI，请稍候...'
  install_dependencies > "$log" 2>&1 || { err "依赖安装失败，日志：$log"; rm -f "$installer"; return 1; }
  XUI_NONINTERACTIVE=1 XUI_DB_TYPE=sqlite XUI_USERNAME="$PANEL_USER" XUI_PASSWORD="$PANEL_PASS" \
  XUI_WEB_BASE_PATH="$WEB_PATH" XUI_PANEL_PORT="$PANEL_PORT" \
  XUI_SSL_MODE="$( [[ "$HTTPS_MODE" == official ]] && printf domain || printf none )" \
  XUI_DOMAIN="$DOMAIN" XUI_ENABLE_FAIL2BAN=false bash "$installer" >> "$log" 2>&1 || rc=$?
  rm -f "$installer"
  if (( rc != 0 )); then err "官方安装脚本执行失败（退出码 $rc），日志：$log"; return 1; fi
  if ! installed || ! service_active; then err "安装程序已结束，但面板服务未确认运行；请查看日志：$log"; return 1; fi
  if [[ "$HTTPS_MODE" == official ]]; then HTTPS_MODE=none; warn '请在证书管理中确认 HTTPS 是否真正启用，未验证前不标记成功。'; fi
  save_config
  ok '3X-UI 面板服务已启动'; say '========== 安装结果 ==========';
  say "管理员账号：$PANEL_USER"; say "管理员密码：$PANEL_PASS"; say "访问路径：$WEB_PATH";
  warn '请立即离线保存密码和路径，避免截图或公开。';
  show_address; say "安装日志（仅 root 可读）：$log";
}
show_status(){ if installed; then if service_active; then ok '3X-UI 已安装，服务运行中'; else warn '3X-UI 已安装，服务未运行'; fi; else warn '3X-UI 尚未安装'; fi; }
show_logs(){ if need_cmd journalctl; then journalctl -u x-ui -n 70 --no-pager || true; else err '系统没有 journalctl'; fi; }
backup_db(){
  local db='' dest
  for db in /etc/x-ui/x-ui.db /usr/local/x-ui/x-ui.db; do [[ -f "$db" ]] && break; done
  [[ -f "$db" ]] || { err '未找到 SQLite 数据库，请检查安装目录'; return 1; }
  install -d -m 700 /root/3xui-backups
  dest="/root/3xui-backups/x-ui-$(date -u +%Y%m%d-%H%M%S).db"
  if need_cmd sqlite3; then sqlite3 "$db" ".backup '$dest'" || return 1; else cp -p "$db" "$dest" || return 1; warn '未安装 sqlite3，使用文件复制备份；高并发写入时建议改用 SQLite 在线备份。'; fi
  chmod 600 "$dest"; ok "数据库备份已保存：$dest"
}
manage_credentials(){
  installed || { err '尚未安装'; return 1; }
  say '【修改管理员账号与密码】'; warn '优先使用官方管理命令，避免直接修改数据库。';
  if confirm '是否修改账号和密码？'; then
    local u p
    u=$(prompt_user) || return 1
    p=$(prompt_password) || return 1
    if x-ui setting -username "$u" -password "$p"; then systemctl restart x-ui; ok '账号密码已提交更新'; else err '修改失败，请进入官方菜单第 7 项操作'; fi
    unset p
  fi
}
prompt_user(){ local u; ask u '请输入新管理员账号：' '' || return 1; [[ "$u" =~ ^[a-zA-Z0-9_-]{4,40}$ ]] || { err '账号必须为 4-40 位字母数字下划线或连字符'; return 1; }; printf '%s' "$u"; }
prompt_password(){ local p; read -rs -p '请输入新管理员密码（至少 12 位）：' p; printf '\n' >&2; (( ${#p} >= 12 )) || { err '密码长度不足'; return 1; }; printf '%s' "$p"; }
manage_path_port(){
  installed || { err '尚未安装'; return 1; }
  say '【修改面板端口与访问路径】'; say '1. 修改面板内部端口'; say '2. 修改访问路径'; say '0. 返回'; local c p
  ask c '请选择 [1/2/0]：' 0 || return 1
  case "$c" in
    1) ask p '新内部端口：' "$PANEL_PORT" || return 1; valid_port "$p" || { err '端口无效'; return 1; }; if x-ui setting -port "$p"; then PANEL_PORT="$p"; [[ "$NETWORK_TYPE" == public ]] && EXTERNAL_PORT="$p"; save_config; systemctl restart x-ui; ok '面板端口已更新'; else err '官方命令执行失败'; fi;;
    2) ask p '新访问路径（以 / 开头）：' "$WEB_PATH" || return 1; [[ "$p" =~ ^/[a-zA-Z0-9/_-]{6,128}$ ]] || { err '访问路径格式不正确'; return 1; }; if x-ui setting -webBasePath "$p"; then WEB_PATH="$p"; save_config; systemctl restart x-ui; ok '访问路径已更新'; else err '官方命令执行失败'; fi;;
    0) return 0;; *) err '无效选择';;
  esac
}
ssl_paths(){ local d="$1"; CERT_DIR="/root/cert/$d"; CERT_FULL="$CERT_DIR/fullchain.pem"; CERT_KEY="$CERT_DIR/privkey.pem"; }
ssl_apply(){
  local d="$1"; ssl_paths "$d"
  [[ -s "$CERT_FULL" && -s "$CERT_KEY" ]] || { err '证书或私钥文件不存在'; return 1; }
  if ! openssl x509 -in "$CERT_FULL" -noout -checkend 86400 >/dev/null 2>&1; then err '证书无效或即将过期'; return 1; fi
  if ! x-ui setting -webCert "$CERT_FULL" -webCertKey "$CERT_KEY"; then err '自动绑定证书失败，请使用官方菜单 20 → 5 手动绑定'; return 1; fi
  systemctl restart x-ui || { err '面板重启失败'; return 1; }
  DOMAIN="$d"; HTTPS_MODE=verified; save_config; ok '证书已设置并重启面板';
  warn 'HTTPS 已在面板配置，但公网 DNS、NAT 转发及实际连接仍需单独验证。'
}
ssl_cloudflare(){
  local d token account zone acme
  say '【Cloudflare DNS 验证申请证书】'; say '无需公网 80 端口。域名必须属于你有 DNS 编辑权限的 Cloudflare 区域。'
  ask d '请输入证书域名：' "${DOMAIN:-}" || return 1
  valid_domain "$d" || { err '域名格式不正确'; return 1; }
  read -rs -p '输入 Cloudflare API Token（输入不回显）：' token || return 1; printf '\n'
  [[ -n "$token" ]] || { err 'Token 不能为空'; return 1; }
  ask zone 'Cloudflare Zone ID（可留空，由 acme.sh 自动识别）：' '' || return 1
  ask account 'Cloudflare Account ID（可留空）：' '' || return 1
  if ! need_cmd curl || ! need_cmd openssl; then err '缺少 curl 或 openssl'; return 1; fi
  acme='/root/.acme.sh/acme.sh'
  if [[ ! -x "$acme" ]]; then
    say '检测到尚未安装 acme.sh。';
    if ! confirm '是否从 acme.sh 官方站点下载安装脚本？'; then return 1; fi
    local f; f=$(mktemp /tmp/acme-install.XXXXXX.sh)
    if ! curl -fLsS --max-time 90 https://get.acme.sh -o "$f"; then err 'acme.sh 下载失败'; rm -f "$f"; return 1; fi
    if ! bash -n "$f"; then err 'acme.sh 安装脚本语法异常'; rm -f "$f"; return 1; fi
    bash "$f" || { rm -f "$f"; err 'acme.sh 安装失败'; return 1; }; rm -f "$f"
  fi
  [[ -x "$acme" ]] || { err 'acme.sh 不可执行'; return 1; }
  info '正在使用 Cloudflare DNS 验证申请证书...'
  local rc=0
  CF_Token="$token" CF_Zone_ID="$zone" CF_Account_ID="$account" "$acme" --issue --dns dns_cf -d "$d" --keylength ec-256 --server letsencrypt || rc=$?
  unset token
  (( rc == 0 )) || { err '申请失败，请检查 Token 权限、域名所属 Zone 和日志'; return 1; }
  ssl_paths "$d"; install -d -m 700 "$CERT_DIR"
  "$acme" --install-cert --ecc -d "$d" --fullchain-file "$CERT_FULL" --key-file "$CERT_KEY" --reloadcmd 'x-ui restart' || { err '证书安装失败'; return 1; }
  chmod 600 "$CERT_KEY"; chmod 644 "$CERT_FULL"
  ok '证书签发成功，自动续期配置已提交';
  if confirm '是否立即把此证书应用到 3X-UI 面板？'; then ssl_apply "$d"; else DOMAIN="$d"; save_config; fi
}
ssl_menu(){
  local c d
  say '【HTTPS / SSL 证书管理】'; say '1. 使用 Cloudflare DNS 申请证书（全中文流程）'; say '2. 绑定已经存在的证书'; say '3. 查看证书状态'; say '4. 官方 SSL 管理菜单（备用，部分英文）'; say '0. 返回';
  ask c '请选择 [0-4]：' 0 || return 1
  case "$c" in
    1) ssl_cloudflare;;
    2) ask d '证书域名：' "${DOMAIN:-}" || return 1; valid_domain "$d" || { err '域名无效'; return 1; }; ssl_apply "$d";;
    3) if [[ -n "$DOMAIN" ]]; then ssl_paths "$DOMAIN"; if [[ -f "$CERT_FULL" ]]; then openssl x509 -in "$CERT_FULL" -noout -subject -dates; else warn '未找到该域名证书'; fi; else warn '尚未设置域名'; fi;;
    4) x-ui && true;;
    0) return 0;; *) err '无效选择';;
  esac
}
nat_guide(){ say '【NAT VPS 配置指引】'; say '1. 在 3X-UI 内填写面板内部监听端口（例如 2053）。'; say '2. 在服务商 NAT 后台创建 TCP 外部端口 → 内部端口映射。'; say '3. 客户端连接时使用服务商分配的外部端口。'; say '4. 每条通过共享 IPv4 访问的入站通常需要独立端口映射。'; say '5. 域名 A 记录指向公网 IPv4；DNS 解析不等于端口映射。'; say '6. 未配置 HTTPS 时不要通过公网 HTTP 登录面板。'; say '7. 独立 IPv6 直连不依赖 IPv4 NAT，但需检查 IPv6 防火墙和监听。'; }
sys_info(){ uname -a; sed -n '1,8p' /etc/os-release 2>/dev/null || true; free -h 2>/dev/null || true; df -h / 2>/dev/null || true; }
update_panel(){ installed || { err '尚未安装面板'; return 1; }; warn '升级前建议先备份数据库。'; if confirm '是否进入官方更新流程？'; then x-ui; fi; }
uninstall_panel(){ warn '卸载会影响现有面板和节点。'; if confirm '是否进入官方菜单自行确认卸载？'; then x-ui; fi; }
main(){
  require_root; load_config
  while :; do
    header; show_status; say
    say '  1. 全新安装 3X-UI'; say '  2. 查看面板状态'; say '  3. 启动面板'; say '  4. 停止面板'; say '  5. 重启面板'; say '  6. 查看运行日志'; say '  7. 备份面板数据库'; say
    say '  8. 修改管理员账号与密码'; say '  9. 修改面板端口与访问路径'; say ' 10. 配置 HTTPS / SSL 证书'; say ' 11. 查看面板访问地址'; say ' 12. NAT VPS 端口配置指引'; say ' 13. 配置面板访问方式'; say
    say ' 14. 更新 3X-UI'; say ' 15. 查看系统与资源信息'; say ' 16. 进入官方管理菜单'; say ' 17. 卸载 3X-UI'; say; say '  0. 退出'; say
    local c; ask c '请选择 [0-17]：' '' || break
    case "$c" in
      1) new_install;; 2) show_status;; 3) service_action start;; 4) service_action stop;; 5) service_action restart;; 6) show_logs;; 7) backup_db;;
      8) manage_credentials;; 9) manage_path_port;; 10) ssl_menu;; 11) show_address;; 12) nat_guide;; 13) configure_access;;
      14) update_panel;; 15) sys_info;; 16) if installed; then x-ui; else err '尚未安装 3X-UI'; fi;; 17) uninstall_panel;;
      0) say '已退出。'; break;; *) err '无效选择';;
    esac
    say; wait_enter
  done
}
main "$@"
