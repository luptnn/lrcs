#!/bin/bash

# 确保脚本以 root 运行
[[ $EUID -ne 0 ]] && echo "请使用 root 运行" && exit 1

# 检测系统并安装基础包
if [ -f /etc/alpine-release ]; then
    OS="Alpine"
    apk update && apk add fail2ban iptables ipset
    rc-update add fail2ban default
    LOG="/var/log/messages"
    BACKEND="auto"
    touch $LOG
else
    OS="Debian"
    apt update && apt install -y fail2ban iptables
    [ -f /var/log/auth.log ] && LOG="/var/log/auth.log" || LOG=""
    [ -z "$LOG" ] && BACKEND="systemd" || BACKEND="auto"
fi

# 交互式参数输入
read -p "封禁时间 BANTIME (默认 24h): " BT
BANTIME=${BT:-"24h"}
read -p "检测窗口 FINDTIME (默认 60m): " FT
FINDTIME=${FT:-"60m"}
read -p "最大重试 MAXRETRY (默认 3): " MR
MAXRETRY=${MR:-3}

# 彻底清理旧配置防止冲突
rm -rf /etc/fail2ban/jail.local /etc/fail2ban/jail.d/*.conf

# 写入最新配置
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime  = $BANTIME
findtime  = $FINDTIME
maxretry = $MAXRETRY
banaction = iptables-multiport
backend = $BACKEND

[sshd]
enabled = true
port    = ssh
$( [[ -n "$LOG" ]] && echo "logpath = $LOG" )
EOF

# 重启服务
if [ "$OS" == "Alpine" ]; then
    rc-service fail2ban restart
else
    systemctl daemon-reload
    systemctl restart fail2ban
fi

echo "------------------------------------------------"
echo "✅ 成功! 系统: $OS, 模式: $BACKEND"
echo "配置: 封禁 $BANTIME, 窗口 $FINDTIME, 重试 $MAXRETRY 次"
# 强制验证 client 状态
sleep 2
fail2ban-client status sshd
echo "------------------------------------------------"
