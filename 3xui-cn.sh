
#!/usr/bin/env bash
# 3X-UI 中文安装向导 V1.1
# 非官方中文封装，调用 MHSanaei/3x-ui 官方安装程序

set -uo pipefail
export LC_ALL=C.UTF-8

OFFICIAL="https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[36m'
RESET='\033[0m'

ok() {
    printf "${GREEN}✔ %s${RESET}\n" "$*"
}

warn() {
    printf "${YELLOW}提示：%s${RESET}\n" "$*"
}

err() {
    printf "${RED}错误：%s${RESET}\n" "$*" >&2
}

pause() {
    echo
    read -r -p "按回车返回菜单..." _ || true
}

ask() {
    local prompt="$1"
    local default="$2"
    local answer

    read -r -p "$prompt [$default]：" answer || return 1
    REPLY="${answer:-$default}"
}

# 标准 Linux y/n 确认
confirm() {
    local answer

    while true; do
        read -r -p "$1 [Y/n]：" answer || return 1

        case "$answer" in
            y|Y|yes|YES|Yes|"")
                return 0
                ;;
            n|N|no|NO|No)
                return 1
                ;;
            *)
                warn "请输入 y 或 n，直接回车默认继续"
                ;;
        esac
    done
}

installed() {
    [[ -x /usr/local/x-ui/x-ui ]] &&
    command -v x-ui >/dev/null 2>&1
}

status() {
    if installed; then
        if systemctl is-active --quiet x-ui; then
            ok "3X-UI 已安装，服务运行中"
        else
            warn "3X-UI 已安装，但服务未运行"
        fi
    else
        warn "尚未检测到官方 3X-UI 安装"
    fi
}

check_env() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        err "请使用 root 账号运行"
        return 1
    fi

    if ! command -v systemctl >/dev/null; then
        err "当前系统没有 systemd"
        return 1
    fi

    if [[ ! -r /etc/os-release ]]; then
        err "无法识别当前系统"
        return 1
    fi

    . /etc/os-release

    case "$ID" in
        debian|ubuntu)
            ;;
        *)
            err "目前仅支持 Debian / Ubuntu"
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|aarch64|arm64)
            ;;
        *)
            err "当前 CPU 架构暂不支持"
            return 1
            ;;
    esac

    if ! command -v curl >/dev/null; then
        err "缺少 curl，请先安装 curl"
        return 1
    fi

    if ! command -v openssl >/dev/null; then
        err "缺少 openssl，请先安装 openssl"
        return 1
    fi

    ok "系统：${PRETTY_NAME:-$ID} / $(uname -m)"

    local kb
    kb=$(awk '/MemTotal:/{print $2}' /proc/meminfo)

    if [[ "$kb" =~ ^[0-9]+$ ]] && ((kb < 524288)); then
        warn "内存低于 512MiB，可能无法稳定运行"
        warn "建议至少使用 1GiB 内存的 VPS"
    fi
}

port_busy() {
    if command -v ss >/dev/null; then
        ss -H -ltn 2>/dev/null |
            awk '{print $4}' |
            grep -Eq "(^|:)$1$"
    else
        return 1
    fi
}

rand() {
    openssl rand -hex "$1"
}

