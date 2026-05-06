#!/bin/bash


#数据库连接信息
DB_HOST="127.0.0.1"      # 数据库IP
DB_USER="readonly_user"  # 数据库用户名
DB_PASS="password123"    # 数据库密码
DB_NAME="assets_db"      # 数据库名称
QUERY="SELECT ip_address FROM servers WHERE status='active';"


#获取服务器列表
# 使用 mysql -e 执行命令，-N 不打印表头，-s 不打印边框
IP_LIST=$(mysql -h${DB_HOST} -u${DB_USER} -p${DB_PASS} ${DB_NAME} -N -s -e "${QUERY}")

if [ -z "$IP_LIST" ]; then
    echo "[ERROR] 未能在数据库中找到有效 IP，请检查数据！"
    exit 1
fi

#单个 IP check函数
check_server() {
    local ip=$1
    local target_port=22 # 默认测试 SSH 端口

    echo "--- 正在检测: $ip ---"

    # --- ICMP Ping 测试 ---
    # -c 2: 发送2个包; -i 间隔0.2秒; -W 等待1秒超时
    ping -c 2 -i 0.2 -W 1 $ip > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  [OK] Ping 响应"
    else
        echo "  [FAIL] Ping 无法访问"
    fi

    # --- Telnet/NC 端口测试 (验证服务是否存活) ---
    # -z 扫描模式; -w 超时2秒
    nc -z -w 2 $ip $target_port > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  [OK] 端口 $target_port (Telnet) 正常"
    else
        echo "  [FAIL] 端口 $target_port (Telnet) 拒绝连接"
    fi
}

#执行
echo "[INFO] 开始巡检，总计 $(echo "$IP_LIST" | wc -l) 台设备..."

for ip in $IP_LIST
do
    check_server $ip
done

echo "--- 巡检结束 ---"
