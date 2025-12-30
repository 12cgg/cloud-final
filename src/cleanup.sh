#!/bin/bash
# =============================================================================
# 清理脚本 - 清理实验创建的VM和Docker容器
# =============================================================================
# 功能说明：
#   清理实验过程中创建的VM、Docker容器和相关资源
#
# 使用方法：
#   sudo bash cleanup.sh [--all]
#   --all: 同时清理结果目录
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_DIR="${SCRIPT_DIR}/results"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[清理]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

echo ""
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}  实验环境清理${NC}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_warning "即将清理以下内容："
echo "  • 停止Nginx服务"
echo "  • 删除Docker容器"
echo "  • 清理实验结果文件"
echo ""

read -p "确认清理? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "取消清理"
    exit 0
fi

echo ""

log "停止Nginx服务..."
sudo systemctl stop nginx 2>/dev/null || true
sudo pkill -9 nginx 2>/dev/null || true
log_success "Nginx已停止"

log "清理Docker容器..."
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        docker ps -a --format '{{.Names}}' | grep -E "docker-nginx|vmware-nginx" | while read container; do
            docker rm -f "$container" 2>/dev/null && log_success "已删除容器: $container"
        done
    else
        log_warning "Docker未运行，跳过容器清理"
    fi
else
    log_warning "Docker未安装，跳过容器清理"
fi

log "清理结果文件..."
if [[ -d "${RESULT_DIR}" ]]; then
    rm -rf "${RESULT_DIR}"
    log_success "已删除: ${RESULT_DIR}"
else
    log_warning "结果目录不存在"
fi

echo ""
log_success "清理完成！"
echo ""
