#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat openssl iproute coreutils -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat openssl iproute2 coreutils -y
    fi
}

# 仅在缺少依赖时才安装依赖，二次运行脚本时跳过 (不再更新依赖)
ensure_base() {
    local cmd
    for cmd in wget curl unzip tar socat openssl ss shuf; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            install_base
            return
        fi
    done
    echo -e "${green}依赖已安装，跳过依赖安装${plain}"
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm /usr/local/XrayR/ -rf
    fi

    mkdir /usr/local/XrayR/ -p
	cd /usr/local/XrayR/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/Gkimins/XrayR/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 XrayR 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 XrayR 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 XrayR 最新版本：${last_version}，开始安装"
        wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip https://github.com/Gkimins/XrayR/releases/download/${last_version}/XrayR-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        if [[ $1 == v* ]]; then
            last_version=$1
	else
	    last_version="v"$1
	fi
        url="https://github.com/Gkimins/XrayR/releases/download/${last_version}/XrayR-linux-${arch}.zip"
        echo -e "开始安装 XrayR ${last_version}"
        wget -q -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 XrayR ${last_version} 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip XrayR-linux.zip
    rm XrayR-linux.zip -f
    chmod +x XrayR
    mkdir /etc/XrayR/ -p
    rm /etc/systemd/system/XrayR.service -f
    file="https://github.com/Gkimins/XrayR-release/raw/master/XrayR.service"
    wget -q -N --no-check-certificate -O /etc/systemd/system/XrayR.service ${file}
    #cp -f XrayR.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop XrayR
    systemctl enable XrayR
    echo -e "${green}XrayR ${last_version}${plain} 安装完成，已设置开机自启"
    cp geoip.dat /etc/XrayR/
    cp geosite.dat /etc/XrayR/

    if [[ ! -f /etc/XrayR/config.yml ]]; then
        cp config.yml /etc/XrayR/
        echo -e ""
        echo -e "全新安装，请先参看教程：https://github.com/Gkimins/XrayR，配置必要的内容"
    else
        systemctl start XrayR
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 重启成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请稍后使用 XrayR log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/Gkimins/XrayR/wiki${plain}"
        fi
    fi

    if [[ ! -f /etc/XrayR/dns.json ]]; then
        cp dns.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/route.json ]]; then
        cp route.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/XrayR/
    fi
    if [[ ! -f /etc/XrayR/rulelist ]]; then
        cp rulelist /etc/XrayR/
    fi
    curl -o /usr/bin/XrayR -Ls https://raw.githubusercontent.com/Gkimins/XrayR-release/master/XrayR.sh
    chmod +x /usr/bin/XrayR
    ln -s /usr/bin/XrayR /usr/bin/xrayr # 小写兼容
    chmod +x /usr/bin/xrayr
    cd $cur_dir
    echo -e ""
    echo "XrayR 管理脚本使用方法 (兼容使用xrayr执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单 (功能更多)"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 显示配置文件内容"
    echo "XrayR install            - 安装 XrayR"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

# ---------------------------------------------------------------------------
# Hysteria2 (standalone service, installed via the official installer)
# ---------------------------------------------------------------------------

# 在 39000~40000 范围内自动探测一个未被占用的端口
# $1: tcp 或 udp
find_free_port() {
    local proto=$1
    local port
    local i
    for i in $(seq 1 60); do
        port=$(shuf -i 39000-40000 -n 1)
        if [[ "$proto" == "udp" ]]; then
            if ! ss -lun 2>/dev/null | grep -q ":${port}\b"; then
                echo "$port"; return 0
            fi
        else
            if ! ss -ltn 2>/dev/null | grep -q ":${port}\b"; then
                echo "$port"; return 0
            fi
        fi
    done
    echo "$port"  # 兜底：直接返回最后一次抽取的端口
}

