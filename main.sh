#!/bin/bash

# 基础配置
export CF_ROOT_DIR="/root/cf"                      # 根目录
export CF_CONFIG_FILE="$CF_ROOT_DIR/config.json"   # 配置文件
export CF_LOGS_DIR="$CF_ROOT_DIR/logs"            # 日志目录
export CF_TMP_DIR="$CF_ROOT_DIR/tmp"              # 临时目录
export CF_IPS_DIR="$CF_ROOT_DIR/ips"             # IP列表目录

# 颜色定义
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# 错误代码
readonly E_SUCCESS=0      # 成功
readonly E_FAILED=1       # 一般错误
readonly E_NOFILE=2       # 文件不存在
readonly E_NOPERM=3       # 权限不足
readonly E_NETWORK=4      # 网络错误
readonly E_SPACE=5        # 空间不足

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" >> "${CF_LOGS_DIR}/main.log"
    
    # 同时输出到控制台
    case $level in
        ERROR) echo -e "${RED}${message}${NC}" ;;
        WARN)  echo -e "${YELLOW}${message}${NC}" ;;
        INFO)  echo -e "${GREEN}${message}${NC}" ;;
        DEBUG) echo -e "${BLUE}${message}${NC}" ;;
    esac
}

# 环境初始化
init_environment() {
    # 创建必要的目录
    for dir in "$CF_ROOT_DIR" "$CF_LOGS_DIR" "$CF_TMP_DIR" "$CF_IPS_DIR"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            echo -e "${RED}错误: 无法创建目录 $dir${NC}"
            exit $E_NOPERM
        fi
    done
    
    # 初始化配置文件
    if [ ! -f "$CF_CONFIG_FILE" ]; then
        echo "{}" > "$CF_CONFIG_FILE"
    fi
    
    # 验证目录权限
    for dir in "$CF_ROOT_DIR" "$CF_LOGS_DIR" "$CF_TMP_DIR" "$CF_IPS_DIR"; do
        if [ ! -w "$dir" ]; then
            echo -e "${RED}错误: 目录无写入权限 $dir${NC}"
            exit $E_NOPERM
        fi
    done
}

# 转换文件换行符
convert_line_endings() {
    local file="$1"
    if command -v dos2unix &> /dev/null; then
        dos2unix "$file" 2>/dev/null || true
    else
        # 如果没有 dos2unix，使用 sed 进行转换
        local tmp_file="${file}.tmp"
        if sed 's/\r$//' "$file" > "$tmp_file"; then
            mv "$tmp_file" "$file"
        else
            rm -f "$tmp_file"
            log "WARN" "无法转换行尾格式，继续执行"
        fi
    fi
}

# 下载文件的通用函数
download_file() {
    local url="$1"
    local output="$2"
    local backup_url="$3"
    local expected_type="$4"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log "INFO" "下载文件: $output (尝试 $((retry_count + 1))/$max_retries)"
        
        # 尝试主地址
        if curl -sSLf --connect-timeout 30 "$url" -o "$output"; then
            if verify_file "$output" "$expected_type"; then
                log "INFO" "文件下载成功: $output"
                return 0
            fi
        fi
        
        # 如果有备用地址，尝试备用地址
        if [ -n "$backup_url" ]; then
            log "WARN" "主地址下载失败，尝试备用地址"
            if curl -sSLf --connect-timeout 30 "$backup_url" -o "$output"; then
                if verify_file "$output" "$expected_type"; then
                    log "INFO" "文件从备用地址下载成功: $output"
                    return 0
                fi
            fi
        fi
        
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((3 * retry_count))
            log "WARN" "下载失败，等待 ${wait_time} 秒后重试..."
            sleep "$wait_time"
        fi
    done
    
    log "ERROR" "文件下载失败: $output"
    return 1
}

# 验证文件完整性
verify_file() {
    local file="$1"
    local expected_type="$2"
    
    if [ ! -f "$file" ]; then
        log "ERROR" "文件不存在: $file"
        return 1
    fi
    
    # 检查文件大小
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [ "$size" -lt 1000 ]; then # 文件小于1KB可能是错误页面
        log "ERROR" "文件大小异常: $file ($size bytes)"
        rm -f "$file"
        return 1
    fi
    
    # 检查是否为二进制文件
    if [ "$expected_type" = "binary" ]; then
        if file "$file" | grep -q "text"; then
            log "ERROR" "预期为二进制文件，但检测到文本文件: $file"
            rm -f "$file"
            return 1
        fi
    elif [ "$expected_type" = "text" ]; then
        if ! file "$file" | grep -q "text"; then
            log "ERROR" "预期为文本文件，但检测到二进制文件: $file"
            rm -f "$file"
            return 1
        fi
    fi
    
    return 0
}

