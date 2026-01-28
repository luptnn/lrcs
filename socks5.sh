#!/bin/bash

# --- 随机生成工具 ---
# 生成 8 位随机用户名
RAND_USER=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
# 生成 16 位复杂密码（包含大小写和数字）
RAND_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)

echo "------------------------------------------------"
echo "    MicroSocks 全自动增强安装脚本 (Debian/Alpine)"
echo "------------------------------------------------"

# 1. 交互输入
read -p "请输入服务端口 [默认 1080]: " INPUT_PORT
PORT=${INPUT_PORT:-1080}

read -p "请输入用户名 [默认 随机]: " INPUT_USER
USER=${INPUT_USER:-$RAND_USER}

read -p "请输入密码 [默认 随机]: " INPUT_PASS
PASS=${INPUT_PASS:-$RAND_PASS}

# 2. 环境检测与依赖安装
if [ -f /etc/alpine-release ]; then
    OS_TYPE="alpine"
    echo "[1/4] 检测到 Alpine Linux，安装编译工具..."
    apk add --no-cache build-base git
elif [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
    echo "[1/4] 检测到 Debian/Ubuntu，更新并安装编译工具..."
    apt-get update && apt-get install -y build-essential git
else
    echo "❌ 错误：不支持的操作系统。"
    exit 1
fi

# 3. 源码编译
echo "[2/4] 正在拉取源码并编译..."
cd /tmp
rm -rf microsocks
git clone https://github.com/rofl0r/microsocks.git --depth=1
cd microsocks && make
cp microsocks /usr/local/bin/
chmod +x /usr/local/bin/microsocks

# 4. 自动化服务配置
echo "[3/4] 正在配置系统服务..."

if [ "$OS_TYPE" == "debian" ]; then
    # Systemd 配置
    cat > /etc/systemd/system/microsocks.service <<EOF
[Unit]
Description=MicroSocks Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/microsocks -p $PORT -u $USER -P $PASS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable microsocks >/dev/null 2>&1
    systemctl restart microsocks

elif [ "$OS_TYPE" == "alpine" ]; then
    # OpenRC 配置
    cat > /etc/init.d/microsocks <<EOF
#!/sbin/openrc-run

description="MicroSocks Proxy Server"
command="/usr/local/bin/microsocks"
command_args="-p $PORT -u $USER -P $PASS"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/microsocks
    rc-update add microsocks default >/dev/null 2>&1
    rc-service microsocks restart
fi

# 5. 安装报告
clear
echo "================================================"
echo "        🎉 MicroSocks 安装及服务化成功！"
echo "================================================"
echo "  操作系统:  $OS_TYPE"
echo "  监听端口:  $PORT"
echo "  用户名:    $USER"
echo "  密码:      $PASS"
echo "------------------------------------------------"
echo "  SOCKS5 连接地址: "
echo "  socks5://$USER:$PASS@$(curl -s ifconfig.me):$PORT"
echo "================================================"
