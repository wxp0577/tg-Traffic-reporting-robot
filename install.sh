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

get_cpu() { echo $[100-$(vmstat 1 2|tail -1|awk '{print $15}')]"%"; }
get_mem() { free | grep Mem | awk '{printf "%.2f%%", $3/$2 * 100.0}'; }
get_disk() { df -h / | awk 'NR==2 {print $5}'; }

# ================= 数据与状态采集 =================
interface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
[ -z "$interface" ] && interface="eth0"

# 1. 开机至今
boot_bytes=$(cat /proc/net/dev | grep "$interface:" | awk '{print $2 + $10}')
boot_gb=$(awk "BEGIN {printf \"%.3f GB\", $boot_bytes / 1024 / 1024 / 1024}")

# 2. 今日与当月 (从 vnstat 获取)
today_gb="初始化中..."
month_gb="初始化中..."
if command -v vnstat &> /dev/null; then
    stats=$(vnstat -i $interface --oneline 2>/dev/null)
    if echo "$stats" | grep -q ";"; then
        today_gb=$(to_gb "$(echo "$stats" | cut -d ';' -f 6)")
        month_gb=$(to_gb "$(echo "$stats" | cut -d ';' -f 11)")
    fi
fi

# 3. 脚本配置信息
current_interval="未知"
[ -f "/root/tg_traffic_run.sh" ] && current_interval=$(grep "sleep " /root/tg_traffic_run.sh | awk '{print $2}')

# 4. 服务状态
if systemctl is-active --quiet tgtraffic; then
    script_status="🟢 运行中"
else
    [ -f "/etc/systemd/system/tgtraffic.service" ] && script_status="⏸️ 已暂停" || script_status="🔴 未安装"
fi

# ================= 显示主菜单 =================
clear
echo "===================================================="
echo "      🚀 TG 机器人全能监控控制台"
echo "===================================================="
echo "  🤖 脚本状态 : $script_status"
echo "  ⏱️ 推送频率 : 每 [ $current_interval ] 秒发送一次"
echo "  🌐 监控网卡 : $interface"
echo "----------------------------------------------------"
echo "  🔋 开机累计 : $boot_gb"
echo "  📅 当月流量 : $month_gb (1号重置)"
echo "  📆 今日流量 : $today_gb"
echo "  🖥️ 系统状态 : CPU $(get_cpu) | 内存 $(get_mem) | 硬盘 $(get_disk)"
echo "===================================================="
echo "  1. 🛠️ 安装 / 更新配置 (设置机器名/Token/ID)"
echo "  2. 🗑️ 一键彻底卸载"
echo "  3. ⏸️ 暂停推送服务"
echo "  4. ▶️ 恢复推送服务"
echo "  5. ⏱️ 修改推送频率"
echo "  6. 🔄 仅更新脚本 (保留当前配置)"
echo "  0. ❌ 退出菜单"
echo "===================================================="
read -p "👉 请选择操作 [0-6]: " action

# ================= 执行逻辑 =================
case "$action" in
    0) echo "👋 已退出。"; exit 0 ;;
    2) 
        systemctl stop tgtraffic &>/dev/null
        systemctl disable tgtraffic &>/dev/null
        rm -f /etc/systemd/system/tgtraffic.service /root/tg_traffic_run.sh /usr/local/bin/liuliang
        systemctl daemon-reload
        echo "✅ 卸载成功！"; exit 0 
        ;;
    3) systemctl stop tgtraffic &>/dev/null; echo "⏸️ 已暂停！"; exit 0 ;;
    4) systemctl start tgtraffic &>/dev/null; echo "▶️ 已恢复！"; exit 0 ;;
    5)
        [ ! -f "/root/tg_traffic_run.sh" ] && echo "❌ 请先安装！" && exit 1
        read -p "👉 输入新间隔(秒): " new_int
        if [[ "$new_int" =~ ^[0-9]+$ ]]; then
            sed -i "s/sleep [0-9]*/sleep $new_int/" /root/tg_traffic_run.sh
            systemctl restart tgtraffic
            echo "✅ 频率已更新为 $new_int 秒。"; exit 0
        fi
        ;;
    6)
        echo "⏳ 正在从 GitHub 获取最新脚本..."
        wget -qO /usr/local/bin/liuliang https://raw.githubusercontent.com/wxp0577/tg-Traffic-reporting-robot/refs/heads/main/install.sh
        chmod +x /usr/local/bin/liuliang
        echo "✅ 脚本已更新！请重新运行 liuliang 呼出菜单。"
        exit 0
        ;;
    1)
        echo ""
        read -p "👉 1. 给这台 VPS 起个名字: " vps_name
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
    if [ -z "\$val" ] || [ -z "\$unit" ]; then echo "0.000 GB"; return; fi
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
    # 核心修改：强制使用亚洲/上海（北京）时间
    TIME=\$(TZ='Asia/Shanghai' date +"%Y-%m-%d %H:%M:%S")
    IP=\$(curl -s http://ipinfo.io/ip || curl -s ifconfig.me)
    CPU=\$[100-\$(vmstat 1 2|tail -1|awk '{print \$15}')]"%"
    MEM=\$(free | grep Mem | awk '{printf "%.2f%%", \$3/\$2 * 100.0}')
    DISK=\$(df -h / | awk 'NR==2 {print \$5}')
    BOOT_BYTES=\$(cat /proc/net/dev | grep "$interface:" | awk '{print \$2 + \$10}')
    ACC_GB=\$(awk "BEGIN {printf \"%.3f GB\", \$BOOT_BYTES / 1024 / 1024 / 1024}")
    STATS=\$(vnstat -i $interface --oneline 2>/dev/null)
    if echo "\$STATS" | grep -q ";"; then
        TODAY_GB=\$(to_gb "\$(echo "\$STATS" | cut -d ';' -f 6)")
        MONTH_GB=\$(to_gb "\$(echo "\$STATS" | cut -d ';' -f 11)")
    else
        TODAY_GB="统计中..."; MONTH_GB="统计中..."
    fi
    MESSAGE="🖥 <b>VPS 状态上报</b>%0A---------------------------%0A📛 <b>机器名称：</b>$vps_name%0A🌐 <b>IP 地址：</b>\${IP}%0A📅 <b>上报时间：</b>\${TIME}%0A%0A📊 <b>流量统计：</b>%0A🔋 <b>开机累计：</b>\${ACC_GB}%0A🗓 <b>当月流量：</b>\${MONTH_GB}%0A📅 <b>今日使用：</b>\${TODAY_GB}%0A%0A⚙️ <b>系统性能：</b>%0A💿 <b>CPU 占用：</b>\${CPU}%0A📟 <b>内存占用：</b>\${MEM}%0A💽 <b>硬盘占用：</b>\${DISK}"
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
        echo " 🎉 安装/更新完成！快捷键: liuliang"
        echo "===================================================="
        exit 0
        ;;
    *) echo "❌ 选项错误"; exit 1 ;;
esac
