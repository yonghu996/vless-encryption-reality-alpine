#!/bin/bash

# VLESS Encryption + REALITY 一键安装管理脚本
# 版本: V1.7.4 (Xray 临时 JSON 配置校验修复)
# 固定配置: VLESS Encryption (native + 0-RTT + ML-KEM-768) + REALITY + xtls-rprx-vision

set -eo pipefail
umask 077

# --- 全局变量 ---
SCRIPT_VERSION="1.7.4"
xray_config_path="/usr/local/etc/xray/config.json"
xray_binary_path="/usr/local/bin/xray"

# 存放客户端配置信息的文件
client_encryption_info_file=~/xray_encryption_info.txt
client_reality_info_file=~/xray_reality_info.txt # 格式: pbk|sni|sid
client_vless_link_file=~/xray_vless_reality_link.txt

xray_status_info=""
is_quiet=false
PKG_MANAGER=""
url_extra_path=""

# --- 颜色定义 ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_PURPLE='\033[0;35m'
C_CYAN='\033[0;36m'

# --- 基础函数 ---
# 检查终端是否支持颜色
if [ -t 1 ]; then
    use_color=true
else
    use_color=false
fi

cecho() {
    local color_name="$1"
    local message="$2"
    if [ "$use_color" = true ] && [ -n "$color_name" ]; then
        echo -e "${color_name}${message}${C_RESET}"
    else
        echo "$message"
    fi
}

error() {
    cecho "$C_RED" "[✖] $1" >&2
}

info() {
    if [ "$is_quiet" = false ]; then
        cecho "$C_BLUE" "[!] $1" >&2
    fi
}

success() {
    if [ "$is_quiet" = false ]; then
        cecho "$C_GREEN" "[✔] $1" >&2
    fi
}

# --- 核心功能函数 ---

get_public_ip_v4() {
    local ip
    local sources=("https://api-ipv4.ip.sb/ip" "https://api.ipify.org" "https://ip.seeip.org")
    for source in "${sources[@]}"; do
        ip=$(curl -4s --max-time 5 "$source" 2>/dev/null)
        if echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            echo "$ip"
            return
        fi
    done
    echo ""
}

get_public_ip_v6() {
    local ip
    local sources=("https://api-ipv6.ip.sb/ip" "https://api64.ipify.org")
    for source in "${sources[@]}"; do
        ip=$(curl -6s --max-time 5 "$source" 2>/dev/null)
        if echo "$ip" | grep -q ':'; then
            echo "$ip"
            return
        fi
    done
    echo ""
}

execute_official_script() {
    local url="https://github.com/XTLS/Xray-install/raw/main${url_extra_path}/install-release.sh"
    info "执行 Xray 官方安装器: $*"
    # pipefail ensures failed downloads do not become false successes.
    if ! curl -fsSL --retry 2 --connect-timeout 10 "$url" | bash -s -- "$@"; then
        error "官方安装器执行失败: $*"
        return 1
    fi
}


check_xray_version() {
    [ -x "$xray_binary_path" ] || return 1
    local help_output
    help_output=$("$xray_binary_path" help 2>/dev/null) || return 1
    [[ "$help_output" == *vlessenc* && "$help_output" == *x25519* ]]
}


check_os_and_dependencies() {
    info "正在检查操作系统和依赖..."
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        url_extra_path="/alpinelinux"
    else
        error "错误: 未知的包管理器。"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        info "检测到缺失的依赖 (jq/curl)，正在尝试自动安装..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update >/dev/null 2>&1
                apt-get install -y jq curl >/dev/null 2>&1
                ;;
            dnf | yum)
                "$PKG_MANAGER" install -y jq curl >/dev/null 2>&1
                ;;
            apk)
                "$PKG_MANAGER" add jq curl >/dev/null 2>&1
                ;;
        esac
        if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
            error "依赖 (jq/curl) 自动安装失败。"
            exit 1
        fi
        success "依赖已成功安装。"
    fi
}

