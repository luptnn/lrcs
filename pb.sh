#!/usr/bin/env bash
#=================================================
#  Description: Serverstat-Rust 一键安装脚本
#  Version: v1.0.0
#=================================================

Info="\033[32m[信息]\033[0m"
Error="\033[31m[错误]\033[0m"
Warning="\033[33m[警告]\033[0m"
Tip="\033[32m[注意]\033[0m"

working_dir=/opt/ServerStatus

client_dir="$working_dir/client"
server_dir="$working_dir/server"

tmp_server_file=/tmp/stat_server
tmp_client_file=/tmp/stat_client

client_file="$client_dir/stat_client"
server_file="$server_dir/stat_server"
client_conf=/etc/systemd/system/stat_client.service
server_conf=/etc/systemd/system/stat_server.service
server_toml="$server_dir/config.toml"

bak_dir=/usr/local/ServerStatus/bak/

if [ "${MIRROR}" = CN ]; then
    echo cn
fi

# 检测系统类型
function detect_system() {
    if [ -f /etc/alpine-release ]; then
        SYSTEM="alpine"
    elif [ -f /etc/debian_version ]; then
        SYSTEM="debian"
    elif [ -f /etc/redhat-release ]; then
        SYSTEM="rhel"
    elif [ -f /etc/arch-release ]; then
        SYSTEM="arch"
    else
        # 尝试通过其他方式检测
        if [ -f /etc/os-release ]; then
            if grep -qi "alpine" /etc/os-release; then
                SYSTEM="alpine"
            elif grep -qi "debian" /etc/os-release; then
                SYSTEM="debian"
            elif grep -qi "ubuntu" /etc/os-release; then
                SYSTEM="debian"
            elif grep -qi "centos" /etc/os-release; then
                SYSTEM="rhel"
            elif grep -qi "fedora" /etc/os-release; then
                SYSTEM="rhel"
            elif grep -qi "arch" /etc/os-release; then
                SYSTEM="arch"
            else
                echo -e "${Error} 无法检测系统类型"
                exit 1
            fi
        else
            echo -e "${Error} 无法检测系统类型"
            exit 1
        fi
    fi
    echo -e "${Info} 检测到系统类型: $SYSTEM"
}

detect_system

# 检查架构
function check_arch() {
    case $(uname -m) in
        x86_64)
            arch=x86_64
        ;;
        aarch64 | aarch64_be | arm64 | armv8b | armv8l)
            arch=aarch64
        ;;
        *)
            echo -e "${Error} 暂不支持该系统架构"
            exit 1
        ;;
    esac
}

check_arch

# 检查发行版
function check_release() {
    if [[ $SYSTEM == "alpine" ]]; then
        release="apk"
    elif [[ $SYSTEM == "debian" ]]; then
        release="deb"
    elif [[ $SYSTEM == "rhel" ]]; then
        release="rpm"
    elif [[ $SYSTEM == "arch" ]]; then
        release="pkg"
    else
        echo -e "${Error} 暂不支持该 Linux 发行版"
        exit 1
    fi
}

check_release

# 检查并安装必需工具
function install_tool() {
    echo -e "${Info} 检查并安装必需工具..."
    
    # 检查unzip
    if ! command -v unzip &> /dev/null; then
        echo -e "${Info} unzip not found. Installing unzip..."
        case $release in
            apk)
                apk add --no-cache unzip
                ;;
            deb)
                apt-get update
                apt-get install -y unzip
                ;;
            rpm)
                yum install -y unzip
                ;;
            pkg)
                pacman -S unzip --noconfirm
                ;;
        esac
    fi

    # 检查wget
    if ! command -v wget &> /dev/null; then
        echo -e "${Info} wget not found. Installing wget..."
        case $release in
            apk)
                apk add --no-cache wget
                ;;
            deb)
                apt-get update
                apt-get install -y wget
                ;;
            rpm)
                yum install -y wget
                ;;
            pkg)
                pacman -S wget --noconfirm
                ;;
        esac
    fi

    # Alpine系统需要额外检查openrc
    if [[ $SYSTEM == "alpine" ]]; then
        if ! command -v rc-status &> /dev/null; then
            echo -e "${Info} OpenRC not found. Installing openrc..."
            apk add --no-cache openrc
        fi
    fi
}