install_panel() {
    check_env || return 1

    if installed; then
        warn "检测到已经安装 3X-UI"
        warn "为避免覆盖现有数据，请使用管理菜单"
        return 1
    fi

    echo
    echo "【步骤 1/5】安装说明"
    echo
    echo "即将安装 3X-UI 面板。"
    echo "安装过程中将自动下载官方程序及依赖。"
    echo "不会主动删除其他代理程序。"
    echo "不会自动修改 VPS 防火墙。"
    echo
    echo "是否继续安装？"

    if ! confirm "确认继续"; then
        warn "已取消安装"
        return 0
    fi

    echo
    echo "【步骤 2/5】选择面板端口"
    echo
    echo "面板端口用于访问 3X-UI 管理后台。"
    echo "它不是代理节点的端口。"
    echo
    echo "普通 VPS：检查防火墙和安全组。"
    echo "NAT VPS：需要按服务商规则配置端口转发。"
    echo

    local port

    while true; do
        ask "请输入面板内部端口（1024～65535）" "2053" || return 1
        port="$REPLY"

        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            err "请输入有效的数字端口"
            continue
        fi

        if ((10#$port < 1024 || 10#$port > 65535)); then
            err "端口范围必须是 1024～65535"
            continue
        fi

        port=$((10#$port))

        if port_busy "$port"; then
            err "端口 $port 已被占用，请更换"
            continue
        fi

        break
    done

    echo
    echo "【步骤 3/5】管理员登录信息"
    echo
    echo "为提高安全性，自动生成："
    echo "  - 随机管理员用户名"
    echo "  - 随机管理员密码"
    echo "  - 随机访问路径"
    echo
    echo "安装完成后会显示登录信息。"
    echo "请妥善保存，不要公开截图。"

    local username password path

    username="admin$(rand 4)"
    password="$(rand 16)"
    path="$(rand 12)"

    local sslmode=""
    local domain=""
    local choice=""

    # HTTPS 配置及最终确认循环
    while true; do

        echo
        echo "【步骤 4/5】HTTPS 证书配置"
        echo
        echo "HTTPS 可以加密面板管理连接。"
        echo
        echo "1. 使用域名自动申请 HTTPS 证书"
        echo "   需要公网 TCP 80 端口可访问"
        echo
        echo "2. 暂时跳过 HTTPS"
        echo "   适合 NAT VPS 先测试安装"
        echo "   后续可单独配置 HTTPS"
        echo
        echo "0. 取消安装"
        echo

        read -r -p "请选择 [1/2/0，默认 2]：" choice || return 1

        case "${choice:-2}" in

            1)
                sslmode="domain"

                while true; do
                    echo
                    read -r -p "请输入域名（输入 0 返回）：" domain || return 1

                    if [[ "$domain" == "0" ]]; then
                        break
                    fi

                    if [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
                        break
                    fi

                    err "域名格式不正确，请重新输入"
                done

                if [[ "$domain" == "0" ]]; then
                    continue
                fi

                if port_busy 80; then
                    err "本机 80 端口已被占用"
                    warn "可以返回选择跳过 HTTPS"
                    continue
                fi

                warn "请确认域名已正确解析"
                warn "并且公网 TCP 80 可以访问本机 80 端口"
                ;;

            2)
                sslmode="none"
                domain=""

                echo
                warn "已选择暂时跳过 HTTPS"
                echo "面板安装后将使用 HTTP。"
                echo "HTTP 不加密管理员登录信息。"
                echo "请勿直接将 HTTP 管理端口暴露到公网。"
                echo "建议通过 SSH 隧道访问，之后再配置 HTTPS。"
                ;;

            0)
                warn "已取消安装"
                return 0
                ;;

            *)
                err "请输入 1、2 或 0"
                continue
                ;;
        esac

        # 最终确认，可返回证书选择
        while true; do
            echo
            echo "【步骤 5/5】确认安装"
            echo
            echo "面板内部端口：$port"
            echo "数据库：SQLite"

            if [[ "$sslmode" == "none" ]]; then
                echo "HTTPS：暂时跳过"
            else
                echo "HTTPS：申请域名证书"
                echo "证书域名：$domain"
            fi

            echo
            echo "1. 确认开始安装"
            echo "2. 返回修改 HTTPS 选项"
            echo "0. 取消安装"
            echo

            read -r -p "请选择 [1/2/0，默认 1]：" choice || return 1

            case "${choice:-1}" in
                1)
                    choice="install"
                    break
                    ;;
                2)
                    choice="back"
                    break
                    ;;
                0)
                    warn "已取消安装"
                    return 0
                    ;;
                *)
                    err "请输入 1、2 或 0"
                    ;;
            esac
        done

        if [[ "$choice" == "install" ]]; then
            break
        fi
    done

    echo
    echo "========== 开始安装 =========="
    echo

    local tmp log rc=0

    tmp=$(mktemp /tmp/3xui-official.XXXXXX.sh) || return 1
    log=$(mktemp /tmp/3xui-install.XXXXXX.log) || {
        rm -f "$tmp"
        return 1
    }

    chmod 600 "$tmp" "$log"

    echo "正在下载官方安装脚本..."

    if ! curl -fLSs \
        --connect-timeout 10 \
        --max-time 90 \
        "$OFFICIAL" \
        -o "$tmp"; then

        err "官方安装脚本下载失败"
        rm -f "$tmp" "$log"
        return 1
    fi

    if ! bash -n "$tmp"; then
        err "官方安装脚本语法检查失败"
        rm -f "$tmp" "$log"
        return 1
    fi

    echo "官方脚本下载成功。"
    echo "正在安装系统依赖和 3X-UI 面板..."
    echo "安装日志将保存到仅 root 可读取的文件。"
    echo

    XUI_NONINTERACTIVE=1 \
    XUI_DB_TYPE=sqlite \
    XUI_USERNAME="$username" \
    XUI_PASSWORD="$password" \
    XUI_WEB_BASE_PATH="$path" \
    XUI_PANEL_PORT="$port" \
    XUI_SSL_MODE="$sslmode" \
    XUI_DOMAIN="$domain" \
    XUI_ENABLE_FAIL2BAN=false \
    bash "$tmp" >"$log" 2>&1 || rc=$?

    rm -f "$tmp"

    if ((rc != 0)); then
        err "官方安装程序返回错误码：$rc"
        echo
        echo "安装日志位置：$log"
        echo "日志可能包含敏感信息，请勿直接公开。"
        return 1
    fi

    if ! installed || ! systemctl is-active --quiet x-ui; then
        err "未检测到正常运行的面板服务"
        echo "请检查安装日志：$log"
        return 1
    fi

    if [[ "$sslmode" == "domain" ]]; then
        local cert="/root/cert/$domain/fullchain.pem"

        if [[ ! -s "$cert" ]]; then
            err "面板已安装，但未检测到预期的证书文件"
            echo "请检查安装日志：$log"
            return 1
        fi

        ok "面板服务已启动，并检测到证书文件"

        echo
        echo "面板地址："
        echo "https://$domain:$port/$path"

    else
        ok "3X-UI 面板服务已启动"
        warn "当前尚未配置 HTTPS"

        echo
        echo "推荐通过 SSH 隧道安全访问面板。"
        echo
        echo "在你自己的电脑运行："
        echo "ssh -L 2053:127.0.0.1:$port root@服务器地址 -p SSH端口"
        echo
        echo "然后在本机浏览器访问："
        echo "http://127.0.0.1:2053/$path"
        echo
        echo "NAT VPS 请使用服务商提供的 SSH 外部端口。"
    fi

    echo
    echo "========== 安装结果 =========="
    echo

    printf "管理员账号：%s\n" "$username"
    printf "管理员密码：%s\n" "$password"
    printf "访问路径：/%s\n" "$path"

    echo
    echo "请立即保存以上登录信息。"
    echo "不要公开管理员密码和完整访问路径。"
    echo
    echo "安装日志：$log"
}