pre_check() {
    if [ "$(id -u)" != "0" ]; then
        error "错误: 您必须以root用户身份运行此脚本"
        exit 1
    fi
    check_os_and_dependencies
}

service_is_active() {
    local svc="$1"
    if command -v rc-service >/dev/null 2>&1; then
        rc-service "$svc" status >/dev/null 2>&1
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet "$svc"
    else
        return 1
    fi
}


check_xray_status() {
    if [ ! -f "$xray_binary_path" ]; then
        xray_status_info="$(cecho "$C_YELLOW" "Xray 状态: 未安装")"
        return
    fi

    local xray_version
    xray_version=$($xray_binary_path version 2>/dev/null | head -n 1 | awk '{print $2}' || echo "未知")

    local service_status
    
    if service_is_active xray; then
        service_status="$(cecho "$C_GREEN" "运行中")"
    else
        service_status="$(cecho "$C_RED" "未运行")"
    fi

    local feature_support
    if check_xray_version; then
        feature_support=" | $(cecho "$C_GREEN" "支持所需功能")"
    else
        feature_support=" | $(cecho "$C_RED" "不支持所需功能")"
    fi
    xray_status_info="Xray 状态: $(cecho "$C_GREEN" "已安装") | ${service_status} | 版本: $(cecho "$C_CYAN" "$xray_version")${feature_support}"
}

is_valid_port() {
    local port="$1"
    if echo "$port" | grep -q '^[0-9]\+$' && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}