# 获取服务端信息
function input_upm() {
    echo -e "${Tip} 请输入服务端的信息"
    echo -e "${Tip} 格式为: protocol://username:password@master:port"
    echo -e "${Tip} 示例: http://h1:p1@127.0.0.1:8080"
    echo -e "${Tip} 或: grpc://h1:p1@127.0.0.1:8081"
    echo -n "请输入: "
    read -re UPM
    
    # 验证输入格式
    if [[ ! $UPM =~ ^(http|grpc)://[^:]+:[^@]+@[^:]+:[0-9]+$ ]]; then
        echo -e "${Error} 格式不正确！请按照示例格式输入"
        echo -e "${Error} 示例: http://h1:p1@127.0.0.1:8080"
        exit 1
    fi
}

function get_conf() {
    PROTOCOL=$(echo "${UPM}" |sed "s/\///g" |awk -F "[:@]" '{print $1}')
    USER=$(echo "${UPM}" |sed "s/\///g" |awk -F "[:@]" '{print $2}')
    PASSWD=$(echo "${UPM}" |sed "s/\///g" |awk -F "[:@]" '{print $3}')
    if [ "${PROTOCOL}" = "grpc" ]; then
        echo -e "${Info} 使用 grpc 连接"
        MASTER=$(echo "${UPM}" |awk -F "[@]" '{print $2}')
    else
        echo -e "${Info} 使用 http 连接"
        MASTER=$(echo "${UPM}" |awk -F "[@]" '{print $2}')/report
    fi
    
    echo -e "${Info} 配置信息:"
    echo -e "${Info} 协议: $PROTOCOL"
    echo -e "${Info} 用户名: $USER"
    echo -e "${Info} 密码: $PASSWD"
    echo -e "${Info} 服务器地址: $MASTER"
}

# 检查服务
function check_client() {
    if pgrep -f "stat_client" > /dev/null; then
        CPID=$(pgrep -f "stat_client")
    else
        CPID=""
    fi
}

# 获取仓库最新版本号
function get_latest_version() {
    api_url="https://api.github.com/repos/zdz/ServerStatus-Rust/releases/latest"
    local latest_version
    latest_version=$(wget -qO- "$api_url" 2>/dev/null | grep -Po '(?<="tag_name": ")[^"]*' || echo "v1.0.0")
    echo "$latest_version"
}

# 写入 systemd 配置
function write_client() {
    local latest_version
    latest_version=$(get_latest_version)
    echo -e "${Info} 写入systemd配置中"
    
    mkdir -p $(dirname ${client_conf})
    
    cat >${client_conf} <<-EOF
#Version=${latest_version}
[Unit]
Description=Serverstat-Rust Client
After=network.target

[Service]
Type=simple
Environment="RUST_BACKTRACE=1"
WorkingDirectory=${working_dir}
ExecStart=$client_file -a "${PROTOCOL}://${MASTER}" -u ${USER} -p ${PASSWD}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 ${client_conf}
}

# Alpine系统使用openrc
function write_client_openrc() {
    local latest_version
    latest_version=$(get_latest_version)
    echo -e "${Info} 写入OpenRC配置中"
    
    cat >/etc/init.d/stat_client <<-EOF
#!/sbin/openrc-run
#Version=${latest_version}

name="stat_client"
description="ServerStatus-Rust Client"
command="$client_file"
command_args="-a \"${PROTOCOL}://${MASTER}\" -u ${USER} -p ${PASSWD}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
directory="${working_dir}"
output_log="/var/log/stat_client.log"
error_log="/var/log/stat_client.err"

depend() {
    need net
    after firewall
}

start_pre() {
    export RUST_BACKTRACE=1
}
EOF
    
    chmod +x /etc/init.d/stat_client
}

# 获取二进制文件 - 客户端
function get_client_binary() {
    if [ "${CN}" = true ] || [ "${MIRROR}" = "CN" ]; then
        MIRROR_URL="https://ghproxy.com/"
    else
        MIRROR_URL=""
    fi
    
    install_tool
    cd /tmp || exit

    echo -e "${Info} 正在下载 ServerStatus-Rust 客户端..."

    # 清理旧文件
    rm -f /tmp/stat_client /tmp/client-*.zip
    
    # 下载客户端
    echo -e "${Info} 下载客户端..."
    wget --no-check-certificate -q "${MIRROR_URL}https://github.com/zdz/Serverstatus-Rust/releases/latest/download/client-${arch}-unknown-linux-musl.zip"
    
    if [ ! -f "client-${arch}-unknown-linux-musl.zip" ]; then
        echo -e "${Error} 客户端文件下载失败！"
        exit 1
    fi
    
    # 解压文件
    unzip -o "client-${arch}-unknown-linux-musl.zip"
    
    if [ ! -f "stat_client" ]; then
        # 尝试从压缩包中直接提取
        unzip -j "client-${arch}-unknown-linux-musl.zip" "stat_client" -d /tmp
    fi
    
    if [ ! -f "/tmp/stat_client" ]; then
        echo -e "${Error} 解压后未找到客户端文件！"
        exit 1
    fi
    
    echo -e "${Info} 客户端文件下载和解压成功！"
}

# 启用客户端服务
function enable_client() {
    if [[ $SYSTEM == "alpine" ]]; then
        write_client_openrc
        rc-update add stat_client default 2>/dev/null || true
        rc-service stat_client start
    else
        write_client
        systemctl daemon-reload
        systemctl enable stat_client --now
    fi
    
    sleep 2
    check_client
    if [[ -n ${CPID} ]]; then
        echo -e "${Info} Status Client 启动成功！"
        echo -e "${Info} 客户端PID: $CPID"
    else
        echo -e "${Error} Status Client 启动失败！"
        echo -e "${Warning} 请检查配置信息和服务端状态"
    fi
}

# 安装客户端
function install_client() {
    echo -e "${Info} 开始安装 ServerStatus-Rust 客户端"
    echo -e "${Info} 系统架构: $arch"
    echo -e "${Info} 发行版: $release"
    
    # 第一步：下载客户端二进制文件
    get_client_binary
    
    # 第二步：创建目录并复制文件
    mkdir -p ${client_dir}
    
    if [ -f "/tmp/stat_client" ]; then
        cp /tmp/stat_client $client_file
        chmod +x $client_file
        echo -e "${Info} 客户端文件已复制到: $client_file"
    else
        echo -e "${Error} 未找到客户端文件"
        ls -la /tmp/
        exit 1
    fi
    
    # 第三步：提示用户输入服务端信息
    echo -e "${Info} "
    echo -e "${Info} ==========================================="
    echo -e "${Info} 现在需要您输入服务端连接信息"
    echo -e "${Info} ==========================================="
    
    input_upm
    get_conf
    
    # 第四步：启用客户端服务
    enable_client
    
    # 显示最终信息
    echo -e "${Info} "
    echo -e "${Info} ==========================================="
    echo -e "${Info} 安装完成！"
    echo -e "${Info} ==========================================="
    echo -e "${Info} 客户端文件: $client_file"
    echo -e "${Info} 服务配置文件: $(if [[ $SYSTEM == "alpine" ]]; then echo "/etc/init.d/stat_client"; else echo "$client_conf"; fi)"
    echo -e "${Info} 工作目录: $working_dir"
    echo -e "${Info} "
    echo -e "${Tip} 常用命令:"
    echo -e "${Tip} 启动客户端: $(if [[ $SYSTEM == "alpine" ]]; then echo "rc-service stat_client start"; else echo "systemctl start stat_client"; fi)"
    echo -e "${Tip} 停止客户端: $(if [[ $SYSTEM == "alpine" ]]; then echo "rc-service stat_client stop"; else echo "systemctl stop stat_client"; fi)"
    echo -e "${Tip} 重启客户端: $(if [[ $SYSTEM == "alpine" ]]; then echo "rc-service stat_client restart"; else echo "systemctl restart stat_client"; fi)"
    echo -e "${Tip} 查看状态: $(if [[ $SYSTEM == "alpine" ]]; then echo "rc-service stat_client status"; else echo "systemctl status stat_client"; fi)"
    echo -e "${Tip} 查看日志: journalctl -u stat_client -f"
    echo -e "${Info} ==========================================="
}

# 主函数 - 自动执行安装
function main() {
    echo -e "${Info} ==========================================="
    echo -e "${Info} ServerStatus-Rust 客户端一键安装脚本"
    echo -e "${Info} ==========================================="
    
    # 检查是否以root运行
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Error} 此脚本需要以root权限运行"
        echo -e "${Tip} 请使用: sudo bash $0"
        exit 1
    fi
    
    # 检查是否已经安装
    if [ -f "$client_file" ]; then
        echo -e "${Warning} 检测到客户端已安装"
        read -p "是否重新安装？(y/N): " reinstall
        if [[ $reinstall =~ ^[Yy]$ ]]; then
            echo -e "${Info} 开始卸载旧版本..."
            # 停止服务
            if [[ $SYSTEM == "alpine" ]]; then
                rc-service stat_client stop 2>/dev/null || true
                rc-update del stat_client 2>/dev/null || true
                rm -f /etc/init.d/stat_client
            else
                systemctl stop stat_client 2>/dev/null || true
                systemctl disable stat_client 2>/dev/null || true
                rm -f $client_conf
                systemctl daemon-reload
            fi
            rm -rf $client_dir
            echo -e "${Info} 旧版本已卸载"
        else
            echo -e "${Info} 退出安装"
            exit 0
        fi
    fi
    
    # 执行安装
    install_client
}

# 执行主函数
main "$@"