manage() {
    check_env || return 1

    if ! installed; then
        err "尚未安装 3X-UI"
        return 1
    fi

    case "$1" in

        start)
            if systemctl start x-ui; then
                ok "面板启动成功"
            else
                err "面板启动失败"
            fi
            ;;

        stop)
            if confirm "确认停止面板服务？"; then
                if systemctl stop x-ui; then
                    ok "面板已停止"
                else
                    err "停止失败"
                fi
            fi
            ;;

        restart)
            if systemctl restart x-ui; then
                ok "面板重启成功"
            else
                err "面板重启失败"
            fi
            ;;

        logs)
            journalctl -u x-ui -n 40 --no-pager
            ;;

        official)
            echo "即将进入 3X-UI 官方管理菜单"
            echo "部分提示可能仍然是英文"
            x-ui
            ;;
    esac
}

backup() {
    check_env || return 1

    if ! installed; then
        err "尚未安装 3X-UI"
        return 1
    fi

    local src="/etc/x-ui/x-ui.db"
    local dest="/root/3xui-backups"
    local target

    if [[ ! -f "$src" ]]; then
        err "未找到默认 SQLite 数据库"
        return 1
    fi

    if ! command -v sqlite3 >/dev/null; then
        err "缺少 sqlite3"
        echo "可执行：apt-get install -y sqlite3"
        return 1
    fi

    mkdir -p "$dest"
    chmod 700 "$dest"

    target="$dest/x-ui-$(date +%Y%m%d-%H%M%S).db"

    if sqlite3 "$src" ".backup '$target'"; then
        chmod 600 "$target"
        ok "数据库备份成功：$target"
    else
        err "数据库备份失败"
        rm -f "$target"
    fi
}

menu() {
    while true; do
        echo
        printf "${BLUE}========== 3X-UI 中文安装向导 V1.1 ==========${RESET}\n"
        echo

        status

        echo
        echo "  1. 中文引导安装（全新 VPS）"
        echo "  2. 查看面板服务状态"
        echo "  3. 启动面板"
        echo "  4. 停止面板"
        echo "  5. 重启面板"
        echo "  6. 查看最近运行日志"
        echo "  7. 备份 SQLite 数据库"
        echo "  8. 进入官方 x-ui 管理菜单"
        echo "  0. 退出"
        echo

        local choice

        read -r -p "请选择 [0-8]：" choice || break

        case "$choice" in
            1)
                install_panel
                pause
                ;;
            2)
                status
                pause
                ;;
            3)
                manage start
                pause
                ;;
            4)
                manage stop
                pause
                ;;
            5)
                manage restart
                pause
                ;;
            6)
                manage logs
                pause
                ;;
            7)
                backup
                pause
                ;;
            8)
                manage official
                pause
                ;;
            0)
                echo "已退出中文管理工具"
                break
                ;;
            *)
                warn "请输入 0～8"
                ;;
        esac
    done
}

menu