# 下载或更新 cfnas.sh
download_cfnas() {
    log "INFO" "开始下载 cfnas.sh..."
    
    # 检查curl命令是否可用
    if ! command -v curl &> /dev/null; then
        log "ERROR" "curl 命令未安装，请先安装 curl"
        return 1
    fi
    
    # 检查磁盘空间
    local required_space=5  # 需要5MB空间
    local available_space=$(df -m "$CF_DIR" | awk 'NR==2 {print $4}')
    if [ -n "$available_space" ] && [ "$available_space" -lt "$required_space" ]; then
        log "ERROR" "磁盘空间不足。需要: ${required_space}MB, 可用: ${available_space}MB"
        return 1
    fi
    
    # 确保临时目录存在并可写
    TMP_DIR="/tmp/cf_download"
    if ! mkdir -p "$TMP_DIR" 2>/dev/null; then
        TMP_DIR="$CF_DIR/tmp"
        if ! mkdir -p "$TMP_DIR" 2>/dev/null; then
            log "ERROR" "无法创建临时目录，请检查权限"
            return 1
        fi
    fi
    
    # 检查临时目录权限
    if [ ! -w "$TMP_DIR" ]; then
        log "ERROR" "临时目录无写入权限: $TMP_DIR"
        return 1
    fi
    
    # 设置临时文件路径
    TMP_FILE="$TMP_DIR/cfnas.sh.tmp.$$"
    CF_TMP_FILE="$TMP_DIR/cf.sh.tmp.$$"
    
    # 清理旧的临时文件
    trap 'rm -f "$TMP_FILE" "$CF_TMP_FILE"' EXIT
    
    # 确保目标目录存在且有写入权限
    if [ ! -d "$CF_DIR" ]; then
        if ! mkdir -p "$CF_DIR" 2>/dev/null; then
            log "ERROR" "无法创建目录: $CF_DIR"
            return 1
        fi
    fi
    
    if [ ! -w "$CF_DIR" ]; then
        log "ERROR" "目录无写入权限: $CF_DIR"
        return 1
    fi
    
    # 添加重试机制
    local max_retries=3
    local retry_count=0
    local curl_timeout=30
    local curl_retry_delay=3
    
    # 下载链接
    local cfnas_url="https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cfnas.sh"
    local cf_url="https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cf.sh"
    local cfnas_backup_url="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cfnas.sh"
    local cf_backup_url="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cf.sh"
    
    while [ $retry_count -lt $max_retries ]; do
        log "INFO" "尝试下载 cfnas.sh (尝试 $((retry_count + 1))/$max_retries)"
        
        # 使用 -f 选项防止输出错误页面到文件
        if curl -sSLf --connect-timeout "$curl_timeout" --retry 3 --retry-delay "$curl_retry_delay" "$cfnas_url" -o "$TMP_FILE" || \
           curl -sSLf --connect-timeout "$curl_timeout" --retry 3 --retry-delay "$curl_retry_delay" "$cfnas_backup_url" -o "$TMP_FILE"; then
            
            # 验证下载的文件
            if [ -s "$TMP_FILE" ] && head -n1 "$TMP_FILE" | grep -q "#!/bin/bash"; then
                # 确保文件以换行符结尾
                echo "" >> "$TMP_FILE"
                convert_line_endings "$TMP_FILE"
                
                # 安全地移动文件
                if cp "$TMP_FILE" "$CF_DIR/cfnas.sh" && chmod +x "$CF_DIR/cfnas.sh"; then
                    log "INFO" "cfnas.sh 下载成功"
                    
                    # 下载 cf.sh
                    log "INFO" "开始下载 cf.sh..."
                    if curl -sSLf --connect-timeout "$curl_timeout" "$cf_url" -o "$CF_TMP_FILE" || \
                       curl -sSLf --connect-timeout "$curl_timeout" "$cf_backup_url" -o "$CF_TMP_FILE"; then
                        
                        if [ -s "$CF_TMP_FILE" ] && head -n1 "$CF_TMP_FILE" | grep -q "#!/bin/bash"; then
                            echo "" >> "$CF_TMP_FILE"
                            convert_line_endings "$CF_TMP_FILE"
                            
                            if cp "$CF_TMP_FILE" "$CF_DIR/cf.sh" && chmod +x "$CF_DIR/cf.sh"; then
                                log "INFO" "cf.sh 下载成功"
                                return 0
                            else
                                log "ERROR" "无法保存 cf.sh"
                            fi
                        else
                            log "ERROR" "下载的 cf.sh 文件不完整或格式错误"
                        fi
                    else
                        log "ERROR" "下载 cf.sh 失败"
                    fi
                else
                    log "ERROR" "无法保存 cfnas.sh"
                fi
            else
                log "ERROR" "下载的 cfnas.sh 文件不完整或格式错误"
            fi
        else
            log "ERROR" "下载失败: curl 错误"
        fi
        
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((curl_retry_delay * retry_count))
            log "WARN" "下载失败，等待 ${wait_time} 秒后重试..."
            sleep "$wait_time"
        fi
    done
    
    log "ERROR" "达到最大重试次数，下载失败"
    return 1
}

