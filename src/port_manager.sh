#!/bin/bash
# =============================================================================
# 端口管理工具脚本
# =============================================================================
# 功能：
#   - 检测端口是否被占用
#   - 释放指定端口（杀死占用进程）
#   - 查找可用的替代端口
#
# 使用方法：
#   bash port_manager.sh check 8080           # 检查端口是否被占用
#   bash port_manager.sh kill 8080            # 释放端口（需要sudo）
#   bash port_manager.sh find 8080            # 查找替代端口
#   bash port_manager.sh info 8080            # 显示端口详细信息
# =============================================================================

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[端口管理]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_info() { echo -e "${CYAN}[i]${NC} $*"; }

# 检查端口是否被占用
check_port() {
    local port=$1
    
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":${port} "; then
            return 0  # 被占用
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            return 0  # 被占用
        fi
    else
        log_error "未找到 ss 或 netstat 工具"
        return 2
    fi
    
    return 1  # 未被占用
}

# 获取占用端口的进程信息
get_port_info() {
    local port=$1
    
    log "端口 ${port} 的使用情况："
    echo ""
    
    if command -v lsof >/dev/null 2>&1; then
        local info=$(sudo lsof -i ":${port}" 2>/dev/null || true)
        if [[ -n "$info" ]]; then
            echo "$info"
            return 0
        fi
    fi
    
    if command -v ss >/dev/null 2>&1; then
        local info=$(ss -tulnp | grep ":${port} " 2>/dev/null || true)
        if [[ -n "$info" ]]; then
            echo "$info"
            return 0
        fi
    fi
    
    if command -v netstat >/dev/null 2>&1; then
        local info=$(sudo netstat -tulnp 2>/dev/null | grep ":${port} " || true)
        if [[ -n "$info" ]]; then
            echo "$info"
            return 0
        fi
    fi
    
    log_info "端口 ${port} 未被占用"
    return 1
}

# 杀死占用端口的进程
kill_port() {
    local port=$1
    local force=${2:-false}
    
    if ! check_port "$port"; then
        log_success "端口 ${port} 未被占用"
        return 0
    fi
    
    log_warning "尝试释放端口 ${port}..."
    
    # 获取进程PID
    local pids=()
    
    if command -v lsof >/dev/null 2>&1; then
        # 使用lsof查找
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(sudo lsof -t -i ":${port}" 2>/dev/null || true)
    fi
    
    if [[ ${#pids[@]} -eq 0 ]] && command -v ss >/dev/null 2>&1; then
        # 使用ss查找
        while IFS= read -r line; do
            local pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+' || true)
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(ss -tulnp | grep ":${port} " 2>/dev/null || true)
    fi
    
    if [[ ${#pids[@]} -eq 0 ]] && command -v netstat >/dev/null 2>&1; then
        # 使用netstat查找
        while IFS= read -r line; do
            local pid=$(echo "$line" | awk '{print $7}' | cut -d'/' -f1 || true)
            [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && pids+=("$pid")
        done < <(sudo netstat -tulnp 2>/dev/null | grep ":${port} " || true)
    fi
    
    if [[ ${#pids[@]} -eq 0 ]]; then
        log_error "无法找到占用端口 ${port} 的进程"
        return 1
    fi
    
    # 去重
    local unique_pids=($(printf '%s\n' "${pids[@]}" | sort -u))
    
    log "找到 ${#unique_pids[@]} 个进程占用端口 ${port}"
    
    # 显示进程信息
    for pid in "${unique_pids[@]}"; do
        local proc_info=$(ps -p "$pid" -o pid,user,cmd --no-headers 2>/dev/null || echo "PID $pid")
        log_info "进程: $proc_info"
    done
    
    # 确认是否杀死进程
    if [[ "$force" != "true" ]]; then
        echo ""
        log_warning "即将杀死以上进程以释放端口 ${port}"
        read -p "是否继续？[y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "操作已取消"
            return 1
        fi
    fi
    
    # 杀死进程
    local killed=0
    for pid in "${unique_pids[@]}"; do
        if sudo kill "$pid" 2>/dev/null; then
            log_success "已杀死进程 PID: $pid"
            ((killed++))
        else
            log_warning "无法杀死进程 PID: $pid (可能已退出)"
        fi
    done
    
    # 等待端口释放
    sleep 1
    
    # 验证端口是否已释放
    if ! check_port "$port"; then
        log_success "端口 ${port} 已成功释放"
        return 0
    else
        log_error "端口 ${port} 仍被占用，可能需要强制杀死"
        log_info "尝试强制杀死: sudo kill -9 ..."
        for pid in "${unique_pids[@]}"; do
            sudo kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1
        
        if ! check_port "$port"; then
            log_success "端口 ${port} 已强制释放"
            return 0
        else
            log_error "无法释放端口 ${port}"
            return 1
        fi
    fi
}

# 查找可用端口
find_available_port() {
    local start_port=$1
    local max_attempts=${2:-100}
    
    log "从端口 ${start_port} 开始查找可用端口..."
    
    for ((i=0; i<max_attempts; i++)); do
        local port=$((start_port + i))
        
        if ! check_port "$port"; then
            log_success "找到可用端口: ${port}"
            echo "$port"
            return 0
        fi
    done
    
    log_error "在 ${start_port}-$((start_port + max_attempts - 1)) 范围内未找到可用端口"
    return 1
}

# 显示使用帮助
show_help() {
    cat <<EOF
端口管理工具

使用方法:
  bash port_manager.sh <command> <port> [options]

命令:
  check <port>          检查端口是否被占用
  info <port>           显示端口详细信息（占用进程等）
  kill <port> [-f]      释放端口（杀死占用进程）
                        -f: 强制模式，不询问确认
  find <port> [max]     查找可用端口（从指定端口开始）
                        max: 最大尝试次数（默认100）

示例:
  # 检查端口8080是否被占用
  bash port_manager.sh check 8080

  # 查看端口8080的详细信息
  bash port_manager.sh info 8080

  # 释放端口8080（会提示确认）
  bash port_manager.sh kill 8080

  # 强制释放端口8080（不询问）
  bash port_manager.sh kill 8080 -f

  # 查找8080之后的可用端口
  bash port_manager.sh find 8080

  # 在8080-8200范围内查找可用端口
  bash port_manager.sh find 8080 120

退出码:
  0 - 成功
  1 - 失败或端口被占用
  2 - 工具缺失

EOF
}

# 主函数
main() {
    if [[ $# -lt 2 ]]; then
        show_help
        exit 1
    fi
    
    local command=$1
    local port=$2
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        log_error "无效的端口号: $port"
        log_info "端口号必须在 1-65535 之间"
        exit 1
    fi
    
    case "$command" in
        check)
            if check_port "$port"; then
                log_warning "端口 ${port} 已被占用"
                exit 1
            else
                log_success "端口 ${port} 可用"
                exit 0
            fi
            ;;
        info)
            get_port_info "$port"
            ;;
        kill)
            local force=false
            [[ "${3:-}" == "-f" || "${3:-}" == "--force" ]] && force=true
            kill_port "$port" "$force"
            ;;
        find)
            local max_attempts=${3:-100}
            find_available_port "$port" "$max_attempts"
            ;;
        -h|--help|help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"