is_valid_uuid() {
    [[ "$1" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]
}

is_valid_sni() {
    local host="$1" label
    [ "${#host}" -le 253 ] && [[ "$host" == *.* ]] || return 1
    [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "$host" != .* && "$host" != *. && "$host" != *..* ]] || return 1
    local -a labels
    IFS='.' read -r -a labels <<< "$host"
    for label in "${labels[@]}"; do
        [ "${#label}" -le 63 ] && [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

is_valid_short_id() {
    [[ "$1" =~ ^[[:xdigit:]]*$ ]] && [ "${#1}" -le 16 ] && (( ${#1} % 2 == 0 ))
}

validate_node_inputs() {
    local port="$1" uuid="$2" sni="$3" sid="$4"
    if ! is_valid_port "$port"; then error "端口必须为 1-65535"; return 1; fi
    if ! is_valid_uuid "$uuid"; then error "UUID 格式无效"; return 1; fi
    if ! is_valid_sni "$sni"; then error "SNI 必须是合法域名，例如 www.sega.com（不要输入反斜杠）"; return 1; fi
    if ! is_valid_short_id "$sid"; then error "Short ID 必须是偶数位十六进制字符，最多16位"; return 1; fi
    return 0
}

generate_uuid() {
    if [ -f "$xray_binary_path" ] && [ -x "$xray_binary_path" ]; then
        $xray_binary_path uuid
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

generate_vless_encryption_config() {
    info "正在生成 VLESS Encryption 配置..."
    local vlessenc_output
    vlessenc_output=$($xray_binary_path vlessenc 2>/dev/null)
    if [ -z "$vlessenc_output" ]; then
        error "生成 VLESS Encryption 配置失败"
        return 1
    fi

    local decryption_config="" encryption_config="" in_mlkem_section=false parsing_encryption=false
    while IFS= read -r line; do
        if [ "$in_mlkem_section" = true ] && [[ "$line" != *'"decryption":'* ]] && [[ "$line" != *'"encryption":'* ]] && [[ "$parsing_encryption" = false ]] && [ -n "$decryption_config" ] && [ -n "$encryption_config" ]; then
            if [[ ! "$line" =~ ^[[:space:]]*"\"" ]]; then
                break
            fi
        fi
        if [[ "$line" == *"Authentication: ML-KEM-768, Post-Quantum"* ]]; then
            in_mlkem_section=true
            continue
        fi
        if [ "$in_mlkem_section" = false ]; then
            continue
        fi
        if [ "$parsing_encryption" = true ]; then
            encryption_config+="${line}"
            if [[ "$line" == *"\"" ]]; then
                parsing_encryption=false
                encryption_config=$(echo "$encryption_config" | sed 's/"$//' | tr -d '[:space:]')
            fi
            continue
        fi
        if [[ "$line" == *'"decryption":'* ]]; then
            decryption_config=$(echo "$line" | sed 's/.*"decryption": "\([^"]*\)".*/\1/')
            continue
        fi
        if [[ "$line" == *'"encryption":'* ]]; then
            parsing_encryption=true
            encryption_config=$(echo "$line" | sed 's/.*"encryption": "\([^"]*\).*/\1/')
            if [[ "$line" == *"\"" ]]; then
                parsing_encryption=false
                encryption_config=$(echo "$encryption_config" | sed 's/"$//' | tr -d '[:space:]')
            fi
        fi
    done <<< "$vlessenc_output"

    if [ -z "$decryption_config" ] || [ -z "$encryption_config" ]; then
        error "无法解析 VLESS Encryption 配置。"
        return 1
    fi
    echo "${decryption_config}|${encryption_config}"
}

generate_reality_keys() {
    info "正在生成 REALITY 密钥对..."
    local key_pair private_key public_key

    if ! key_pair=$("$xray_binary_path" x25519 2>/dev/null); then
        error "Xray x25519 命令执行失败，无法生成 REALITY 密钥。"
        return 1
    fi

    # Xray 26.10.21: "PrivateKey: ..." / "Password (PublicKey): ..."
    # Also accept older Xray labels: "Password:", "PublicKey:", "Private key:" and "Public key:".
    private_key=$(printf '%s\n' "$key_pair" |
        awk -F':[[:space:]]*' '/^[[:space:]]*(PrivateKey|Private key):/ { print $2; exit }' |
        tr -d '[:space:]')
    public_key=$(printf '%s\n' "$key_pair" |
        awk -F':[[:space:]]*' '/^[[:space:]]*(Password \(PublicKey\)|Password|PublicKey|Public key):/ { print $2; exit }' |
        tr -d '[:space:]')

    # Xray defaults to raw URL-safe Base64 for 32-byte X25519 keys (43 characters).
    # Fail closed on changed or unexpected output instead of writing broken JSON.
    if [[ ! "$private_key" =~ ^[A-Za-z0-9_-]{43}$ ]] ||
       [[ ! "$public_key" =~ ^[A-Za-z0-9_-]{43}$ ]]; then
        error "无法解析 REALITY 密钥对：Xray x25519 输出字段/密钥格式不符合预期。"
        return 1
    fi
    printf '%s|%s\n' "$private_key" "$public_key"
}


install_xray() {
    if [ -f "$xray_binary_path" ]; then
        if ! check_xray_version; then
            info "检测到已安装的 Xray 版本不支持所需功能，需要更新。"
        else
            info "检测到 Xray 已安装。继续操作将覆盖现有配置。"
        fi
        echo -n "是否继续？[y/N]: "
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            info "操作已取消。"
            return
        fi
    fi

    info "开始配置 VLESS Encryption + REALITY + Vision..."
    local port uuid sni short_id
    while true; do
        echo -n "请输入端口 [1-65535] (默认: 443): "
        read -r port
        [ -z "$port" ] && port=443
        if is_valid_port "$port"; then
            break
        else
            error "端口无效。"
        fi
    done
    echo -n "请输入UUID (留空将自动生成): "
    read -r uuid
    if [ -z "$uuid" ]; then
        uuid=$(generate_uuid)
        info "已为您生成随机UUID: ${uuid}"
    fi
    echo -n "请输入REALITY SNI (默认: learn.microsoft.com): "
    read -r sni
    [ -z "$sni" ] && sni="learn.microsoft.com"
    echo -n "请输入REALITY Short ID (默认: 20220701): "
    read -r short_id
    [ -z "$short_id" ] && short_id="20220701"
    if ! validate_node_inputs "$port" "$uuid" "$sni" "$short_id"; then return 1; fi

    run_install "$port" "$uuid" "$sni" "$short_id"
}

update_xray() {
    if [ ! -x "$xray_binary_path" ]; then
        error "Xray 未安装。"
        return 1
    fi

    info "正在检查 Xray 最新版本..."
    local current_version latest_version
    current_version=$("$xray_binary_path" version | head -n 1 | awk '{print $2}' | sed 's/^v//')
    latest_version=$(curl -fsSL --max-time 15 \
        https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name // empty' | sed 's/^v//' || true)
    if [ -z "$latest_version" ]; then
        error "获取最新版本号失败。"
        return 1
    fi
    info "当前: $current_version；最新: $latest_version"
    if [ "$current_version" = "$latest_version" ] && check_xray_version; then
        success "Xray 已是最新版本。"
        return 0
    fi

    if ! execute_official_script install; then
        error "Xray 核心更新失败！"
        return 1
    fi
    if ! execute_official_script update-geodata; then
        info "Geo 扩展数据下载失败；Xray 自带基础 Geo 数据，不影响此节点。"
    fi
    if ! check_xray_version || ! restart_xray; then return 1; fi
    success "Xray 更新成功！"
}


restart_xray() {
    if [ ! -x "$xray_binary_path" ]; then error "Xray 未安装。"; return 1; fi
    info "正在启动或重启 Xray..."
    if command -v rc-service >/dev/null 2>&1; then
        if ! rc-update add xray default >/dev/null 2>&1; then
            error "无法启用 Xray OpenRC 开机自启"
            return 1
        fi
        if service_is_active xray; then
            if ! rc-service xray restart; then error "OpenRC 重启失败"; return 1; fi
        else
            if ! rc-service xray start; then error "OpenRC 启动失败"; return 1; fi
        fi
    elif command -v systemctl >/dev/null 2>&1; then
        if ! systemctl enable xray >/dev/null 2>&1 || ! systemctl restart xray; then
            error "systemd 启动失败"
            return 1
        fi
    else
        error "未找到 OpenRC 或 systemd 服务管理器"
        return 1
    fi
    sleep 1
    if ! service_is_active xray; then
        error "Xray 没有保持运行，请检查配置和日志"
        return 1
    fi
    success "Xray 已运行，并已设置开机自启"
}


stop_xray() {
    if [ ! -x "$xray_binary_path" ]; then error "Xray 未安装。"; return 1; fi
    if ! service_is_active xray; then success "Xray 已停止"; return 0; fi
    if command -v rc-service >/dev/null 2>&1; then
        if ! rc-service xray stop; then error "OpenRC 停止失败"; return 1; fi
    elif command -v systemctl >/dev/null 2>&1; then
        if ! systemctl stop xray; then error "systemd 停止失败"; return 1; fi
    else
        error "没有可用的服务管理器"
        return 1
    fi
    success "Xray 已停止"
}


uninstall_xray() {
    if [ ! -f "$xray_binary_path" ]; then error "Xray 未安装。"; return 1; fi
    echo "警告：将删除 Xray 程序、配置、日志和本脚本生成的客户端信息。"
    echo -n "确认卸载？请输入 yes: "
    local confirm
    read -r confirm
    if [ "$confirm" != "yes" ]; then info "已取消卸载"; return 0; fi

    if command -v rc-service >/dev/null 2>&1; then
        # The official Alpine installer has no 'remove' action.
        if service_is_active xray && ! rc-service xray stop; then
            error "服务仍在运行，已取消删除。"
            return 1
        fi
        rc-update del xray default >/dev/null 2>&1 || true
        rm -f /etc/init.d/xray /etc/logrotate.d/xray "$xray_binary_path"
        rm -rf /usr/local/etc/xray /usr/local/share/xray /var/log/xray
    else
        if ! execute_official_script remove --purge; then
            error "官方卸载脚本失败"
            return 1
        fi
    fi
    rm -f "$client_vless_link_file" "$client_encryption_info_file" "$client_reality_info_file"
    success "Xray 已卸载；系统依赖及专用系统用户保留"
}


view_xray_log() {
    if [ ! -x "$xray_binary_path" ]; then error "Xray 未安装。"; return 1; fi
    if command -v rc-service >/dev/null 2>&1; then
        echo "Xray OpenRC 状态："
        rc-service xray status || true
        if [ -f /var/log/xray/error.log ]; then
            info "显示最近100行错误日志；按 Ctrl+C 退出..."
            tail -n 100 -f /var/log/xray/error.log
        else
            info "暂无 /var/log/xray/error.log；可运行 rc-service xray checkconfig 排查启动失败"
            rc-service xray checkconfig || true
        fi
    elif command -v journalctl >/dev/null 2>&1; then
        info "按 Ctrl+C 退出日志..."
        journalctl -u xray -f --no-pager
    else
        error "没有可用的日志查看工具"
        return 1
    fi
}


modify_config() {
    if [ ! -f "$xray_config_path" ]; then
        error "错误: Xray 未安装。"
        return
    fi

    info "读取当前配置..."
    local current_port
    current_port=$(jq -r '.inbounds[0].port' "$xray_config_path")
    local current_uuid
    current_uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$xray_config_path")
    local current_sni
    current_sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$xray_config_path")
    local current_short_id
    current_short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$xray_config_path")

    info "请输入新配置，回车则保留当前值。"
    local port uuid sni short_id
    while true; do
        echo -n "端口 (当前: ${current_port}): "
        read -r port
        [ -z "$port" ] && port=$current_port
        if is_valid_port "$port"; then
            break
        else
            error "端口无效。"
        fi
    done
    echo -n "UUID (当前: ${current_uuid}): "
    read -r uuid
    [ -z "$uuid" ] && uuid=$current_uuid
    echo -n "SNI (当前: ${current_sni}): "
    read -r sni
    [ -z "$sni" ] && sni=$current_sni
    echo -n "Short ID (当前: ${current_short_id}): "
    read -r short_id
    [ -z "$short_id" ] && short_id=$current_short_id
    if ! validate_node_inputs "$port" "$uuid" "$sni" "$short_id"; then return 1; fi

    local encryption_info
    encryption_info=$(generate_vless_encryption_config)
    if [ -z "$encryption_info" ]; then return 1; fi

    local reality_keys
    reality_keys=$(generate_reality_keys)
    if [ -z "$reality_keys" ]; then return 1; fi

    local decryption_config
    decryption_config=$(echo "$encryption_info" | cut -d'|' -f1)
    local encryption_config
    encryption_config=$(echo "$encryption_info" | cut -d'|' -f2)
    local private_key
    private_key=$(echo "$reality_keys" | cut -d'|' -f1)
    local public_key
    public_key=$(echo "$reality_keys" | cut -d'|' -f2)

    if ! write_config "$port" "$uuid" "$decryption_config" "$encryption_config" "$private_key" "$public_key" "$sni" "$short_id"; then return 1; fi

    if ! restart_xray; then
        return
    fi
    
    success "配置修改成功！"
    view_subscription_info || true
}

view_subscription_info() {
    if [ ! -f "$xray_config_path" ]; then
        error "错误: 配置文件不存在。"
        return
    fi

    local ip4
    ip4=$(get_public_ip_v4)
    local ip6
    ip6=$(get_public_ip_v6)
    if [ -z "$ip4" ] && [ -z "$ip6" ]; then
        error "无法获取任何公网 IP 地址。"
        return 1
    fi

    local display_ip=${ip4:-$ip6}
    if [ -z "$display_ip" ]; then
        error "无法获取有效的公网IP地址。"
        return 1
    fi

    local uuid port
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$xray_config_path")
    port=$(jq -r '.inbounds[0].port' "$xray_config_path")

    if [ ! -f "$client_encryption_info_file" ] || [ ! -f "$client_reality_info_file" ]; then
        error "缺少客户端配置信息文件。"
        return
    fi

    local encryption reality_info public_key sni short_id
    encryption=$(cat "$client_encryption_info_file" 2>/dev/null)
    reality_info=$(cat "$client_reality_info_file" 2>/dev/null)
    public_key=$(echo "$reality_info" | cut -d'|' -f1)
    sni=$(echo "$reality_info" | cut -d'|' -f2)
    short_id=$(echo "$reality_info" | cut -d'|' -f3)

    if [ -z "$encryption" ] || [ -z "$public_key" ] || [ -z "$sni" ]; then
        error "客户端配置信息不完整。"
        return
    fi
    
    local link_name_raw
    link_name_raw="$(hostname) VLESS-E-reality"
    local link_name_encoded
    link_name_encoded=$(echo "$link_name_raw" | sed 's/ /%20/g')

    local address_for_url=$display_ip
    if [[ $display_ip == *":"* ]]; then
        address_for_url="[${display_ip}]"
    fi

    local vless_url="vless://${uuid}@${address_for_url}:${port}?encryption=${encryption}&security=reality&sni=${sni}&sid=${short_id}&fp=chrome&pbk=${public_key}&flow=xtls-rprx-vision&type=tcp#${link_name_encoded}"
    local yaml_url="- { name: '${link_name_raw}', type: vless, server: ${address_for_url}, port: ${port}, uuid: ${uuid}, network: tcp, udp: true, tls: true, skip-cert-verify: false, flow: xtls-rprx-vision, client-fingerprint: chrome, servername: ${sni}, reality-opts: { public-key: \"${public_key}\", short-id: ${short_id} }, encryption: \"${encryption}\" }"

    if [ "$is_quiet" = true ]; then
        echo "${vless_url}"
        echo "${yaml_url}"
    else
        echo "${vless_url}" > "$client_vless_link_file"
        chmod 600 "$client_vless_link_file"
        echo "----------------------------------------------------------------"
        cecho "$C_CYAN" " --- Xray VLESS-Encryption + REALITY + Vision 订阅信息 --- "
        echo " 节点名称: $(cecho "$C_PURPLE" "$link_name_raw")"
        if [ -n "$ip4" ]; then echo " 地址(IPv4): $(cecho "$C_PURPLE" "$ip4")"; fi
        if [ -n "$ip6" ]; then echo " 地址(IPv6): $(cecho "$C_PURPLE" "$ip6")"; fi
        echo " 端口: $(cecho "$C_PURPLE" "$port")"
        echo " UUID: $(cecho "$C_PURPLE" "$uuid")"
        echo " PublicKey: $(cecho "$C_PURPLE" "$public_key")"
        echo " 协议: $(cecho "$C_YELLOW" "VLESS Encryption")"
        echo " 安全类型: $(cecho "$C_YELLOW" "reality")"
        echo " 流控: $(cecho "$C_YELLOW" "xtls-rprx-vision")"
        echo " 指纹: $(cecho "$C_YELLOW" "chrome")"
        echo " SNI: $(cecho "$C_PURPLE" "$sni")"
        echo " Short ID: $(cecho "$C_PURPLE" "$short_id")"
        echo "----------------------------------------------------------------"
        cecho "$C_GREEN" " 订阅链接 (已保存到 $client_vless_link_file): "
        echo
        cecho "$C_GREEN" "$vless_url"
        echo
        echo "----------------------------------------------------------------"
        echo "--- yaml格式的节点(内核支持才可用) ---"
        echo
        cecho "$C_GREEN" "$yaml_url"
        echo
        echo "----------------------------------------------------------------"
    fi
}

write_config() {
    local port="$1" uuid="$2" decryption_config="$3" encryption_config="$4"
    local private_key="$5" public_key="$6" sni="$7" short_id="$8"
    local tmp_config

    mkdir -p /var/log/xray
    chown xray:xray /var/log/xray
    chmod 700 /var/log/xray
    # Xray's external config loader requires the filename to end in .json.
    # -format=json alone does not override its extension check.
    tmp_config=$(mktemp "${xray_config_path}.tmp.XXXXXX") || return 1
    if ! mv -f "$tmp_config" "${tmp_config}.json"; then
        rm -f "$tmp_config"
        error "无法创建临时 JSON 配置文件"
        return 1
    fi
    tmp_config="${tmp_config}.json"

    if ! jq -n \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --arg decryption "$decryption_config" \
        --arg private_key "$private_key" \
        --arg sni "$sni" \
        --arg short_id "$short_id" \
        --arg flow "xtls-rprx-vision" \
    '{
        "log": {
            "loglevel": "warning",
            "error": "/var/log/xray/error.log"
        },
        "inbounds": [{
            "listen": "::",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [{
                    "id": $uuid,
                    "flow": $flow
                }],
                "decryption": $decryption
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": ($sni + ":443"),
                    "xver": 0,
                    "serverNames": [$sni],
                    "privateKey": $private_key,
                    "shortIds": [$short_id],
                    "fingerprint": "chrome"
                }
            }
        }],
        "outbounds": [{
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        }]
    }' > "$tmp_config"; then
        rm -f "$tmp_config"
        error "生成配置文件失败"
        return 1
    fi

    if ! "$xray_binary_path" run -test -format=json -config "$tmp_config"; then
        rm -f "$tmp_config"
        error "Xray 配置检查不通过，旧配置未覆盖"
        return 1
    fi
    if ! chown root:xray "$tmp_config" || ! chmod 640 "$tmp_config"; then
        rm -f "$tmp_config"
        error "设置 Xray 配置权限失败"
        return 1
    fi
    if [ -f "$xray_config_path" ]; then
        cp -p "$xray_config_path" "${xray_config_path}.bak" || { rm -f "$tmp_config"; return 1; }
    fi
    mv -f "$tmp_config" "$xray_config_path"
    printf '%s\n' "$encryption_config" > "$client_encryption_info_file"
    printf '%s\n' "${public_key}|${sni}|${short_id}" > "$client_reality_info_file"
    chmod 600 "$client_encryption_info_file" "$client_reality_info_file"
}


run_install() {
    local port="$1" uuid="$2" sni="$3" short_id="$4"
    if ! validate_node_inputs "$port" "$uuid" "$sni" "$short_id"; then return 1; fi

    info "正在下载并安装 Xray 核心..."
    if ! execute_official_script install; then
        error "Xray 核心安装失败！"
        exit 1
    fi

    info "正在尝试更新 Geo 数据文件..."
    if ! execute_official_script update-geodata; then
        info "Geo 扩展数据更新失败，继续使用官方自带的 Geo 数据。"
    fi

    if ! check_xray_version; then
        error "安装的 Xray 版本不支持所需功能！"
        exit 1
    fi

    local encryption_info
    encryption_info=$(generate_vless_encryption_config)
    if [ -z "$encryption_info" ]; then
        error "生成 Encryption 配置失败！"
        exit 1
    fi

    local reality_keys
    reality_keys=$(generate_reality_keys)
    if [ -z "$reality_keys" ]; then
        error "生成 REALITY 密钥对失败！"
        exit 1
    fi

    local decryption_config
    decryption_config=$(echo "$encryption_info" | cut -d'|' -f1)
    local encryption_config
    encryption_config=$(echo "$encryption_info" | cut -d'|' -f2)
    local private_key
    private_key=$(echo "$reality_keys" | cut -d'|' -f1)
    local public_key
    public_key=$(echo "$reality_keys" | cut -d'|' -f2)

    info "正在写入 Xray 配置文件..."
    if ! write_config "$port" "$uuid" "$decryption_config" "$encryption_config" "$private_key" "$public_key" "$sni" "$short_id"; then return 1; fi

    if ! restart_xray; then
        exit 1
    fi

    success "Xray 安装/配置成功！"
    if ! view_subscription_info; then
        info "服务已启动，但暂时无法自动获取公网地址，请检查网络后通过菜单8查看订阅。"
    fi
}

press_any_key_to_continue() {
    echo
    cecho "$C_YELLOW" "按任意键返回主菜单..."
    read -r -n 1 -s
}

main_menu() {
    while true; do
        clear
        cecho "$C_CYAN" "改自 https://github.com/yahuisme/vless-encryption-reality 而来的 alpine 支持版"
        cecho "$C_CYAN" "--- Xray VLESS-Encryption + REALITY + Vision 一键脚本 v${SCRIPT_VERSION} ---"
        echo
        check_xray_status
        echo "  ${xray_status_info}"
        cecho "$C_GREEN"  "────────────────────────────────────────────────────────"
        cecho "$C_PURPLE" "  1. 一键安装/重装 Xray (VLESS-Encryption + REALITY + Vision)"
        cecho "$C_PURPLE" "  2. 更新 Xray"
        cecho "$C_PURPLE" "  3. 重启 Xray"
        cecho "$C_PURPLE" "  4. 停止 Xray"
        cecho "$C_PURPLE" "  5. 卸载 Xray"
        cecho "$C_PURPLE" "  6. 查看 Xray 日志"
        cecho "$C_PURPLE" "  7. 修改节点配置"
        cecho "$C_PURPLE" "  8. 查看订阅信息"
        cecho "$C_GREEN"  "────────────────────────────────────────────────────────"
        cecho "$C_RED"    "  0. 退出脚本"
        cecho "$C_GREEN"  "────────────────────────────────────────────────────────"
        echo -n "  请输入选项 [0-8]: "
        read -r choice

        local needs_pause=true
        case $choice in
            1) install_xray ;;
            2) update_xray ;;
            3) restart_xray ;;
            4) stop_xray ;;
            5) uninstall_xray ;;
            6) view_xray_log; needs_pause=false ;;
            7) modify_config ;;
            8) view_subscription_info || true ;;
            0) success "感谢使用！"; exit 0 ;;
            *) error "无效选项。" ;;
        esac

        if [ "$needs_pause" = true ]; then
            press_any_key_to_continue
        fi
    done
}

