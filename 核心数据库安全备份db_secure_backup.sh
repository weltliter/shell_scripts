#!/bin/bash


set -euo pipefail


DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="production_core_db"
# 使用预先制作的独立的安全配置文件存放凭证，避免在脚本或进程中暴露密码
DB_CREDENTIALS="/etc/mysql/.backup.cnf"  


BACKUP_BASE_DIR="/data/backup/mysql"
RETENTION_DAYS=7
CURRENT_TIME=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_BASE_DIR}/${DB_NAME}_${CURRENT_TIME}.sql.gz"


# 前置安全与环境检查
pre_flight_check() {
    echo "========== 数据库备份任务开始: ${CURRENT_TIME} =========="
    
    # 检查凭证文件是否存在且权限安全 (通常应为 600)
    if [[ ! -f "${DB_CREDENTIALS}" ]]; then
        echo "[ERROR] 凭证文件 ${DB_CREDENTIALS} 不存在，已中止备份以保障安全！" >&2
        exit 1
    fi

    if [[ ! -d "${BACKUP_BASE_DIR}" ]]; then
        echo "[INFO] 备份目录不存在，正在创建 ${BACKUP_BASE_DIR} ..."
        mkdir -p "${BACKUP_BASE_DIR}"
        chmod 700 "${BACKUP_BASE_DIR}" # 限制普通用户访问备份文件
    fi
}


# 流式备份与压缩
execute_backup() {
    echo "[INFO] 正在执行全量逻辑备份并进行 gzip 压缩..."
    
    # 核心逻辑：
    # 使用 --defaults-extra-file 读取密码，防止 ps 命令嗅探
    # 加上 --single-transaction 保证 InnoDB 引擎的备份一致性且不锁表
    # 直接通过管道 | 交给 gzip，不在磁盘上落地庞大的 .sql 纯文本文件，极致节省 I/O 和空间
    mysqldump --defaults-extra-file="${DB_CREDENTIALS}" \
              -h "${DB_HOST}" -P "${DB_PORT}" \
              --single-transaction \
              --routines --events --triggers \
              "${DB_NAME}" | gzip > "${BACKUP_FILE}"
              
    echo "[OK] 备份成功！产物路径: ${BACKUP_FILE}"
    echo "[INFO] 备份文件大小: $(du -sh "${BACKUP_FILE}" | cut -f1)"
}


# 历史备份轮转清理
cleanup_expired_backups() {
    echo "[INFO] 正在清理 ${RETENTION_DAYS} 天前的历史备份..."
    
    # 删除超期文件，保持磁盘空间健康
    find "${BACKUP_BASE_DIR}" -type f -name "${DB_NAME}_*.sql.gz" -mtime +${RETENTION_DAYS} -delete
    
    echo "[OK] 历史备份清理完成。"
    echo "========== 数据库备份任务结束 =========="
}


main() {
    pre_flight_check
    execute_backup
    cleanup_expired_backups
}

main
