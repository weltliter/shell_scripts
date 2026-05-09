#!/bin/bash
# 查找 /var/log 目录下大于 1GB 的文件，并在不停止业务的情况下瞬间清空它们
# 如果一个日志文件正在被程序疯狂写入，直接用 rm -f 删除它，磁盘空间是不会释放的。因为进程还死死抓着这个文件

echo "开始扫描并清空大于 1GB 的日志文件..."

find /var/log -type f -size +1G | while read big_file; do
    echo "发现巨型文件，正在清空: $big_file"
    > "$big_file"
done

echo "清理完成，空间已释放"