show_help() {
    echo "Xray VLESS-Encryption + REALITY + Vision 一键脚本 v${SCRIPT_VERSION}"
    echo
    echo "用法:"
    echo "  $0                # 显示交互式菜单"
    echo "  $0 install [选项]   # 以无交互方式安装"
    echo
    echo "安装选项:"
    echo "  --port <端口>      # 监听端口 (默认: 443)"
    echo "  --uuid <UUID>      # 用户UUID (默认: 自动生成)"
    echo "  --sni <域名>       # REALITY SNI (默认: learn.microsoft.com)"
    echo "  --short-id <HEX>  # REALITY Short ID (默认: 20220701)"
    echo "  --quiet, -q        # 静默模式，成功后仅输出订阅链接"
    echo
    echo "示例:"
    echo "  $0 install --port 28888 --uuid 'your-uuid' --sni 'www.sega.com'"
}

main() {
    pre_check

    if [ $# -gt 0 ] && [ "$1" = "install" ]; then
        shift # 消耗 "install"
        local port="443"
        local uuid=""
        local sni="learn.microsoft.com"
        local short_id="20220701" # 始终使用默认值

        while [ $# -gt 0 ]; do
            case "$1" in
                --port) port="${2:?--port 缺少值}"; shift 2 ;;
                --uuid) uuid="${2:?--uuid 缺少值}"; shift 2 ;;
                --sni) sni="${2:?--sni 缺少值}"; shift 2 ;;
                --short-id) short_id="${2:?--short-id 缺少值}"; shift 2 ;;
                --quiet | -q) is_quiet=true; shift ;;
                *) error "未知参数: $1"; exit 1 ;;
            esac
        done

        if [ -z "$uuid" ]; then
            info "UUID 未提供，将自动生成。"
            uuid=$(generate_uuid)
        fi

        if ! validate_node_inputs "$port" "$uuid" "$sni" "$short_id"; then exit 1; fi

        info "开始静默安装..."
        info "  端口: $port"
        info "  UUID: $uuid"
        info "  SNI: $sni"
        info "  Short ID: $short_id"
        run_install "$port" "$uuid" "$sni" "$short_id"
    else
        main_menu
    fi
}

# --- 脚本入口 ---
# Sourcing the script is supported for parser regression tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [ $# -gt 0 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
        show_help
        exit 0
    fi
    main "$@"
fi
