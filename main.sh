#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置文件路径
CONFIG_FILE="$CF_DIR/config.json"

# 清理日志函数
clean_log() {
    # 如果需要清理日志，在这里实现
    :
}

# 转换文件换行符
convert_line_endings() {
    local file=$1
    if [ -f "$file" ]; then
        # 使用 sed 命令删除 \r 字符
        echo -e "${BLUE}转换文件换行符...${NC}"
        sed -i 's/\r$//' "$file"
        # 使用 dos2unix（如果可用）作为备选方案
        if command -v dos2unix >/dev/null 2>&1; then
            dos2unix "$file" >/dev/null 2>&1
        fi
        echo -e "${GREEN}换行符转换完成${NC}"
    fi
}

# 添加日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" >> "${CF_DIR}/main.log"
    
    # 同时输出到控制台
    case $level in
        ERROR) echo -e "${RED}${message}${NC}" ;;
        WARN)  echo -e "${YELLOW}${message}${NC}" ;;
        INFO)  echo -e "${GREEN}${message}${NC}" ;;
        DEBUG) echo -e "${BLUE}${message}${NC}" ;;
    esac
}

# 下载或更新 cfnas.sh
download_cfnas() {
    log "INFO" "开始下载 cfnas.sh..."
    # 添加重试机制
    local max_retries=3
    local retry_count=0
    
    # 直接使用固定的 GitHub 链接
    local cfnas_url="https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cfnas.sh"
    local cf_url="https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cf.sh"
    
    # 备用链接（使用代理）
    local cfnas_backup_url="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cfnas.sh"
    local cf_backup_url="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/cf.sh"
    
    while [ $retry_count -lt $max_retries ]; do
        # 尝试直接下载 cfnas.sh
        if curl -sSL --connect-timeout 10 "$cfnas_url" -o "$TMP_FILE" || \
           curl -sSL --connect-timeout 10 "$cfnas_backup_url" -o "$TMP_FILE"; then
            
            if [ -s "$TMP_FILE" ] && grep -q "#!/bin/bash" "$TMP_FILE"; then
                echo "" >> "$TMP_FILE"
                convert_line_endings "$TMP_FILE"
                mv "$TMP_FILE" "$CF_DIR/cfnas.sh"
                chmod +x "$CF_DIR/cfnas.sh"
                log "INFO" "cfnas.sh 下载成功"
                
                # 下载 cf.sh
                echo -e "${BLUE}开始下载 cf.sh...${NC}"
                if curl -sSL "$cf_url" -o "$CF_TMP_FILE" || \
                   curl -sSL "$cf_backup_url" -o "$CF_TMP_FILE"; then
                    
                    if [ -s "$CF_TMP_FILE" ] && grep -q "#!/bin/bash" "$CF_TMP_FILE"; then
                        echo "" >> "$CF_TMP_FILE"
                        convert_line_endings "$CF_TMP_FILE"
                        mv "$CF_TMP_FILE" "$CF_DIR/cf.sh"
                        chmod +x "$CF_DIR/cf.sh"
                        echo -e "${GREEN}cf.sh 下载成功${NC}"
                        return 0
                    else
                        rm -f "$CF_TMP_FILE"
                        echo -e "${RED}下载的 cf.sh 文件不完整或格式错误${NC}"
                    fi
                else
                    rm -f "$CF_TMP_FILE"
                    echo -e "${RED}cf.sh 下载失败${NC}"
                fi
            else
                rm -f "$TMP_FILE"
                echo -e "${RED}下载的 cfnas.sh 文件不完整或格式错误${NC}"
            fi
        fi
        
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            echo -e "${YELLOW}下载失败，等待重试 ($retry_count/$max_retries)...${NC}"
            sleep 2
        fi
    done
    
    echo -e "${RED}达到最大重试次数，下载失败${NC}"
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

# 主函数
main() {
    # 创建 cf 目录
    CF_DIR="/root/cf"
    if [ ! -d "$CF_DIR" ]; then
        echo -e "${BLUE}创建 cf 目录...${NC}"
        mkdir -p "$CF_DIR"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}cf 目录创建成功${NC}"
        else
            echo -e "${RED}cf 目录创建失败${NC}"
            exit 1
        fi
    fi

    # 初始化配置文件
    CONFIG_FILE="$CF_DIR/config.json"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}创建配置文件...${NC}"
        echo "{}" > "$CONFIG_FILE"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}配置文件创建成功${NC}"
        else
            echo -e "${RED}配置文件创建失败${NC}"
            exit 1
        fi
    fi

    # 处理命令行参数
    case "$1" in
        "--update")
            echo -e "${BLUE}更新模式${NC}"
            FORCE_UPDATE=true
            ;;
        "--ipv4")
            echo -e "${BLUE}IPv4 优选模式${NC}"
            source "$CF_DIR/cfnas.sh"
            init_config
            init_install
            run_optimize "ipv4"
            ;;
        "--ipv6")
            echo -e "${BLUE}IPv6 优选模式${NC}"
            source "$CF_DIR/cfnas.sh"
            init_config
            init_install
            run_optimize "ipv6"
            ;;
        "--all")
            run_all_optimizations
            ;;
        *)
            # 主菜单部分
            while true; do
                clear
                echo -e "${YELLOW}请选择操作模式:${NC}"
                echo -e "1. ${GREEN}CFNAS IPv4 优选${NC}"
                echo -e "2. ${GREEN}CFNAS IPv6 优选${NC}"
                echo -e "3. ${GREEN}全部优选 (CFNAS + CF)${NC}"
                echo -e "4. ${GREEN}CF IPv4 优选${NC}"
                echo -e "5. ${GREEN}CF IPv6 优选${NC}"
                echo -e "6. ${GREEN}更新脚本${NC}"
                echo -e "7. ${GREEN}进入 CFNAS 菜单${NC}"
                echo -e "8. ${GREEN}上传结果到 GitHub${NC}"
                echo -e "9. ${GREEN}配置 GitHub${NC}"
                echo -e "0. ${RED}退出${NC}"
                read -p "请输入选项 [0-9]: " choice
                
                case $choice in
                    1)
                        if [ ! -f "$CF_DIR/cfnas.sh" ]; then
                            echo -e "${YELLOW}cfnas.sh 不存在，正在下载...${NC}"
                            download_cfnas
                        fi
                        
                        echo -e "${BLUE}正在处理文件格式...${NC}"
                        tr -d '\r' < "$CF_DIR/cfnas.sh" > "$CF_DIR/cfnas.sh.tmp"
                        mv "$CF_DIR/cfnas.sh.tmp" "$CF_DIR/cfnas.sh"
                        chmod +x "$CF_DIR/cfnas.sh"
                        
                        if [ -f "$CF_DIR/cfnas.sh" ]; then
                            source "$CF_DIR/cfnas.sh"
                            init_config
                            init_install
                            run_optimize "ipv4"
                        else
                            echo -e "${RED}错误: 无法找到 cfnas.sh 文件${NC}"
                            exit 1
                        fi
                        read -p "按回车键继续..."
                        ;;
                    2)
                        if [ ! -f "$CF_DIR/cfnas.sh" ]; then
                            echo -e "${YELLOW}cfnas.sh 不存在，正在下载...${NC}"
                            download_cfnas
                        fi
                        
                        echo -e "${BLUE}正在处理文件格式...${NC}"
                        tr -d '\r' < "$CF_DIR/cfnas.sh" > "$CF_DIR/cfnas.sh.tmp"
                        mv "$CF_DIR/cfnas.sh.tmp" "$CF_DIR/cfnas.sh"
                        chmod +x "$CF_DIR/cfnas.sh"
                        
                        if [ -f "$CF_DIR/cfnas.sh" ]; then
                            source "$CF_DIR/cfnas.sh"
                            init_config
                            init_install
                            run_optimize "ipv6"
                        else
                            echo -e "${RED}错误: 无法找到 cfnas.sh 文件${NC}"
                            exit 1
                        fi
                        read -p "按回车键继续..."
                        ;;
                    3)
                        run_all_optimizations
                        read -p "按回车键继续..."
                        ;;
                    4)
                        if [ ! -f "$CF_DIR/cf.sh" ]; then
                            echo -e "${YELLOW}cf.sh 不存在，正在下载...${NC}"
                            download_cfnas
                        fi
                        
                        echo -e "${BLUE}正在处理文件格式...${NC}"
                        tr -d '\r' < "$CF_DIR/cf.sh" > "$CF_DIR/cf.sh.tmp"
                        mv "$CF_DIR/cf.sh.tmp" "$CF_DIR/cf.sh"
                        chmod +x "$CF_DIR/cf.sh"
                        
                        if [ -f "$CF_DIR/cf.sh" ]; then
                            bash "$CF_DIR/cf.sh" --ipv4
                        else
                            echo -e "${RED}错误: 无法找到 cf.sh 文件${NC}"
                            exit 1
                        fi
                        ;;
                    5)
                        if [ ! -f "$CF_DIR/cf.sh" ]; then
                            echo -e "${YELLOW}cf.sh 不存在，正在下载...${NC}"
                            download_cfnas
                        fi
                        
                        echo -e "${BLUE}正在处理文件格式...${NC}"
                        tr -d '\r' < "$CF_DIR/cf.sh" > "$CF_DIR/cf.sh.tmp"
                        mv "$CF_DIR/cf.sh.tmp" "$CF_DIR/cf.sh"
                        chmod +x "$CF_DIR/cf.sh"
                        
                        if [ -f "$CF_DIR/cf.sh" ]; then
                            bash "$CF_DIR/cf.sh" --ipv6
                        else
                            echo -e "${RED}错误: 无法找到 cf.sh 文件${NC}"
                            exit 1
                        fi
                        ;;
                    6)
                        FORCE_UPDATE=true
                        ;;
                    7)
                        bash cfnas.sh
                        ;;
                    8)
                        upload_to_github
                        read -p "按回车键继续..."
                        ;;
                    9)
                        configure_github
                        ;;
                    0)
                        exit 0
                        ;;
                    *)
                        echo -e "${RED}无效选项${NC}"
                        read -p "按回车键继续..."
                        ;;
                esac
            done
            ;;
    esac
}

# 如果直接运行此脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi