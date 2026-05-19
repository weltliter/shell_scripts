#!/bin/bash
# 需要配后台持续静默执行操作


set -euxo pipefail


SNAPSHOT_DIR="/var/log/sys_snapshots"
MEM_WARN_PERCENT=90           # 内存告警阈值 (%)
CURRENT_TIME=$(date '+%Y%m%d_%H%M%S')
SNAPSHOT_FILE="${SNAPSHOT_DIR}/scene_${CURRENT_TIME}.log"

# 防抖机制：避免短时间内频繁触发抓取导致 I/O 爆炸
COOLDOWN_MINUTES=15
LOCK_FILE="/tmp/capture_scene.lock"



# 获取 CPU 核心数与 1 分钟平均负载
CPU_CORES=$(nproc)
LOAD_1MIN=$(awk '{print $1}' /proc/loadavg)

# 获取内存使用率 (已用内存 / 总内存 * 100)
MEM_TOTAL=$(free -m | awk 'NR==2 {print $2}')
MEM_USED=$(free -m | awk 'NR==2 {print $3}')
MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))

# 使用 awk 进行浮点数比较：判断负载是否超过核心数的 1.5 倍
IS_LOAD_HIGH=$(awk -v load="${LOAD_1MIN}" -v cores="${CPU_CORES}" 'BEGIN { if (load > cores * 1.5) print 1; else print 0 }')


capture_scene() {
    local trigger_reason=$1
    
    echo "========== 触发异常抓取: ${CURRENT_TIME} ==========" > "${SNAPSHOT_FILE}"
    echo "触发原因: ${trigger_reason}" >> "${SNAPSHOT_FILE}"
    echo "系统负载: ${LOAD_1MIN} (核心数: ${CPU_CORES})" >> "${SNAPSHOT_FILE}"
    echo "内存使用: ${MEM_PERCENT}% (${MEM_USED}MB / ${MEM_TOTAL}MB)" >> "${SNAPSHOT_FILE}"
    echo -e "\n--------------------------------------------------" >> "${SNAPSHOT_FILE}"

    # 抓取当前消耗 CPU 前 10 的进程
    echo -e "\n[Top 10 CPU Consumers]" >> "${SNAPSHOT_FILE}"
    ps -eo pid,user,%cpu,%mem,stat,start,command --sort=-%cpu | head -n 11 >> "${SNAPSHOT_FILE}"

    # 抓取当前消耗 内存 前 10 的进程
    echo -e "\n[Top 10 Memory Consumers]" >> "${SNAPSHOT_FILE}"
    ps -eo pid,user,%cpu,%mem,stat,start,command --sort=-%mem | head -n 11 >> "${SNAPSHOT_FILE}"

    # 抓取当前 TCP 连接状态统计 (用于排查并发洪水或连接泄露)
    echo -e "\n[TCP Connection States]" >> "${SNAPSHOT_FILE}"
    ss -ant | awk 'NR>1 {++s[$1]} END {for(k in s) print k,s[k]}' >> "${SNAPSHOT_FILE}"
    
    # 抓取内核消息环形缓冲区的末尾 (排查 OOM Killer 或硬件报错)
    echo -e "\n[Recent Kernel Messages (dmesg)]" >> "${SNAPSHOT_FILE}"
    dmesg -T | tail -n 15 >> "${SNAPSHOT_FILE}"

    echo -e "\n========== 快照抓取结束 ==========" >> "${SNAPSHOT_FILE}"
    
    # 更新锁文件时间，进入冷却期
    touch "${LOCK_FILE}"
}


main() {
    # 检查是否处于冷却期
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_age_min
        lock_age_min=$(find "${LOCK_FILE}" -mmin -${COOLDOWN_MINUTES} | wc -l)
        if [[ "${lock_age_min}" -eq 1 ]]; then
            # 处于冷却期，直接静默退出
            exit 0
        fi
    fi

    # 环境准备
    if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
        mkdir -p "${SNAPSHOT_DIR}"
    fi

    # 条件触发判定
    if [[ "${IS_LOAD_HIGH}" -eq 1 ]]; then
        capture_scene "System Load 超标 (当前: ${LOAD_1MIN}, 阈值: ${CPU_CORES} * 1.5)"
    elif [[ "${MEM_PERCENT}" -ge "${MEM_WARN_PERCENT}" ]]; then
        capture_scene "Memory 使用率超标 (当前: ${MEM_PERCENT}%, 阈值: ${MEM_WARN_PERCENT}%)"
    fi
}

main