# 添加合并结果函数
merge_results() {
    local ips_merged_file="$CF_DIR/ips/merged_all.txt"
    local temp_file="$CF_DIR/temp_results.txt"
    
    # 删除之前的合并文件
    if [ -f "$ips_merged_file" ]; then
        echo -e "${BLUE}删除之前的合并文件: $ips_merged_file${NC}"
        rm -f "$ips_merged_file"
    fi
    
    # 创建临时文件和输出目录
    mkdir -p "$(dirname "$ips_merged_file")"
    touch "$temp_file"
    
    # 检查并创建 ips 目录
    local ips_dir="$CF_DIR/ips"
    if [ ! -d "$ips_dir" ]; then
        mkdir -p "$ips_dir"
    fi
    
    # 合并 ips 目录下的所有 txt 文件
    if [ -d "$ips_dir" ]; then
        for file in "$ips_dir"/*.txt; do
            if [ -f "$file" ] && [ "$(basename "$file")" != "merged_all.txt" ]; then
                cat "$file" >> "$temp_file"
            fi
        done
    fi
    
    # 如果临时文件不为空，则处理并移动到最终位置
    if [ -s "$temp_file" ]; then
        # 删除空行和重复项
        sort -u "$temp_file" > "$ips_merged_file"
        rm -f "$temp_file"
        echo -e "${GREEN}优选结果已合并到: $ips_merged_file${NC}"
        echo -e "${YELLOW}合并后的IP数量: $(wc -l < "$ips_merged_file") 个${NC}"
    else
        echo -e "${RED}未找到任何优选结果${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# 上传到 GitHub
upload_to_github() {
    local config_file="/root/cf/config.json"
    local merged_file="$CF_DIR/ips/merged_all.txt"
    local github_token=$(jq -r '.github.token // ""' "$config_file" 2>/dev/null || echo "")
    local github_repo=$(jq -r '.github.repo // ""' "$config_file" 2>/dev/null || echo "")
    local github_branch=$(jq -r '.github.branch // "main"' "$config_file" 2>/dev/null || echo "main")
    local github_path="ips/merged_all.txt"

    # 检查配置
    if [ -z "$github_token" ] || [ -z "$github_repo" ]; then
        echo -e "${RED}错误：GitHub 配置不完整${NC}"
        echo -e "${YELLOW}请先配置 GitHub 令牌和仓库名${NC}"
        return 1
    fi

    # 检查文件是否存在
    if [ ! -f "$merged_file" ]; then
        echo -e "${RED}错误：合并文件不存在${NC}"
        return 1
    fi

    # 获取当前文件的 SHA（如果存在）
    local existing_sha=$(curl -s -H "Authorization: token $github_token" \
        "https://api.github.com/repos/$github_repo/contents/$github_path" | \
        jq -r '.sha // ""')

    # 准备上传数据
    local content=$(base64 "$merged_file" | tr -d '\n')
    local json_data
    if [ -n "$existing_sha" ]; then
        json_data=$(jq -n \
            --arg message "Update CloudFlare optimized IPs" \
            --arg content "$content" \
            --arg branch "$github_branch" \
            --arg sha "$existing_sha" \
            '{message: $message, content: $content, branch: $branch, sha: $sha}')
    else
        json_data=$(jq -n \
            --arg message "Add CloudFlare optimized IPs" \
            --arg content "$content" \
            --arg branch "$github_branch" \
            '{message: $message, content: $content, branch: $branch}')
    fi

    # 上传到 GitHub
    local response=$(curl -s -X PUT \
        -H "Authorization: token $github_token" \
        -H "Content-Type: application/json" \
        "https://api.github.com/repos/$github_repo/contents/$github_path" \
        -d "$json_data")

    if echo "$response" | jq -e '.content.sha' >/dev/null 2>&1; then
        echo -e "${GREEN}文件上传成功！${NC}"
        echo -e "文件路径: ${YELLOW}$github_path${NC}"
        echo -e "访问地址: ${YELLOW}https://raw.githubusercontent.com/$github_repo/$github_branch/$github_path${NC}"
    else
        echo -e "${RED}文件上传失败${NC}"
        echo -e "错误信息: $(echo "$response" | jq -r '.message // "未知错误"')"
        return 1
    fi
}

# 修改全部优选函数
run_all_optimizations() {
    echo -e "${BLUE}执行全部优选...${NC}"
    
    # 确保配置文件路径正确
    CF_DIR="/root/cf"  # 确保 CF_DIR 正确设置
    CONFIG_FILE="$CF_DIR/config.json"  # 使用正确的配置文件路径
    
    echo -e "${BLUE}使用配置文件: $CONFIG_FILE${NC}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在，创建新的配置文件...${NC}"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "{}" > "$CONFIG_FILE"
    fi
    
    # 检查并处理 cfnas.sh
    if [ ! -f "$CF_DIR/cfnas.sh" ]; then
        echo -e "${YELLOW}cfnas.sh 不存在，正在下载...${NC}"
        download_cfnas
    fi
    
    # 处理 cfnas.sh 文件格式
    echo -e "${BLUE}正在处理 CFNAS 文件格式...${NC}"
    tr -d '\r' < "$CF_DIR/cfnas.sh" > "$CF_DIR/cfnas.sh.tmp"
    mv "$CF_DIR/cfnas.sh.tmp" "$CF_DIR/cfnas.sh"
    chmod +x "$CF_DIR/cfnas.sh"
    
    # 检查并处理 cf.sh
    if [ ! -f "$CF_DIR/cf.sh" ]; then
        echo -e "${YELLOW}cf.sh 不存在，正在下载...${NC}"
        download_cfnas
    fi
    
    # 处理 cf.sh 文件格式
    echo -e "${BLUE}正在处理 CF 文件格式...${NC}"
    tr -d '\r' < "$CF_DIR/cf.sh" > "$CF_DIR/cf.sh.tmp"
    mv "$CF_DIR/cf.sh.tmp" "$CF_DIR/cf.sh"
    chmod +x "$CF_DIR/cf.sh"
    
    # 执行优选
    echo -e "${YELLOW}第一步: CFNAS IPv4 + IPv6 优选${NC}"
    if [ -f "$CF_DIR/cfnas.sh" ]; then
        # 保存当前的配置文件路径
        local original_config="$CONFIG_FILE"
        
        source "$CF_DIR/cfnas.sh"
        init_config
        init_install
        run_optimize "both"
        
        # 恢复配置文件路径
        CONFIG_FILE="$original_config"
    else
        echo -e "${RED}错误: 无法找到 cfnas.sh 文件${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}第二步: CF IPv4 + IPv6 优选${NC}"
    if [ -f "$CF_DIR/cf.sh" ]; then
        bash "$CF_DIR/cf.sh" --both
    else
        echo -e "${RED}错误: 无法找到 cf.sh 文件${NC}"
        return 1
    fi
    
    # 合并结果
    if merge_results; then
        echo -e "\n${YELLOW}第三步: 上传结果到 GitHub${NC}"
        
        # 尝试上传
        if upload_to_github; then
            echo -e "${GREEN}全部操作已完成！${NC}"
        else
            echo -e "${YELLOW}上传未完成，但优选和合并已成功${NC}"
            echo -e "${YELLOW}您可以稍后通过主菜单手动上传结果${NC}"
        fi
    else
        echo -e "${RED}合并结果失败，跳过上传${NC}"
        return 1
    fi
}

# 更新配置
update_config() {
    local key=$1
    local value=$2
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
    fi
    local temp_file=$(mktemp)
    jq ".$key = \"$value\"" "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
    echo -e "${GREEN}配置已更新${NC}"
}

# GitHub 配置菜单
configure_github() {
    while true; do
        clear
        echo -e "${BLUE}GitHub 配置${NC}"
        echo
        
        # 读取当前配置
        local current_token=$(jq -r '.github.token // "未设置"' "$CONFIG_FILE" 2>/dev/null || echo "未设置")
        local current_repo=$(jq -r '.github.repo // "未设置"' "$CONFIG_FILE" 2>/dev/null || echo "未设置")
        local current_branch=$(jq -r '.github.branch // "main"' "$CONFIG_FILE" 2>/dev/null || echo "main")
        
        # 显示当前配置（令牌只显示前后4位）
        echo -e "当前配置："
        if [ "$current_token" != "未设置" ]; then
            token_length=${#current_token}
            token_display="${current_token:0:4}...${current_token: -4}"
            echo -e "1) 访问令牌: ${GREEN}${token_display}${NC}"
        else
            echo -e "1) 访问令牌: ${YELLOW}未设置${NC}"
        fi
        echo -e "2) 仓库名称: ${GREEN}${current_repo}${NC} (格式: 用户名/仓库名)"
        echo -e "3) 分支名: ${GREEN}${current_branch}${NC}"
        echo -e "0) 返回上级菜单"
        echo
        echo -e "${GREEN}请选择要修改的选项 [0-3]: ${NC}"
        
        read -r choice
        case $choice in
            1)
                echo -e "请输入 GitHub 访问令牌 (Personal Access Token): "
                read -r new_token
                [ -n "$new_token" ] && update_config "github.token" "$new_token"
                ;;
            2)
                echo -e "请输入仓库名称 (格式: 用户名/仓库名): "
                read -r new_repo
                [ -n "$new_repo" ] && update_config "github.repo" "$new_repo"
                ;;
            3)
                echo -e "请输入分支名 [默认: main]: "
                read -r new_branch
                [ -n "$new_branch" ] && update_config "github.branch" "$new_branch"
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选项${NC}"
                ;;
        esac
        read -p "按回车键继续..."
    done
}

# 按回车继续
press_enter() {
    echo -e "\n${BLUE}按回车键继续...${NC}"
    read
}

# 初始化安装
init_install() {
    log "INFO" "开始初始化安装..."
    
    # 检测系统架构
    local arch=$(uname -m)
    local cf_binary="cf-amd64"
    case "$arch" in
        x86_64|amd64)
            cf_binary="cf-amd64"
            ;;
        aarch64|arm64)
            cf_binary="cf-arm64"
            ;;
        *)
            log "ERROR" "不支持的系统架构: $arch"
            return 1
            ;;
    esac
    log "INFO" "检测到系统架构: $arch, 将使用 $cf_binary"
    
    # 创建必要的目录
    mkdir -p "$CF_DIR/ips"
    
    # 下载所需文件
    local files_to_download=(
        "https://git.910626.xyz/https://raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/CloudflareST_linux_amd64|$CF_DIR/cf|binary"
        "https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/files/locations.json|$CF_DIR/locations.json|text"
        "https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/files/ips-v4.txt|$CF_DIR/ips-v4.txt|text"
        "https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/files/ips-v6.txt|$CF_DIR/ips-v6.txt|text"
    )
    
    local success=true
    for file_info in "${files_to_download[@]}"; do
        IFS='|' read -r url output type <<< "$file_info"
        
        # 备用下载地址
        local backup_url="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/files/$(basename "$url")"
        
        if [ -f "$output" ]; then
            if verify_file "$output" "$type"; then
                log "INFO" "文件已存在且完整: $(basename "$output"), 跳过下载"
                continue
            else
                log "WARN" "现有文件可能损坏，重新下载: $(basename "$output")"
                rm -f "$output"
            fi
        fi
        
        if ! download_file "$url" "$output" "$backup_url" "$type"; then
            success=false
            break
        fi
        
        if [ "$type" = "binary" ]; then
            chmod +x "$output"
        fi
    done
    
    if [ "$success" = true ]; then
        log "INFO" "初始化安装完成"
        return 0
    else
        log "ERROR" "初始化安装失败"
        return 1
    fi
}

# 更新脚本
update_scripts() {
    echo -e "${BLUE}正在更新脚本...${NC}"
    
    # 下载最新的 main.sh
    local script_url="https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/main.sh"
    local script_backup_url="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/main.sh"
    local tmp_script="/tmp/main.sh.tmp.$$"
    
    # 清理旧的临时文件
    trap 'rm -f "$tmp_script"' EXIT
    
    # 下载脚本
    if curl -sSLf "$script_url" -o "$tmp_script" || curl -sSLf "$script_backup_url" -o "$tmp_script"; then
        # 验证下载的文件
        if [ -s "$tmp_script" ] && head -n1 "$tmp_script" | grep -q "#!/bin/bash"; then
            # 确保文件以换行符结尾
            echo "" >> "$tmp_script"
            convert_line_endings "$tmp_script"
            
            # 安全地移动文件
            if cp "$tmp_script" "$0" && chmod +x "$0"; then
                echo -e "${GREEN}脚本更新成功，请重新运行脚本${NC}"
                exit 0
            else
                echo -e "${RED}无法保存更新的脚本${NC}"
            fi
        else
            echo -e "${RED}下载的脚本文件不完整或格式错误${NC}"
        fi
    else
        echo -e "${RED}下载脚本失败${NC}"
    fi
    
    return 1
}

# 查看日志
view_logs() {
    echo -e "${BLUE}日志文件: ${CF_LOGS_DIR}/main.log${NC}"
    echo -e "${BLUE}最新日志内容:${NC}"
    tail -n 20 "${CF_LOGS_DIR}/main.log"
}

# 执行优选
run_optimize() {
    local mode="$1"
    local cf_binary="$CF_DIR/cf"
    
    # 验证必要文件
    local required_files=("$cf_binary" "$CF_DIR/locations.json")
    case "$mode" in
        "ipv4"|"both")
            required_files+=("$CF_DIR/ips-v4.txt")
            ;;
        "ipv6"|"both")
            required_files+=("$CF_DIR/ips-v6.txt")
            ;;
    esac
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "ERROR" "缺少必要文件: $file"
            return 1
        fi
        
        if [ ! -r "$file" ]; then
            log "ERROR" "文件无读取权限: $file"
            return 1
        fi
    done
    
    # 验证可执行文件
    if [ ! -x "$cf_binary" ]; then
        log "WARN" "修复 cf 可执行权限"
        chmod +x "$cf_binary"
    fi
    
    # 创建输出目录
    local output_dir="$CF_DIR/ips"
    mkdir -p "$output_dir"
    
    # 设置优选参数
    local timeout=5
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        case "$mode" in
            "ipv4")
                log "INFO" "开始 IPv4 优选..."
                if "$cf_binary" --ipv4 -o "$output_dir/cfnas_ipv4.txt" -t "$timeout"; then
                    log "INFO" "IPv4 优选完成"
                    return 0
                fi
                ;;
            "ipv6")
                log "INFO" "开始 IPv6 优选..."
                if "$cf_binary" --ipv6 -o "$output_dir/cfnas_ipv6.txt" -t "$timeout"; then
                    log "INFO" "IPv6 优选完成"
                    return 0
                fi
                ;;
            "both")
                log "INFO" "开始 IPv4 优选..."
                if ! "$cf_binary" --ipv4 -o "$output_dir/cfnas_ipv4.txt" -t "$timeout"; then
                    log "ERROR" "IPv4 优选失败"
                else
                    log "INFO" "IPv4 优选完成"
                fi
                
                log "INFO" "开始 IPv6 优选..."
                if ! "$cf_binary" --ipv6 -o "$output_dir/cfnas_ipv6.txt" -t "$timeout"; then
                    log "ERROR" "IPv6 优选失败"
                else
                    log "INFO" "IPv6 优选完成"
                fi
                
                # 只要有一个成功就返回成功
                if [ -s "$output_dir/cfnas_ipv4.txt" ] || [ -s "$output_dir/cfnas_ipv6.txt" ]; then
                    return 0
                fi
                ;;
            *)
                log "ERROR" "无效的优选模式: $mode"
                return 1
                ;;
        esac
        
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((5 * retry_count))
            log "WARN" "优选失败，等待 ${wait_time} 秒后重试..."
            sleep "$wait_time"
        fi
    done
    
    log "ERROR" "优选失败，达到最大重试次数"
    return 1
}

# 主函数
main() {
    # 初始化环境
    init_environment
    
    # 处理命令行参数
    case "$1" in
        "--ipv4")   source cfnas.sh && run_optimize "ipv4" ;;
        "--ipv6")   source cfnas.sh && run_optimize "ipv6" ;;
        "--all")    run_all_optimizations ;;
        "--update") update_scripts ;;
        *)          show_menu ;;
    esac
}

# 程序入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi