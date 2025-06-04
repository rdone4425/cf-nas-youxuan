#!/bin/bash

# 导入主配置
CF_ROOT_DIR=${CF_ROOT_DIR:-"/root/cf"}
source "$CF_ROOT_DIR/main.sh"

# CFNAS 特定配置
CFNAS_BINARY="$CF_ROOT_DIR/cf"
CFNAS_CONFIG="$CF_ROOT_DIR/cfnas.conf"

# 初始化CFNAS配置
init_cfnas() {
    log "INFO" "初始化 CFNAS 环境..."
    
    # 检查并下载必要文件
    local arch=$(uname -m)
    local binary_name="amd64"
    case "$arch" in
        x86_64|amd64)
            binary_name="amd64"
            ;;
        aarch64|arm64)
            binary_name="arm64"
            ;;
        i386|i686)
            binary_name="386"
            ;;
        armv7*|armv6*|armhf)
            binary_name="arm"
            ;;
        mips64el)
            binary_name="mips64le"
            ;;
        mips64)
            binary_name="mips64"
            ;;
        mipsel)
            binary_name="mipsle"
            ;;
        *)
            log "ERROR" "不支持的系统架构: $arch"
            log "INFO" "当前支持的架构: amd64, arm64, 386, arm, mips64le, mips64, mipsle"
            return $E_FAILED
            ;;
    esac
    
    # 下载必要文件
    local files=(
        "https://raw.githubusercontent.com/rdone4425/Cloudflare_vless_trojan/main/cf/${binary_name}|$CFNAS_BINARY|binary"
        "https://raw.githubusercontent.com/rdone4425/Cloudflare_vless_trojan/main/cf/ips-v4.txt|$CF_IPS_DIR/ips-v4.txt|text"
        "https://raw.githubusercontent.com/rdone4425/Cloudflare_vless_trojan/main/cf/ips-v6.txt|$CF_IPS_DIR/ips-v6.txt|text"
    )
    
    for file_info in "${files[@]}"; do
        IFS='|' read -r url output type <<< "$file_info"
        if ! download_file "$url" "$output" "" "$type"; then
            log "ERROR" "文件下载失败: $output"
            return $E_FAILED
        fi
    done
    
    # 设置执行权限
    chmod +x "$CFNAS_BINARY"
    
    log "INFO" "CFNAS 环境初始化完成"
    return $E_SUCCESS
}

# CFNAS优选函数
run_optimize() {
    local mode="$1"
    local output_file=""
    local args=""
    
    case "$mode" in
        "ipv4")
            output_file="$CF_IPS_DIR/cfnas_ipv4.txt"
            args="--ipv4"
            ;;
        "ipv6")
            output_file="$CF_IPS_DIR/cfnas_ipv6.txt"
            args="--ipv6"
            ;;
        *)
            log "ERROR" "无效的优选模式: $mode"
            return $E_FAILED
            ;;
    esac
    
    log "INFO" "开始 ${mode} 优选..."
    
    # 执行优选
    if ! "$CFNAS_BINARY" $args -o "$output_file" -t 4; then
        log "ERROR" "${mode} 优选失败"
        return $E_FAILED
    fi
    
    log "INFO" "${mode} 优选完成"
    return $E_SUCCESS
}

# 如果直接运行此脚本，显示帮助信息
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${YELLOW}CFNAS 优选工具${NC}"
    echo "用法: $0 [--ipv4|--ipv6]"
    echo
    echo "选项:"
    echo "  --ipv4    执行 IPv4 优选"
    echo "  --ipv6    执行 IPv6 优选"
fi
