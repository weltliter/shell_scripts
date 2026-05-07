#!/bin/bash

#变量配置区域
LOG_DIR="/var/log/nginx"                 # Nginx 日志存放目录
BACKUP_DIR="/data/backup/nginx_logs"     # 压缩归档目录
PID_FILE="/var/run/nginx.pid"            # Nginx PID 文件位置
YESTERDAY=$(date -d "yesterday" +"%Y%m%d") # 获取昨天的日期

# 确保备份目录存在，不存在则创建
mkdir -p $BACKUP_DIR

#日志切割与压缩 (Log Rotation)
echo "[$(date +'%Y-%m-%d %H:%M:%S')] 开始处理 Nginx 日志..."

# 移动当前的 access.log 到备份目录并重命名
mv ${LOG_DIR}/access.log ${BACKUP_DIR}/access_${YESTERDAY}.log

# 向 Nginx 主进程发送 USR1 信号，平滑重新打开日志文件，不中断前端业务
if [ -f "$PID_FILE" ]; then
    kill -USR1 $(cat $PID_FILE)
    echo "[INFO] 已通知 Nginx 重新生成 access.log"
else
    echo "[ERROR] 找不到 Nginx PID 文件，Nginx 可能未运行！"
    exit 1
fi

# 打包压缩昨天的日志，并删除未压缩的原文件以节省空间
cd $BACKUP_DIR
tar -czf access_${YESTERDAY}.tar.gz access_${YESTERDAY}.log
rm -f access_${YESTERDAY}.log
echo "[INFO] 日志已打包为 access_${YESTERDAY}.tar.gz"

#日志清理 (Data Retention)
# 查找备份目录下，修改时间超过 30 天的 .tar.gz 文件并删除
find $BACKUP_DIR -name "access_*.tar.gz" -type f -mtime +30 -exec rm -f {} \;
echo "[INFO] 已清理 30 天前的过期历史日志"

#数据提取与分析 (Traffic Analysis)
echo "========================================================"
echo "昨天的流量简报 ($YESTERDAY)"
echo "========================================================"

# 分析 A: 提取访问量 Top 5 的 IP 地址
# awk '{print $1}' 提取第一列 (通常是 IP)
# sort 排序后交由 uniq -c 统计重复次数，再按纯数字逆序 sort -nr 排列
echo "--- Top 5 访问 IP ---"
tar -xzOf access_${YESTERDAY}.tar.gz | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5

echo ""

# 分析 B: 统计 HTTP 状态码分布 (如 200, 404, 500)
# Nginx 默认日志中，状态码通常在第 9 列
echo "--- HTTP 状态码统计 ---"
tar -xzOf access_${YESTERDAY}.tar.gz | awk '{print $9}' | sort | uniq -c | sort -nr | head -n 5

echo "========================================================"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] 日志处理完毕。"
