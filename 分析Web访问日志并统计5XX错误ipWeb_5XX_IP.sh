#!/bin/bash


# Description : 分析 Web 访问日志，利用正则表达式提取出现 5xx 错误请求的来源 IP 并统计排行

# -e 抛出异常 -u 不准用错变量 -o 不准在管道里藏匿错误
set -euo pipefail

LOG_FILE="/var/log/nginx/access.log"
TOP_LIMIT=10


# 提取异常 IP 并统计出现频次排行
analyze_error_ips() {
    echo "========== 正在分析 HTTP 5xx 错误请求的来源 IP =========="
    
    # 基础防御：检查日志文件是否存在
    if [[ ! -f "${LOG_FILE}" ]]; then
        echo "[ERROR] 日志文件 ${LOG_FILE} 不存在！" >&2
        exit 1
    fi


    # grep 粗略过滤出包含 5xx 状态码的日志行
    # grep -E -o 配合正则表达式，精准切割并提取符合 IPv4 规范的文本
    # sort 排序后交由 uniq -c 去重并统计频次
    # sort -nr 按频次倒序排列
    # head -n 截取 Top N 结果
    
    grep 'HTTP/1.[0-1] 5' "${LOG_FILE}" | \
        grep -E -o "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | \
        sort | \
        uniq -c | \
        sort -nr | \
        head -n "${TOP_LIMIT}"
        
    echo "========== 分析完成 (Top ${TOP_LIMIT}) =========="
}

# 执行
analyze_error_ips
