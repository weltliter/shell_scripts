#!/bin/bash


# 阈值与 Webhook 配置区域
THRESHOLD_DISK=85   # 磁盘使用率告警阈值
THRESHOLD_MEM=90    # 内存使用率告警阈值
# Webhook 地址
WEBHOOK_URL="https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN_HERE" 

# 初始化变量
ALERT_MSG=""
HOST_IP=$(hostname -I | awk '{print $1}') # 获取本机局域网 IP
DATETIME=$(date +"%Y-%m-%d %H:%M:%S")

# 探针：获取并判断资源状态
# 根目录磁盘
# df -h: 查看磁盘挂载；awk '$NF=="/"{print $5}': 获取挂载点是 / 的那行的第 5 列 (例如 45%)
# sed 's/%//': 把百分号切掉，只留纯数字方便对比
DISK_USE=$(df -h | awk '$NF=="/"{print $5}' | sed 's/%//')

if [ "$DISK_USE" -gt "$THRESHOLD_DISK" ]; then
    ALERT_MSG="${ALERT_MSG}- 根目录磁盘使用率已达 **${DISK_USE}%** (阈值: ${THRESHOLD_DISK}%)\n"
fi

# 物理内存
# free -m: 以 MB 为单位看内存；计算公式：(已用/总计)*100
MEM_USE=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')

if [ "$MEM_USE" -gt "$THRESHOLD_MEM" ]; then
    ALERT_MSG="${ALERT_MSG}- 内存使用率已飙升至 **${MEM_USE}%** (阈值: ${THRESHOLD_MEM}%)\n"
fi

# CPU 负载
# 获取 1 分钟平均负载 (Load Average)
CPU_LOAD=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1)
CPU_CORES=$(nproc) # 获取系统 CPU 核心数

# Bash 的 if 不支持小数比较，所以这里用 awk 代理计算。如果 负载 > 核心数，返回 1
IS_HIGH_LOAD=$(echo "$CPU_LOAD $CPU_CORES" | awk '{if ($1 > $2) print 1; else print 0}')

if [ "$IS_HIGH_LOAD" -eq 1 ]; then
    ALERT_MSG="${ALERT_MSG}- CPU 1分钟负载达 **${CPU_LOAD}** (已超核心数 ${CPU_CORES}，系统可能卡顿)\n"
fi


# 告警：组装 JSON 并发送 HTTP 请求
if [ -n "$ALERT_MSG" ]; then
    echo "[WARNING] 发现资源异常，正在向工作群发送告警..."
    
    # 使用 Here Document (<<EOF) 语法，优雅地生成多行 JSON 数据
    JSON_PAYLOAD=$(cat <<EOF
    {
        "msgtype": "markdown",
        "markdown": {
            "title": "服务器资源异常告警",
            "text": "### 生产服务器资源告警\n**时间:** ${DATETIME}\n**主机 IP:** ${HOST_IP}\n**异常详情:**\n${ALERT_MSG}\n> ！"
        }
    }
EOF
)

    # 用 curl 模拟浏览器/Postman，发送 POST 请求给机器人
    # -s: 静默模式；-X: 指定请求方法；-H: 指定请求头；-d: 携带的数据
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD" > /dev/null
    
    echo "[INFO] 告警发送完成。"
else
    echo "[INFO] ${DATETIME} - 服务器 ${HOST_IP} 各项资源运行正常，无需告警。"
fi
