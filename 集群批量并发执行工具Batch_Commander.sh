#!/bin/bash
# 并发向集群下发指令

COMMAND=$1 # 具体命令
SERVER_LIST="/opt/scripts/server_ips.txt"

# 参数校验
if [ -z "$COMMAND" ]; then
    echo "[error]错误: 未提供任何执行命令。"
    exit 1
fi

if [ ! -f "$SERVER_LIST" ]; then
    echo "[error]错误: 找不到列表文件 $SERVER_LIST"
    exit 1
fi

echo "向集群下发指令: [ $COMMAND ]"
echo "=================================================="

# 循环读取 IP 并打入后台执行
cat "$SERVER_LIST" | while read -r IP; do
    # 忽略空行和带 # 号的注释
    if [[ -z "$IP" || "$IP" == \#* ]]; then
        continue
    fi
    
    # 并发执行
    {
        RESULT=$(ssh -n -q -o ConnectTimeout=3 -o StrictHostKeyChecking=no "root@$IP" "$COMMAND" 2>&1)
        
        STATUS=$?
        
        # 将 IP 和结果拼接成一段完整的文本，一次性 echo 输出，防止日志撕裂
        if [ $STATUS -eq 0 ]; then
            echo -e "[success] [$IP] 成功:\n$RESULT\n------------------------"
        else
            echo -e "[error] [$IP] 失败:\n$RESULT\n------------------------"
        fi
    } &
    
done < "$SERVER_LIST"

# 在此死等，直到所有后台 SSH 进程全部结束
wait

echo "=================================================="
echo "所有并发任务执行完毕！"
