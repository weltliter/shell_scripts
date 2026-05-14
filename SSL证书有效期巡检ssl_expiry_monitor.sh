#!/bin/bash


# 批量检测目标域名的 SSL/TLS 证书剩余有效期，提前告警

set -euo pipefail


TARGET_DOMAINS= baidu.com # 总之就是各种域名
ALERT_THRESHOLD_DAYS=30  # 告警阈值


# 探测并计算证书剩余天数
check_ssl_expiry() {
    echo "========== SSL 证书有效期批量巡检 =========="
    
    for domain in "${TARGET_DOMAINS[@]}"; do
        # 使用 echo | 发送一个 EOF 给 s_client，让其获取到证书后立即断开，防止阻塞
        # x509：OpenSSL 中专门用来处理 X.509 格式（HTTPS 证书标准格式）的工具
        # -enddate：直接提取证书的最终过期时间
        # -d=：指定用等号 = 作为分隔刀，把上一层的输出切成两半
        # -f2：取切开后的第 2 块
        local expire_date_str
        expire_date_str=$(echo | openssl s_client -servername "${domain}" -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
        
        if [[ -z "${expire_date_str}" ]]; then
            echo "[ERROR] 域名 ${domain} : 无法获取证书信息，请检查网络或 DNS 解析"
            continue
        fi
        
        # 将提取到的日期字符串转换为 Unix 时间戳
        local expire_ts current_ts remain_days
        expire_ts=$(date -d "${expire_date_str}" +%s)
        current_ts=$(date +%s)
        
        # 计算剩余天数 (秒数差值除以每天的秒数)
        remain_days=$(( (expire_ts - current_ts) / 86400 ))
        
        # 结果判断与输出
        if [[ ${remain_days} -lt 0 ]]; then
            echo "[FATAL] 域名 ${domain} : 证书已过期 ${remain_days#-} 天！"
        elif [[ ${remain_days} -le ${ALERT_THRESHOLD_DAYS} ]]; then
            echo "[WARN]  域名 ${domain} : 证书即将过期，仅剩 ${remain_days} 天"
        else
            echo "[OK]    域名 ${domain} : 状态正常，剩余 ${remain_days} 天"
        fi
    done
    
    echo "========== 巡检任务结束 =========="
}

check_ssl_expiry
