#!/bin/bash

# --- 权限检查 ---
if [ "$EUID" -ne 0 ]; then 
  echo "错误：请以 root 权限运行此脚本。"
  exit 1
fi

# --- 系统检测 ---
if [ -f /etc/alpine-release ]; then
    OS="Alpine"
elif [ -f /etc/debian_version ]; then
    OS="Debian"
else
    echo "不支持的系统。" && exit 1
fi

# --- 函数：安装与修复 ---
install_f2b() {
    echo "--- 配置封禁参数 (直接回车使用 1y, 60m, 3) ---"
    read -p "请输入封禁时长 BANTIME [默认 8760h]: " USER_BANTIME
    BANTIME=${USER_BANTIME:-"8760h"}
    read -p "请输入检测时长 FINDTIME [默认 60m]: " USER_FINDTIME
    FINDTIME=${USER_FINDTIME:-"60m"}
    read -p "请输入最大尝试次数 MAXRETRY [默认 3]: " USER_MAXRETRY
    MAXRETRY=${USER_MAXRETRY:-3}

    echo "--- 正在清理可能冲突的旧配置 ---"
    rm -f /etc/fail2ban/jail.local
    rm -f /etc/fail2ban/jail.d/*.conf

    echo "--- 正在安装/更新组件 ---"
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

    echo "--- 写入新配置并强制覆盖 ---"
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

    echo "--- 重启并强制同步参数 ---"
    if [ "$OS" = "Alpine" ]; then
        rc-service fail2ban restart
    else
        systemctl daemon-reload
        systemctl restart fail2ban
    fi

    # 关键修复：强制通过 Client 注入参数，确保 maxretry 立即变为 3
    sleep 2
    fail2ban-client set sshd bantime $BANTIME >/dev/null 2>&1
    fail2ban-client set sshd maxretry $MAXRETRY >/dev/null 2>&1

    echo "------------------------------------------------"
    echo "✅ 成功！当前生效：封禁 $BANTIME，重试 $MAXRETRY 次。"
    echo "------------------------------------------------"
}

# --- 函数：卸载 ---
uninstall_f2b() {
    echo "⚠️  警告：即将彻底删除 Fail2Ban。"
    read -p "确认继续？(y/n): " confirm
    [[ "$confirm" != "y" ]] && return
    fail2ban-client stop >/dev/null 2>&1
    if [ "$OS" = "Alpine" ]; then
        rc-service fail2ban stop
        rc-update del fail2ban default
        apk del fail2ban
    else
        systemctl stop fail2ban
        systemctl disable fail2ban
        apt purge -y fail2ban
        apt autoremove -y
    fi
    rm -rf /etc/fail2ban /var/lib/fail2ban
    echo "✅ 已彻底移除。"
}

# --- 菜单逻辑 ---
clear
echo "=========================================="
echo "    Fail2Ban 管理工具 (Debian/Alpine)"
echo "=========================================="
echo " 1. 安装 / 修改参数并重启 (默认 1y/60m/3)"
echo " 2. 查看封禁列表 & 状态"
echo " 3. 查看实时日志 (Ctrl+C 退出)"
echo " 4. 彻底删除 (卸载) Fail2Ban"
echo " 5. 退出脚本"
echo "=========================================="
read -p "请选择 [1-5]: " choice

case $choice in
    1) install_f2b ;;
    2) echo "--- 当前 SSH 封禁状态 ---"
       fail2ban-client status sshd ;;
    3) tail -f /var/log/fail2ban.log ;;
    4) uninstall_f2b ;;
    5) exit 0 ;;
    *) echo "无效选择";;
esac

