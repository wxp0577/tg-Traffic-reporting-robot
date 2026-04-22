#!/bin/bash

# ================= 性能采集函数 =================

to_gb() {
    local val=$(echo "$1" | awk '{print $1}')
    local unit=$(echo "$1" | awk '{print $2}')
    if [ -z "$val" ] || [ -z "$unit" ]; then echo "0.000 GB"; return; fi
    awk -v v="$val" -v u="$unit" 'BEGIN {
        if (u ~ /KiB|KB/) { printf "%.3f GB", v / 1024 / 1024 }
        else if (u ~ /MiB|MB/) { printf "%.3f GB", v / 1024 }
        else if (u ~ /GiB|GB/) { printf "%.3f GB", v }
        else if (u ~ /TiB|TB/) { printf "%.3f GB", v * 1024 }
        else if (u ~ /B/) { printf "%.6f GB", v / 1024 / 1024 / 1024 }
        else { print v " " u }
    }'
}

get_cpu() {
    echo $[100-$(vmstat 1 2|tail -1|awk '{print $15}')]"%"
}

get_mem() {
    free | grep Mem | awk '{printf "%.2f%%", $3/$2 * 100.0}'
}

get_disk() {
    df -h / | awk 'NR==2 {print $5}'
}

# ================= 数据与状态采集 =================
interface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$interface" ] && interface="eth0"

boot_bytes=$(cat /proc/net/dev | grep "$interface:" | awk '{print $2 + $10}')
boot_gb=$(awk "BEGIN {printf \"%.3f GB\", $boot_bytes / 1024 / 1024 / 1024}")

today_gb="等待统计..."
if command -v vnstat &> /dev/null; then
    stats=$(vnstat -i $interface --oneline 2>/dev/null)
    if echo "$stats" | grep -q ";"; then
        today_gb=$(to_gb "$(echo "$stats" | cut -d ';' -f 6)")
    else
        today_gb="数据初始化中(约5分)..."
    fi
fi

# 核心新增：检测后台服务状态
if systemctl is-active --quiet tgtraffic; then
    script_status="🟢 运行中"
else
    # 检查服务文件是否存在，判断是已停止还是未安装
    if [ -f "/etc/systemd/system/tgtraffic.service" ]; then
        script_status="⏸️ 已暂停 (待恢复)"
    else
        script_status="🔴 未运行 (未安装)"
    fi
fi

# ================= 显示主菜单 =================
clear
echo "===================================================="
echo "      🚀 TG 机器人全能监控控制台"
echo "===================================================="
echo "  🤖 脚本状态 : $script_status"
echo "  🌐 监控网卡 : $interface"
echo "  🔋 累计流量 : $boot_gb (自开机)"
echo "  📅 今日流量 : $today_gb"
echo "  🖥️ 系统状态 : CPU $(get_cpu) | 内存 $(get_mem)"
echo "===================================================="
echo "  1. 🛠️ 安装 / 更新监控 (并设置机器名)"
echo "  2. 🗑️ 一键彻底卸载"
echo "  3. ⏸️ 暂停推送服务"
echo "  4. ▶️ 恢复推送服务"
echo "  0. ❌ 退出"
echo "===================================================="
read -p "👉 请选择操作 [0-4]: " action

# ================= 菜单执行逻辑 =================
if [ "$action" == "0" ]; then
    echo "👋 已退出。"
    exit 0

elif [ "$action" == "2" ]; then
    systemctl stop tgtraffic &>/dev/null
    systemctl disable tgtraffic &>/dev/null
    rm -f /etc/systemd/system/tgtraffic.service /root/tg_traffic_run.sh /usr/local/bin/liuliang
    systemctl daemon-reload
    echo "✅ 卸载成功！"
    exit 0

elif [ "$action" == "3" ]; then
    systemctl stop tgtraffic &>/dev/null
    echo "⏸️ 推送服务已暂停！"
    exit 0

elif [ "$action" == "4" ]; then
    systemctl start tgtraffic &>/dev/null
    echo "▶️ 推送服务已恢复运行！"
    exit 0

