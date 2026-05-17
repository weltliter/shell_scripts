#!/bin/bash


set -euo pipefail


# 需要重点保护的核心文件或目录列表
PROTECTED_FILES=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/ssh/sshd_config"
    "/etc/sudoers"
)

BASELINE_DB="/var/secure/file_baseline.sha256" # 存放指纹的基线库
LOG_FILE="/var/log/file_integrity.log"



log_event() {
    local level=$1
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*" | tee -a "${LOG_FILE}"
}

# 初始化安全基线
init_baseline() {
    log_event "INFO" "========== 开始生成核心文件安全基线 =========="
    
    # 确保基线库所在目录存在，并严格限制权限 (仅 root 可读写)
    local db_dir
    db_dir=$(dirname "${BASELINE_DB}")
    if [[ ! -d "${db_dir}" ]]; then
        mkdir -p "${db_dir}"
        chmod 700 "${db_dir}"
    fi

    # 清空旧基线
    > "${BASELINE_DB}"

    for file in "${PROTECTED_FILES[@]}"; do
        if [[ -f "${file}" ]]; then
            # 计算 SHA-256 哈希值并存入基线库
            sha256sum "${file}" >> "${BASELINE_DB}"
            log_event "INFO" "已为文件生成指纹: ${file}"
        else
            log_event "WARN" "配置文件不存在，已跳过: ${file}"
        fi
    done
    
    # 锁定基线文件本身，防止黑客连同基线一起篡改
    chmod 600 "${BASELINE_DB}"
    log_event "INFO" "安全基线生成完毕！请妥善保管。基线库: ${BASELINE_DB}"
}

# 比对巡检 (检查文件是否被篡改)
check_integrity() {
    log_event "INFO" "========== 开始执行文件完整性巡检 =========="
    
    if [[ ! -f "${BASELINE_DB}" ]]; then
        log_event "ERROR" "未找到安全基线库 ${BASELINE_DB}，请先执行 init 操作！" >&2
        exit 1
    fi

    # 核心逻辑：使用 sha256sum 的 --check 和 --quiet 参数
    # 它会自动读取基线库中的记录，并重新计算当前系统里文件的哈希值进行核对
    # 如果不匹配，就会输出被篡改的文件名
    if sha256sum --check --quiet "${BASELINE_DB}" > /dev/null 2>&1; then
        log_event "INFO" "所有受保护文件状态正常，未发现篡改痕迹。"
    else
        log_event "FATAL" "警告！检测到以下文件哈希值发生突变，可能已被篡改："
        
        # 提取具体是哪个文件校验失败
        sha256sum --check --quiet "${BASELINE_DB}" 2>&1 | tee -a "${LOG_FILE}"
        
        log_event "FATAL" "请立即排查服务器入侵风险！"
        exit 2
    fi
    log_event "INFO" "========== 完整性巡检结束 =========="
}


action=${1:-""}

# 必须使用 root 权限执行，因为涉及 /etc/shadow 等敏感文件
if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] 请使用 root 权限执行此脚本。" >&2
    exit 1
fi

case "${action}" in
    init)
        init_baseline
        ;;
    check)
        check_integrity
        ;;
    *)
        echo "Usage: $0 {init|check}"
        echo "  init  - 首次运行，对核心文件进行哈希快照并生成基线"
        echo "  check - 定期巡检，比对当前文件与基线是否一致"
        exit 1
        ;;
esac
