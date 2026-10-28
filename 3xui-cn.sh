#!/usr/bin/env bash
# 3X-UI 中文安装向导 V1.0 - 非官方封装，调用 MHSanaei/3x-ui 官方脚本
set -uo pipefail
export LC_ALL=C.UTF-8
OFFICIAL='https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh'
GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; BLUE='\033[36m'; RESET='\033[0m'
ok(){ printf "${GREEN}✔ %s${RESET}\n" "$*"; }
warn(){ printf "${YELLOW}提示：%s${RESET}\n" "$*"; }
err(){ printf "${RED}错误：%s${RESET}\n" "$*" >&2; }
pause(){ printf '\n'; read -r -p '按回车返回菜单...' _ || true; }
ask(){ local prompt="$1" default="$2" answer; read -r -p "$prompt [$default]：" answer || return 1; REPLY="${answer:-$default}"; }
confirm(){ local a; read -r -p "$1（输入 YES 确认）：" a || return 1; [[ "$a" == YES ]]; }
installed(){ [[ -x /usr/local/x-ui/x-ui ]] && command -v x-ui >/dev/null 2>&1; }
status(){ if installed; then if systemctl is-active --quiet x-ui; then ok '3X-UI 已安装，服务运行中'; else warn '3X-UI 已安装，但服务未运行'; fi; else warn '尚未检测到官方 3X-UI 安装'; fi; }
check_env(){
 [[ ${EUID:-$(id -u)} -eq 0 ]] || { err '请使用 root 账号运行，或使用 sudo bash 3xui-cn.sh'; return 1; }
 command -v systemctl >/dev/null || { err '当前系统没有 systemd；V1 仅支持常规 systemd VPS'; return 1; }
 [[ -r /etc/os-release ]] || { err '无法识别系统'; return 1; }
 . /etc/os-release
 case "$ID" in debian|ubuntu) ;; *) err "V1 暂只支持 Debian/Ubuntu，当前：$ID"; return 1;; esac
 case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) err '当前 CPU 架构暂未纳入 V1 测试范围'; return 1;; esac
 command -v curl >/dev/null || { err '缺少 curl，请先安装：apt-get update && apt-get install -y curl'; return 1; }
 command -v openssl >/dev/null || { err '缺少 openssl，请先安装：apt-get install -y openssl'; return 1; }
 ok "系统：${PRETTY_NAME:-$ID} / $(uname -m)"
 local kb; kb=$(awk '/MemTotal:/{print $2}' /proc/meminfo)
 if [[ "$kb" =~ ^[0-9]+$ ]] && ((kb<524288)); then warn '内存低于 512MiB，可能无法稳定安装或运行；建议至少 1GiB'; fi
}
port_busy(){ if command -v ss >/dev/null; then ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$1$"; else return 1; fi; }
rand(){ openssl rand -hex "$1"; }
install_panel(){
 check_env || return 1
 if installed; then warn '已安装 3X-UI，为避免覆盖现有设置，本向导拒绝重复安装。请使用管理菜单。'; return 1; fi
 printf '\n【步骤 1/5】安装说明\n'
 echo '将下载并运行 MHSanaei/3x-ui 官方安装程序。'
 echo '官方程序可能安装系统依赖、修改 systemd 服务并下载面板程序。'
 echo '本向导不会删除其他代理程序，也不会自动修改防火墙。'
 echo 'V1 使用 SQLite；不支持 PostgreSQL 和自定义证书导入。'
 confirm '是否继续' || { warn '已取消'; return 0; }
 printf '\n【步骤 2/5】选择面板端口\n'
 echo '面板端口是浏览器访问后台的端口，不是代理节点端口。'
 local port
 while :; do
  ask '请输入面板端口（1024～65535）' '2053' || return 1; port="$REPLY"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || ((10#$port<1024 || 10#$port>65535)); then err '端口必须是 1024～65535 的整数'; continue; fi
  port=$((10#$port))
  if port_busy "$port"; then err "端口 $port 已被占用，请换一个"; continue; fi
  break
 done
 printf '\n【步骤 3/5】登录信息\n'
 echo '为安全起见，自动生成随机管理员用户名、密码和隐藏访问路径。'
 echo '安装成功后请妥善保存，勿将截图或日志公开。'
 local username password path
 username="admin$(rand 4)"; password="$(rand 16)"; path="$(rand 12)"
 printf '\n【步骤 4/5】HTTPS 证书\n'
 echo '推荐使用自己的域名申请免费 HTTPS 证书。'
 echo '需要：域名 A 记录直指本 VPS 公网 IPv4，外部 TCP 80 能访问本机 80。'
 echo '如果是 NAT VPS、80 端口被占用、CDN 橙云代理或 DNS 尚未生效，可能申请失败。'
 echo 'V1 为避免明文暴露管理员密码，不提供公网 HTTP 无证书安装选项。'
 local domain
 while :; do
  read -r -p '请输入已解析到本机的域名（不含 https://）：' domain || return 1
  if [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then break; fi
  err '域名格式不正确，请重新输入'
 done
 if port_busy 80; then err '本机 TCP 80 已被占用，证书签发可能失败；请先处理后再安装。'; return 1; fi
 printf '\n【步骤 5/5】确认安装\n'
 printf '面板端口：%s\n证书域名：%s\n数据库：SQLite\n' "$port" "$domain"
 echo '注意：证书是否成功取决于域名解析及公网 80 端口是否可达。'
 confirm '确认开始安装' || { warn '已取消'; return 0; }
 local tmp log rc=0
 tmp=$(mktemp /tmp/3xui-official.XXXXXX.sh) || return 1
 log=$(mktemp /tmp/3xui-install.XXXXXX.log) || { rm -f "$tmp"; return 1; }
 chmod 600 "$tmp" "$log"
 echo '正在从 GitHub 下载官方安装程序...'
 if ! curl -fLSs --connect-timeout 10 --max-time 90 "$OFFICIAL" -o "$tmp"; then err '官方脚本下载失败，检查 GitHub 网络连接'; rm -f "$tmp" "$log"; return 1; fi
 if ! bash -n "$tmp"; then err '官方脚本语法检查失败，停止执行'; rm -f "$tmp" "$log"; return 1; fi
 echo '开始安装。官方英文安装输出将保存到仅 root 可读的日志，屏幕只显示中文阶段说明。'
 echo '正在安装系统依赖、3X-UI 程序并尝试申请 HTTPS 证书，请耐心等待...'
 XUI_NONINTERACTIVE=1 XUI_DB_TYPE=sqlite XUI_USERNAME="$username" XUI_PASSWORD="$password" \
 XUI_WEB_BASE_PATH="$path" XUI_PANEL_PORT="$port" XUI_SSL_MODE=domain XUI_DOMAIN="$domain" \
 XUI_ENABLE_FAIL2BAN=false bash "$tmp" >"$log" 2>&1 || rc=$?
 rm -f "$tmp"
 if ((rc!=0)); then err "官方安装程序返回错误码 $rc"; echo "日志文件：$log（仅 root 可读）"; echo '最后 12 行（可能含敏感信息，请勿直接公开）：'; tail -n 12 "$log" | sed -E 's/(Password:|API Token:|DSN:).*/\1 [已隐藏]/I'; return 1; fi
 if ! installed || ! systemctl is-active --quiet x-ui; then err '安装程序已退出，但未检测到运行中的面板服务，不能判定安装成功'; echo "诊断日志：$log"; return 1; fi
 local cert='/root/cert/'"$domain"'/fullchain.pem'
 if [[ ! -s "$cert" ]]; then err '面板程序已运行，但未检测到有效的 HTTPS 证书文件。请勿通过公网 HTTP 登录。'; echo "诊断日志：$log"; return 1; fi
 ok '面板服务已启动，且检测到证书文件（尚未验证浏览器可访问性）'
 printf '\n面板地址：https://%s:%s/%s\n管理员账号：%s\n管理员密码：%s\n' "$domain" "$port" "$path" "$username" "$password"
 echo '请立即保存以上信息；访问失败时检查云防火墙、安全组和 DNS。'
 echo "完整安装日志：$log（可能包含凭据，请勿公开）"
}
manage(){
 check_env || return 1
 installed || { err '尚未安装 3X-UI'; return 1; }
 case "$1" in
  start) systemctl start x-ui && ok '启动命令执行成功' || err '启动失败';;
  stop) confirm '确认停止面板服务？' && systemctl stop x-ui && ok '服务已停止';;
  restart) systemctl restart x-ui && ok '重启命令执行成功' || err '重启失败';;
  logs) journalctl -u x-ui -n 40 --no-pager;;
  official) echo '下面进入 3X-UI 官方管理菜单，部分提示可能为英文。'; x-ui;;
 esac
}
backup(){
 check_env || return 1; installed || { err '尚未安装'; return 1; }
 local src='/etc/x-ui/x-ui.db' dest='/root/3xui-backups' target
 [[ -f "$src" ]] || { err '找不到默认 SQLite 数据库；可能使用了自定义存储，V1 不支持自动备份'; return 1; }
 mkdir -p "$dest" && chmod 700 "$dest"
 target="$dest/x-ui-$(date +%Y%m%d-%H%M%S).db"
 # SQLite 在线备份应使用 SQLite backup API；避免直接复制运行中的数据库造成不一致。
 if ! command -v sqlite3 >/dev/null; then err '缺少 sqlite3，运行 apt-get install -y sqlite3 后再试'; return 1; fi
 if sqlite3 "$src" ".backup '$target'"; then chmod 600 "$target"; ok "备份成功：$target"; else err '数据库备份失败'; rm -f "$target"; fi
}
menu(){
 while :; do
  printf '\n\033[36m========== 3X-UI 中文安装向导 V1.0 ==========\033[0m\n'
  status
  cat <<'MENU'
  1. 中文引导安装（全新 VPS）
  2. 查看面板服务状态
  3. 启动面板
  4. 停止面板
  5. 重启面板
  6. 查看最近运行日志
  7. 备份 SQLite 数据库
  8. 进入官方 x-ui 管理菜单（更新、重置、卸载等）
  0. 退出
MENU
  local choice; read -r -p '请选择 [0-8]：' choice || break
  case "$choice" in
   1) install_panel; pause;;
   2) status; pause;;
   3) manage start; pause;;
   4) manage stop; pause;;
   5) manage restart; pause;;
   6) manage logs; pause;;
   7) backup; pause;;
   8) manage official; pause;;
   0) break;;
   *) warn '请输入 0～8';;
  esac
 done
}
menu
