#!/bin/bash

# ================= 性能采集函数 =================

# 1. 流量单位转换 (强制转为 GB)
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

# 2. 获取当前 IP 地址
get_ip() {
    local ip=$(curl -s http://ipinfo.io/ip)
    [ -z "$ip" ] && ip=$(curl -s ifconfig.me)
    echo "$ip"
}

# 3. 获取 CPU 占用率
get_cpu() {
    echo $[100-$(vmstat 1 2|tail -1|awk '{print $15}')]"%"
}

# 4. 获取内存占用率
get_mem() {
    free | grep Mem | awk '{printf "%.2f%%", $3/$2 * 100.0}'
}

# 5. 获取磁盘占用率 (根目录)
get_disk() {
    df -h / | awk 'NR==2 {print $5}'
}

# ================= 数据采集 & 变量 =================
interface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$interface" ] && interface="eth0"

# 仪表盘显示数据
boot_bytes=$(cat /proc/net/dev | grep "$interface:" | awk '{print $2 + $10}')
boot_gb=$(awk "BEGIN {printf \"%.3f GB\", $boot_bytes / 1024 / 1024 / 1024}")
today_gb="等待统计..."
if command -v vnstat &> /dev/null; then
    stats=$(vnstat -i $interface --oneline 2>/dev/null)
    [ -n "$stats" ] && today_gb=$(to_gb "$(echo "$stats" | cut -d ';' -f 6)")
fi

# ================= 显示主菜单 =================
clear
echo "===================================================="
echo "      🚀 TG 机器人全能监控控制台"
echo "===================================================="
echo "  🌐 监控网卡 : $interface"
echo "  🔋 累计流量 : $boot_gb (自开机)"
echo "  📅 今日流量 : $today_gb"
echo "  🖥️ 系统状态 : CPU $(get_cpu) | 内存 $(get_mem)"
echo "===================================================="
echo "  1. 🛠️ 安装 / 更新监控 (并设置机器名)"
echo "  2. 🗑️ 一键彻底卸载"
echo "  0. ❌ 退出"
echo "===================================================="
read -p "👉 请选择 [0-2]: " action

# ================= 卸载逻辑 =================
if [ "$action" == "2" ]; then
    systemctl stop tgtraffic &>/dev/null
    systemctl disable tgtraffic &>/dev/null
    rm -f /etc/systemd/system/tgtraffic.service /root/tg_traffic_run.sh /usr/local/bin/liuliang
    systemctl daemon-reload
    echo "✅ 卸载成功！"
    exit 0

# ================= 安装逻辑 =================
elif [ "$action" == "1" ]; then
    echo ""
    read -p "👉 1. 请给这台 VPS 起个名字 (如: 香港A, 美国01): " vps_name
    read -p "👉 2. 发送时间间隔 (秒): " interval
    read -p "👉 3. 粘贴 Bot Token: " bot_token
    read -p "👉 4. 粘贴 Chat ID: " chat_id

    apt-get update -y &> /dev/null
    apt-get install vnstat curl bc -y &> /dev/null

    # 快捷指令
    cp -f $(readlink -f "$0") /usr/local/bin/liuliang && chmod +x /usr/local/bin/liuliang

    # 生成推送脚本
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
    TODAY_GB="0.000 GB"
    [ -n "\$STATS" ] && TODAY_GB=\$(to_gb "\$(echo "\$STATS" | cut -d ';' -f 6)")

    MESSAGE="🖥 <b>VPS 状态上报</b>%0A---------------------------%0A📛 <b>机器名称：</b>$vps_name%0A🌐 <b>IP 地址：</b>\${IP}%0A📅 <b>上报时间：</b>\${TIME}%0A%0A📊 <b>流量统计：</b>%0A🔋 <b>开机累计：</b>\${ACC_GB}%0A📅 <b>今日使用：</b>\${TODAY_GB}%0A%0A⚙️ <b>系统性能：</b>%0A💿 <b>CPU 占用：</b>\${CPU}%0A📟 <b>内存占用：</b>\${MEM}%0A💽 <b>硬盘占用：</b>\${DISK}"

    curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d "chat_id=$chat_id" -d "text=\${MESSAGE}" -d "parse_mode=HTML" > /dev/null
    sleep $interval
done
EOF
    chmod +x /root/tg_traffic_run.sh

    # 服务配置
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
fi
