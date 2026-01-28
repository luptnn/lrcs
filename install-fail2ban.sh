#!/bin/bash

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
  echo "错误：请以 root 权限运行此脚本。"
  exit 1
fi

# 检查操作系统
if [ -f /etc/alpine-release ]; then
    OS="Alpine"
elif [ -f /etc/debian_version ]; then
    OS="Debian"
else
    echo "不支持的系统。" && exit 1
fi

# --- 函数：安装与修复 ---
install_f2b() {
    echo "--- 1. 设置参数 (直接回车使用 24h, 60m, 3) ---"
    
    read -p "请输入封禁时长 BANTIME [默认 24h]: " USER_BANTIME
    BANTIME=${USER_BANTIME:-"24h"}

    read -p "请输入检测时长 FINDTIME [默认 60m]: " USER_FINDTIME
    FINDTIME=${USER_FINDTIME:-"60m"}

    read -p "请输入最大尝试次数 MAXRETRY [默认 3]: " USER_MAXRETRY
    MAXRETRY=${USER_MAXRETRY:-3}

    echo "--- 2. 清理可能冲突的旧配置 ---"
    # 删除可能导致覆盖的旧 jail.local 和其他碎片配置
    rm -f /etc/fail2ban/jail.local
    rm -f /etc/fail2ban/jail.d/*.conf

    echo "--- 3. 安装/更新必要组件 ---"
    if [ "$OS" = "Alpine" ]; then
        apk update && apk add fail2ban iptables ipset
        rc-update add fail2ban default
        LOG_PATH="/var/log/messages"
        BACKEND="auto"
        [ ! -f "$LOG_PATH" ] && touch "$LOG_PATH"
    else
        apt update && apt install -y fail2ban iptables
        [ -f /var/log/auth.log ] && { LOG_PATH="/var/log/auth.log"; BACKEND="auto"; } || { LOG_PATH=""; BACKEND="systemd"; }
    fi

    echo "--- 4. 写入新配置 ---"
    # 显式地在 [DEFAULT] 和 [sshd] 中都声明一遍以防万一
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
maxretry = $MAXRETRY
$( [ -n "$LOG_PATH" ] && echo "logpath = $LOG_PATH" )
EOF

    echo "--- 5. 强制重启服务 ---"
    if [ "$OS" = "Alpine" ]; then
        rc-service fail2ban restart
    else
        systemctl daemon-reload
        systemctl restart fail2ban
    fi

    # 核心修复步骤：使用 client 指令强制同步一次参数
    echo "--- 6. 正在同步内核参数 ---"
    sleep 2
    fail2ban-client set sshd bantime $BANTIME >/dev/null
    fail2ban-client set sshd maxretry $MAXRETRY >/dev/null

    echo "------------------------------------------------"
    echo "✅ 修复完成！"
    echo "当前实时生效参数："
    echo " - 封禁时长: $(fail2ban-client get sshd bantime) 秒"
    echo " - 重试次数: $(fail2ban-client get sshd maxretry) 次"
    echo "------------------------------------------------"
}

# --- 其他功能保持不变 ---
uninstall_f2b() {
    echo "⚠️  即将彻底删除 Fail2Ban。"
    read -p "确认继续？(y/n): " confirm
    [[ "$confirm" != "y" ]] && return
    fail2ban-client stop >/dev/null 2>&1
    if [ "$OS" = "Alpine" ]; then
        rc-service fail2ban stop && rc-update del fail2ban default && apk del fail2ban
    else
        systemctl stop fail2ban && systemctl disable fail2ban && apt purge -y fail2ban && apt autoremove -y
    fi
    rm -rf /etc/fail2ban /var/lib/fail2ban
    echo "✅ 已彻底移除。"
}

# --- 菜单逻辑 ---
clear
echo "=========================================="
echo "    Fail2Ban 修复与管理工具"
echo "=========================================="
echo " 1. 彻底修复并应用新配置 (24h/60m/3)"
echo " 2. 查看封禁列表"
echo " 3. 实时日志"
echo " 4. 彻底卸载"
echo " 5. 退出"
echo "=========================================="
read -p "选择: " choice
case $choice in
    1) install_f2b ;;
    2) fail2ban-client status sshd ;;
    3) tail -f /var/log/fail2ban.log ;;
    4) uninstall_f2b ;;
    *) exit 0 ;;
esac