install_hysteria2_bin() {
    echo -e "${green}开始安装 Hysteria2 (官方安装脚本)${plain}"
    # 官方安装脚本会把二进制装到 /usr/local/bin/hysteria，
    # 并创建 hysteria-server.service / hysteria-server@.service 及 hysteria 用户
    bash <(curl -fsSL https://get.hy2.sh/)
    if [[ $? -ne 0 || ! -f /usr/local/bin/hysteria ]]; then
        echo -e "${red}Hysteria2 安装失败，请确保服务器能够访问 https://get.hy2.sh/${plain}"
        return 1
    fi
    mkdir -p /etc/hysteria
    echo -e "${green}Hysteria2 二进制安装完成${plain}"
    return 0
}

# 写入客户端 systemd 模板单元 (官方仅提供服务端模板)
# hysteria-client@<name> -> /etc/hysteria/client-<name>.yaml
install_client_template() {
    cat > /etc/systemd/system/hysteria-client@.service <<'EOF'
[Unit]
Description=Hysteria2 Client Service (%i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria client --config /etc/hysteria/client-%i.yaml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 仅在未安装时安装 XrayR，避免重复运行时误删已有安装
ensure_xrayr() {
    if [[ -f /etc/systemd/system/XrayR.service ]]; then
        echo -e "${green}XrayR 已安装，跳过安装 (如需更新请使用菜单)${plain}"
    else
        install_XrayR "$@"
    fi
}

# 仅在未安装时安装 Hysteria2 二进制，并确保客户端模板存在 (幂等)
ensure_hysteria2() {
    if [[ -f /usr/local/bin/hysteria ]]; then
        echo -e "${green}Hysteria2 已安装，跳过安装${plain}"
        mkdir -p /etc/hysteria
    else
        install_hysteria2_bin || return 1
    fi
    install_client_template
    return 0
}

# 校验实例名称：非空、仅允许字母数字下划线短横线，且不为保留名 config
valid_name() {
    local name=$1
    if [[ -z "$name" ]]; then
        echo -e "${red}名称不能为空${plain}"
        return 1
    fi
    if ! [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo -e "${red}名称只能包含字母、数字、下划线、短横线${plain}"
        return 1
    fi
    if [[ "$name" == "config" ]]; then
        echo -e "${red}config 为保留名称，请换一个${plain}"
        return 1
    fi
    return 0
}

# 新增一个服务端实例：hysteria-server@<name> -> /etc/hysteria/<name>.yaml
add_server_instance() {
    echo -e "${yellow}== 新增 Hysteria2 服务端实例 ==${plain}"
    read -p "实例名称 (例如 s1): " name
    valid_name "$name" || return
    local cfg="/etc/hysteria/${name}.yaml"
    if [[ -f "$cfg" ]]; then
        read -p "实例 ${name} 已存在，是否覆盖？[y/N]: " ow
        [[ "$ow" != "y" && "$ow" != "Y" ]] && echo "已取消" && return
    fi

    local hy_port
    hy_port=$(find_free_port udp)
    echo -e "自动分配监听端口(UDP)：${green}${hy_port}${plain} (范围 39000~40000)"

    read -p "连接密码 (留空则随机生成): " hy_pass
    if [[ -z "$hy_pass" ]]; then
        hy_pass=$(openssl rand -base64 16)
        echo -e "已生成随机密码：${green}${hy_pass}${plain}"
    fi

    read -p "域名 (留空则使用自签证书，默认域名 www.bing.com，客户端需 insecure): " hy_domain

    local sni_hint insecure_hint
    if [[ -n "$hy_domain" ]]; then
        # 提供域名 -> ACME 自动申请证书
        read -p "邮箱 (用于 ACME 申请): " hy_email
        cat > "$cfg" <<EOF
listen: :${hy_port}

acme:
  domains:
    - ${hy_domain}
  email: ${hy_email}

auth:
  type: password
  password: ${hy_pass}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
EOF
        sni_hint="$hy_domain"
        insecure_hint="false"
    else
        # 未提供域名 -> 自签证书，默认域名 www.bing.com，客户端需 insecure=true
        hy_domain="www.bing.com"
        local crt="/etc/hysteria/${name}.crt"
        local key="/etc/hysteria/${name}.key"
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$key" -out "$crt" \
            -subj "/CN=${hy_domain}" -days 36500
        chown hysteria:hysteria "$key" "$crt" 2>/dev/null
        chmod 644 "$crt"
        chmod 640 "$key"
        cat > "$cfg" <<EOF
listen: :${hy_port}

tls:
  cert: ${crt}
  key: ${key}

auth:
  type: password
  password: ${hy_pass}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
EOF
        sni_hint="www.bing.com"
        insecure_hint="true"
    fi

    systemctl enable "hysteria-server@${name}" >/dev/null 2>&1
    systemctl restart "hysteria-server@${name}"
    sleep 2
    if systemctl is-active --quiet "hysteria-server@${name}"; then
        echo -e "${green}服务端实例 ${name} 启动成功${plain}"
        echo -e "  服务：${green}hysteria-server@${name}${plain}   配置：${green}${cfg}${plain}"
        echo -e "  端口：${green}${hy_port}${plain}   密码：${green}${hy_pass}${plain}"
        echo -e "  客户端 SNI：${green}${sni_hint}${plain}   insecure：${green}${insecure_hint}${plain}"
    else
        echo -e "${red}服务端实例 ${name} 可能启动失败，请执行：journalctl -u hysteria-server@${name} -e 查看日志${plain}"
    fi
}

# 新增一个客户端实例：hysteria-client@<name> -> /etc/hysteria/client-<name>.yaml
add_client_instance() {
    echo -e "${yellow}== 新增 Hysteria2 客户端实例 ==${plain}"
    read -p "实例名称 (例如 c1): " name
    valid_name "$name" || return
    local cfg="/etc/hysteria/client-${name}.yaml"
    if [[ -f "$cfg" ]]; then
        read -p "实例 ${name} 已存在，是否覆盖？[y/N]: " ow
        [[ "$ow" != "y" && "$ow" != "Y" ]] && echo "已取消" && return
    fi

    read -p "服务器地址 (host:port，例如 1.2.3.4:443): " hy_server
    read -p "连接密码: " hy_pass
    read -p "SNI (留空默认 www.bing.com): " hy_sni
    [[ -z "$hy_sni" ]] && hy_sni="www.bing.com"
    read -p "是否跳过证书校验 insecure？(留空默认 Yes) [Y/n]: " hy_insecure
    local insecure_val
    if [[ "$hy_insecure" == "n" || "$hy_insecure" == "N" ]]; then
        insecure_val="false"
    else
        insecure_val="true"
    fi

    read -p "上行带宽 up (留空默认 500 mbps): " hy_up
    [[ -z "$hy_up" ]] && hy_up="500 mbps"
    read -p "下行带宽 down (留空默认 500 mbps): " hy_down
    [[ -z "$hy_down" ]] && hy_down="500 mbps"

    local hy_socks hy_http
    hy_socks=$(find_free_port tcp)
    hy_http=$(find_free_port tcp)
    while [[ "$hy_http" == "$hy_socks" ]]; do
        hy_http=$(find_free_port tcp)
    done
    echo -e "自动分配 SOCKS5 端口：${green}${hy_socks}${plain}   HTTP 端口：${green}${hy_http}${plain} (范围 39000~40000)"

    cat > "$cfg" <<EOF
server: ${hy_server}

auth: ${hy_pass}

tls:
  sni: ${hy_sni}
  insecure: ${insecure_val}

bandwidth:
  up: ${hy_up}
  down: ${hy_down}

socks5:
  listen: 127.0.0.1:${hy_socks}

http:
  listen: 127.0.0.1:${hy_http}
EOF

    systemctl enable "hysteria-client@${name}" >/dev/null 2>&1
    systemctl restart "hysteria-client@${name}"
    sleep 2
    if systemctl is-active --quiet "hysteria-client@${name}"; then
        echo -e "${green}客户端实例 ${name} 启动成功${plain}"
        echo -e "  服务：${green}hysteria-client@${name}${plain}   配置：${green}${cfg}${plain}"
        echo -e "  SOCKS5：${green}127.0.0.1:${hy_socks}${plain}   HTTP：${green}127.0.0.1:${hy_http}${plain}"
        echo -e "  带宽 up：${green}${hy_up}${plain}   down：${green}${hy_down}${plain}"
    else
        echo -e "${red}客户端实例 ${name} 可能启动失败，请执行：journalctl -u hysteria-client@${name} -e 查看日志${plain}"
    fi
}

# 列出所有 Hysteria2 实例
list_instances() {
    echo -e "${yellow}== Hysteria2 实例列表 ==${plain}"
    printf "%-8s %-16s %-10s %s\n" "类型" "名称" "状态" "配置文件"
    echo "-------------------------------------------------------------"
    local f name state
    # 服务端：/etc/hysteria/*.yaml 但排除 config.yaml 与 client-*.yaml
    for f in /etc/hysteria/*.yaml; do
        [[ -e "$f" ]] || continue
        name=$(basename "$f" .yaml)
        [[ "$name" == "config" ]] && continue
        [[ "$name" == client-* ]] && continue
        state=$(systemctl is-active "hysteria-server@${name}" 2>/dev/null)
        printf "%-8s %-16s %-10s %s\n" "server" "$name" "$state" "$f"
    done
    # 客户端：/etc/hysteria/client-*.yaml
    for f in /etc/hysteria/client-*.yaml; do
        [[ -e "$f" ]] || continue
        name=$(basename "$f" .yaml)
        name=${name#client-}
        state=$(systemctl is-active "hysteria-client@${name}" 2>/dev/null)
        printf "%-8s %-16s %-10s %s\n" "client" "$name" "$state" "$f"
    done
    echo "-------------------------------------------------------------"
}

# 交互式选择实例：列出编号让用户直接选择，回显到全局变量 ITYPE/INAME/SVC
pick_instance() {
    local -a types names
    local f name
    # 服务端：/etc/hysteria/*.yaml 但排除 config.yaml 与 client-*.yaml
    for f in /etc/hysteria/*.yaml; do
        [[ -e "$f" ]] || continue
        name=$(basename "$f" .yaml)
        [[ "$name" == "config" ]] && continue
        [[ "$name" == client-* ]] && continue
        types+=("server")
        names+=("$name")
    done
    # 客户端：/etc/hysteria/client-*.yaml
    for f in /etc/hysteria/client-*.yaml; do
        [[ -e "$f" ]] || continue
        name=$(basename "$f" .yaml)
        name=${name#client-}
        types+=("client")
        names+=("$name")
    done

    local count=${#names[@]}
    if [[ $count -eq 0 ]]; then
        echo -e "${yellow}暂无实例${plain}"
        return 1
    fi

    echo -e "${yellow}请选择实例：${plain}"
    local i state
    for ((i = 0; i < count; i++)); do
        state=$(systemctl is-active "hysteria-${types[$i]}@${names[$i]}" 2>/dev/null)
        printf "  ${green}%d${plain}) [%-6s] %-16s %s\n" "$((i + 1))" "${types[$i]}" "${names[$i]}" "$state"
    done

    local sel
    read -p "输入序号: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt $count ]]; then
        echo -e "${red}序号无效${plain}"
        return 1
    fi
    local idx=$((sel - 1))
    ITYPE="${types[$idx]}"
    INAME="${names[$idx]}"
    SVC="hysteria-${ITYPE}@${INAME}"
    return 0
}

# 启动/停止/重启实例
control_instance() {
    echo -e "${yellow}== 启动/停止/重启实例 ==${plain}"
    pick_instance || return
    read -p "操作 (start/stop/restart): " act
    case "$act" in
        start|stop|restart)
            systemctl "$act" "$SVC"
            sleep 1
            echo -e "当前状态：${green}$(systemctl is-active "$SVC" 2>/dev/null)${plain}"
            ;;
        *)
            echo -e "${red}操作无效${plain}"
            ;;
    esac
}

status_instance() {
    echo -e "${yellow}== 查看实例状态 ==${plain}"
    pick_instance || return
    systemctl status "$SVC" --no-pager
}

log_instance() {
    echo -e "${yellow}== 查看实例日志 ==${plain}"
    pick_instance || return
    journalctl -u "$SVC" -e --no-pager
}

# 删除实例：停止、禁用、删除配置 (服务端一并删除自签证书)
delete_instance() {
    echo -e "${yellow}== 删除实例 ==${plain}"
    pick_instance || return
    read -p "确认删除实例 ${INAME} (${ITYPE})？[y/N]: " ok
    [[ "$ok" != "y" && "$ok" != "Y" ]] && echo "已取消" && return

    systemctl stop "$SVC" 2>/dev/null
    systemctl disable "$SVC" 2>/dev/null
    if [[ "$ITYPE" == "server" ]]; then
        rm -f "/etc/hysteria/${INAME}.yaml" "/etc/hysteria/${INAME}.crt" "/etc/hysteria/${INAME}.key"
    else
        rm -f "/etc/hysteria/client-${INAME}.yaml"
    fi
    echo -e "${green}实例 ${INAME} 已删除${plain}"
}

main_menu() {
    while true; do
        echo -e ""
        echo -e "${green}==== XrayR + Hysteria2 管理菜单 ====${plain}"
        echo -e "  ${green}1.${plain} 安装/更新 XrayR"
        echo -e "  ${green}2.${plain} 安装 Hysteria2 (二进制 + 客户端模板)"
        echo -e "  ${green}3.${plain} 新增 Hysteria2 服务端实例"
        echo -e "  ${green}4.${plain} 新增 Hysteria2 客户端实例"
        echo -e "  ${green}5.${plain} 实例列表"
        echo -e "  ${green}6.${plain} 启动/停止/重启 实例"
        echo -e "  ${green}7.${plain} 查看实例状态"
        echo -e "  ${green}8.${plain} 查看实例日志"
        echo -e "  ${green}9.${plain} 删除实例"
        echo -e "  ${green}0.${plain} 退出"
        read -p "请输入选项 [0-9]: " choice
        case "$choice" in
            1) install_XrayR ;;
            2) ensure_hysteria2 ;;
            3) add_server_instance ;;
            4) add_client_instance ;;
            5) list_instances ;;
            6) control_instance ;;
            7) status_instance ;;
            8) log_instance ;;
            9) delete_instance ;;
            0) echo "已退出" && break ;;
            *) echo -e "${red}无效选项${plain}" ;;
        esac
    done
}

echo -e "${green}开始安装${plain}"
ensure_base
# install_acme
ensure_xrayr "$1"
ensure_hysteria2
cd "$cur_dir"
main_menu
