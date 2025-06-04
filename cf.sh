#!/bin/bash

# 导入主配置
CF_ROOT_DIR=${CF_ROOT_DIR:-"/root/cf"}
source "$CF_ROOT_DIR/main.sh"

# CF特定配置
CF_SPEEDTEST_DIR="$CF_ROOT_DIR/CloudflareST"
CF_CONFIG_FILE="$CF_SPEEDTEST_DIR/config.conf"

# 默认配置
readonly DEFAULT_CONFIG=(
    "# CloudflareSpeedTest 配置文件"
    "n=200"          # 延迟测速线程数
    "t=4"           # 延迟测速次数
    "sl=10"         # 选择的IP数量
    "tp=443"        # 测速端口
    "tl=500"        # 延迟上限(ms)
)

# 初始化CF配置
init_cf() {
    log "INFO" "初始化 CF 环境..."
    
    # 创建配置目录
    mkdir -p "$CF_SPEEDTEST_DIR"
    
    # 创建配置文件
    if [ ! -f "$CF_CONFIG_FILE" ]; then
        printf "%s\n" "${DEFAULT_CONFIG[@]}" > "$CF_CONFIG_FILE"
    fi
    
    # 检测系统架构并下载对应程序
    local arch=$(uname -m)
    local binary_url=""
    case "$arch" in
        x86_64|amd64)
            binary_url="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/CloudflareST_linux_amd64.tar.gz"
            ;;
        aarch64|arm64)
            binary_url="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/CloudflareST_linux_arm64.tar.gz"
            ;;
        *)
            log "ERROR" "不支持的系统架构: $arch"
            return $E_FAILED
            ;;
    esac
    
    # 下载并解压程序
    local tmp_file="$CF_TMP_DIR/CloudflareST.tar.gz"
    if ! download_file "$binary_url" "$tmp_file" "" "binary"; then
        log "ERROR" "下载 CloudflareST 失败"
        return $E_FAILED
    fi
    
    # 解压文件
    tar -xzf "$tmp_file" -C "$CF_SPEEDTEST_DIR"
    chmod +x "$CF_SPEEDTEST_DIR/CloudflareST"
    rm -f "$tmp_file"
    
    log "INFO" "CF 环境初始化完成"
    return $E_SUCCESS
}

# CF优选函数
run_optimize() {
    local mode="$1"
    local output_file=""
    local ip_file=""
    
    case "$mode" in
        "ipv4")
            output_file="$CF_IPS_DIR/cf_ipv4.txt"
            ip_file="$CF_IPS_DIR/ips-v4.txt"
            ;;
        "ipv6")
            output_file="$CF_IPS_DIR/cf_ipv6.txt"
            ip_file="$CF_IPS_DIR/ips-v6.txt"
            ;;
        *)
            log "ERROR" "无效的优选模式: $mode"
            return $E_FAILED
            ;;
    esac
    
    log "INFO" "开始 ${mode} 优选..."
    
    # 检查必要文件
    if [ ! -f "$ip_file" ]; then
        log "ERROR" "IP列表文件不存在: $ip_file"
        return $E_NOFILE
    fi
    
    # 执行优选
    if ! "$CF_SPEEDTEST_DIR/CloudflareST" -f "$ip_file" -o "$output_file"; then
        log "ERROR" "${mode} 优选失败"
        return $E_FAILED
    fi
    
    log "INFO" "${mode} 优选完成"
    return $E_SUCCESS
}

# 如果直接运行此脚本，显示帮助信息
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${YELLOW}CF 优选工具${NC}"
    echo "用法: $0 [--ipv4|--ipv6]"
    echo
    echo "选项:"
    echo "  --ipv4    执行 IPv4 优选"
    echo "  --ipv6    执行 IPv6 优选"
fi

