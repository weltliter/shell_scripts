#!/bin/bash
# 前端/后端的零停机发布与秒级故障回滚

ACTION=$1          # 操作类型 (deploy 或 rollback)
PACKAGE=$2         # 发布包路径 (如 frontend_v2.tar.gz)

# 目录架构定义
BASE_DIR="/var/www/my_web_app"         # 项目根目录
RELEASES_DIR="${BASE_DIR}/releases"    # 存放所有历史版本的目录
CURRENT_LINK="${BASE_DIR}/current"     # 软链接：永远指向当前正在运行的版本


# 部署新版本 (deploy)
deploy() {
    if [ -z "$PACKAGE" ] || [ ! -f "$PACKAGE" ]; then
        echo "[error]错误: 缺少发布包或文件不存在！"
        exit 1
    fi
    
    # 以当前时间戳生成唯一的版本号目录，例如：20260512_233000
    VERSION=$(date +"%Y%m%d_%H%M%S")
    NEW_RELEASE="${RELEASES_DIR}/${VERSION}"
    
    echo "[Deploy] 开始部署新版本: $VERSION"
    mkdir -p "$NEW_RELEASE"
    
    # 解压前端构建产物到新的版本目录
    tar -xzf "$PACKAGE" -C "$NEW_RELEASE"
    
    # 瞬间将 current 软链接指向刚刚解压的新版本目录
    ln -sfn "$NEW_RELEASE" "$CURRENT_LINK"
    
    echo "[success]部署成功,线上流量已瞬间切换至版本: $VERSION"
    
    # 清理老旧版本,只保留最近 5 个版本
    echo "清理历史版本，仅保留最近 5 次发布..."
    # ls -t 按时间倒序排列；tail -n +6 从第6个开始截取；xargs 传给 rm 执行删除
    cd "$RELEASES_DIR" && ls -t | tail -n +6 | xargs -I {} rm -rf {}
}

# 紧急回滚 (rollback)
rollback() {
    echo "[Rollback] 收到回滚指令，准备执行回滚..."
    
    # readlink: 获取 current 软链接当前真正指向的绝对路径
    CURRENT_REAL=$(readlink "$CURRENT_LINK")
    
    # 查找上一个版本的目录
    # ls -td 列出所有版本目录并按时间排序；grep -A 1 找到当前版本所在的行及紧接着的下一行（即上一个版本）
    PREV_RELEASE=$(ls -td ${RELEASES_DIR}/* | grep -A 1 "$CURRENT_REAL" | tail -n 1)
    
    # 安全校验：如果没有更老的版本了
    if [ "$CURRENT_REAL" == "$PREV_RELEASE" ] || [ -z "$PREV_RELEASE" ]; then
        echo "[fail]回滚失败：未发现更早的历史版本目录！"
        exit 1
    fi
    
    # 瞬间将 current 软链接指向上一个安全版本
    ln -sfn "$PREV_RELEASE" "$CURRENT_LINK"
    
    echo "[success]回滚成功,线上代码已恢复至老版本: $(basename "$PREV_RELEASE")"
}

# 路由控制器 
case "$ACTION" in
    deploy)
        deploy
        ;;
    rollback)
        rollback
        ;;
    *)
        echo "脚本使用说明:"
        echo "发布新版: sh $0 deploy <包路径>"
        echo "紧急回滚: sh $0 rollback"
        exit 1
        ;;
esac