elif [ "$action" == "1" ]; then
    echo ""
    read -p "👉 1. 请给这台 VPS 起个名字 (如: 香港A, 美国01): " vps_name
    read -p "👉 2. 发送时间间隔 (秒): " interval
    read -p "👉 3. 粘贴 Bot Token: " bot_token
    read -p "👉 4. 粘贴 Chat ID: " chat_id

    apt-get update -y &> /dev/null
    apt-get install vnstat curl bc -y &> /dev/null

    wget -qO /usr/local/bin/liuliang https://raw.githubusercontent.com/wxp0577/tg-Traffic-reporting-robot/refs/heads/main/install.sh
    chmod +x /usr/local/bin/liuliang

    cat > /root/tg_traffic_run.sh <<EOF
#!/bin/bash
to_gb() {
    local val=\$(echo "\$1" | awk '{print \$1}')
    local unit=\$(echo "\$1" | awk '{print \$2}')
    awk -v v="\$val" -v u="\$unit" 'BEGIN {
        if (u ~ /KiB|KB/) { printf "%.3f GB", v / 1024 / 1024 }
        else if (u ~ /MiB|MB/) { printf "%.3f GB", v / 1024 }
        else if (u ~ /GiB|GB/) { printf "%.3f GB", v }
        else if (u ~ /TiB|TB/) { printf "%.3f GB", v * 1024 }
        else if (u ~ /B/) { printf "%.6f GB", v / 1024 / 1024 / 1024 }
        else { print v " " u }
    }'
}

while true; do
    TIME=\$(date +"%Y-%m-%d %H:%M:%S")
    IP=\$(curl -s http://ipinfo.io/ip || curl -s ifconfig.me)
    CPU=\$[100-\$(vmstat 1 2|tail -1|awk '{print \$15}')]"%"
    MEM=\$(free | grep Mem | awk '{printf "%.2f%%", \$3/\$2 * 100.0}')
    DISK=\$(df -h / | awk 'NR==2 {print \$5}')
    
    BOOT_BYTES=\$(cat /proc/net/dev | grep "$interface:" | awk '{print \$2 + \$10}')
    ACC_GB=\$(awk "BEGIN {printf \"%.3f GB\", \$BOOT_BYTES / 1024 / 1024 / 1024}")
    
    STATS=\$(vnstat -i $interface --oneline 2>/dev/null)
    if echo "\$STATS" | grep -q ";"; then
        TODAY_GB=\$(to_gb "\$(echo "\$STATS" | cut -d ';' -f 6)")
    else
        TODAY_GB="数据初始化中..."
    fi

    MESSAGE="🖥 <b>VPS 状态上报</b>%0A---------------------------%0A📛 <b>机器名称：</b>$vps_name%0A🌐 <b>IP 地址：</b>\${IP}%0A📅 <b>上报时间：</b>\${TIME}%0A%0A📊 <b>流量统计：</b>%0A🔋 <b>开机累计：</b>\${ACC_GB}%0A📅 <b>今日使用：</b>\${TODAY_GB}%0A%0A⚙️ <b>系统性能：</b>%0A💿 <b>CPU 占用：</b>\${CPU}%0A📟 <b>内存占用：</b>\${MEM}%0A💽 <b>硬盘占用：</b>\${DISK}"

    curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d "chat_id=$chat_id" -d "text=\${MESSAGE}" -d "parse_mode=HTML" > /dev/null
    sleep $interval
done
EOF
    chmod +x /root/tg_traffic_run.sh

    cat > /etc/systemd/system/tgtraffic.service <<EOF
[Unit]
Description=TG Traffic Bot Service
After=network.target
[Service]
ExecStart=/root/tg_traffic_run.sh
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable tgtraffic && systemctl restart tgtraffic
    echo "===================================================="
    echo " 🎉 安装成功！快捷键: liuliang"
    echo "===================================================="
    exit 0
else
    echo "❌ 选项错误，请重新输入"
    exit 1
fi
