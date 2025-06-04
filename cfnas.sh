#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 在 cfnas.sh 开头添加参数处理
if [ "$1" = "--config" ]; then
    # 初始化配置
    init_config
    # 直接显示配置菜单
    show_config_menu
    exit 0
elif [ "$1" = "--auto" ]; then
    # 自动运行模式 - 组合优选
    init_config
    init_install
    echo "开始自动运行 IPv4 + IPv6 组合优选..."
    run_optimize "both"
    exit 0
elif [ "$1" = "--ipv4" ]; then
    # 自动运行模式 - 仅 IPv4
    init_config
    init_install
    echo "开始自动运行 IPv4 优选..."
    run_optimize "ipv4"
    exit 0
elif [ "$1" = "--ipv6" ]; then
    # 自动运行模式 - 仅 IPv6
    init_config
    init_install
    echo "开始自动运行 IPv6 优选..."
    run_optimize "ipv6"
    exit 0
fi

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/cloudflare"

# 定义下载基础URL
BASE_URL="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/Cloudflare_vless_trojan/main/cf"

# 确保工作目录存在
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit 1

# 添加配置文件路径
CONFIG_FILE="$WORK_DIR/config.conf"

# 初始化安装
init_install() {
    echo -e "${BLUE}开始初始化安装...${NC}"
    
    # 检查并安装必要的工具
    check_dependencies
    
    # 获取系统架构
    detect_arch
    
    # 下载必要文件
    download_required_files
    
    echo -e "${GREEN}初始化安装完成${NC}"
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查必要的命令
    for cmd in curl wget jq; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    # 如果有缺失的依赖，尝试安装
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}检测到缺失的依赖: ${missing_deps[*]}${NC}"
        echo -e "${BLUE}尝试安装缺失的依赖...${NC}"
        
        # 检测包管理器
        if command -v apt >/dev/null 2>&1; then
            apt update
            apt install -y ${missing_deps[@]}
        elif command -v yum >/dev/null 2>&1; then
            yum install -y ${missing_deps[@]}
        elif command -v opkg >/dev/null 2>&1; then
            opkg update
            opkg install ${missing_deps[@]}
        else
            echo -e "${RED}无法检测到支持的包管理器，请手动安装以下依赖: ${missing_deps[*]}${NC}"
            exit 1
        fi
    fi
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  BINARY="cf-amd64" ;;
        aarch64) BINARY="cf-arm64" ;;
        armv7l)  BINARY="cf-arm" ;;
        i686)    BINARY="cf-386" ;;
        *)
            echo -e "${RED}不支持的系统架构: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}检测到系统架构: $ARCH, 将使用 $BINARY${NC}"
}

# 下载必要文件
download_required_files() {
    # 下载优选程序
    download_file "$BINARY" "cf"
    chmod +x "cf"
    
    # 下载配置文件
    download_file "locations.json" "locations.json"
    download_file "ips-v4.txt" "ips-v4.txt"
    download_file "ips-v6.txt" "ips-v6.txt"
}

# 添加默认配置
init_config() {
    # 确保配置文件存在
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
IP_COUNT=10
SELECTED_COUNTRIES=""
PORTS="443"
EOF
    fi
    
    # 确保配置值有效，如果无效则设置默认值
    source "$CONFIG_FILE"
    
    # 验证 IP_COUNT，如果无效则设置默认值
    if ! [[ "$IP_COUNT" =~ ^[1-9][0-9]?$|^100$ ]]; then
        IP_COUNT=10
        sed -i "s/IP_COUNT=.*/IP_COUNT=$IP_COUNT/" "$CONFIG_FILE"
    fi

    # 验证 PORTS，如果无效则设置默认值
    if [ -z "$PORTS" ]; then
        PORTS="443"
        sed -i "s/PORTS=.*/PORTS=\"$PORTS\"/" "$CONFIG_FILE"
    fi
}

# 显示配置菜单
show_config_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================${NC}"
        echo -e "${GREEN}        配置设置菜单          ${NC}"
        echo -e "${BLUE}================================${NC}"
        echo -e "当前配置："
        echo -e "1. IP数量: ${YELLOW}$IP_COUNT${NC}"
        echo -e "2. 端口: ${YELLOW}$PORTS${NC}"
        echo -e "3. 已选国家/地区: ${YELLOW}$SELECTED_COUNTRIES${NC}"
        echo -e "${BLUE}--------------------------------${NC}"
        echo "0. 返回主菜单"
        echo -e "${BLUE}================================${NC}"
        
        read -p "请选择要修改的配置 [0-3]: " choice
        
        case $choice in
            1)
                read -p "请输入要优选的IP数量 (1-100): " new_count
                if [[ "$new_count" =~ ^[1-9][0-9]?$|^100$ ]]; then
                    IP_COUNT=$new_count
                    sed -i "s/IP_COUNT=.*/IP_COUNT=$IP_COUNT/" "$CONFIG_FILE"
                    echo -e "${GREEN}IP数量已更新${NC}"
                else
                    echo -e "${RED}无效的数量，请输入1-100之间的数字${NC}"
                fi
                read -p "按回车键继续..."
                ;;
            2)
                read -p "请输入端口号（多个端口用空格分隔）: " new_ports
                if [[ "$new_ports" =~ ^[0-9\ ]+$ ]]; then
                    PORTS=$new_ports
                    sed -i "s/PORTS=.*/PORTS=\"$PORTS\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}端口已更新${NC}"
                else
                    echo -e "${RED}无效的端口号${NC}"
                fi
                read -p "按回车键继续..."
                ;;
            3)
                select_country
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 下载文件函数
download_file() {
    local filename=$1
    local target=$2
    
    if [ ! -f "$target" ]; then
        echo "正在下载 $filename ..."
        if command -v curl >/dev/null 2>&1; then
            curl -sSL "$BASE_URL/$filename" -o "$target"
            if [ $? -ne 0 ]; then
                echo "下载失败: $filename"
                return 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            wget -q "$BASE_URL/$filename" -O "$target"
            if [ $? -ne 0 ]; then
                echo "下载失败: $filename"
                return 1
            fi
        else
            echo "错误: 请安装 curl 或 wget"
            exit 1
        fi
        echo "下载完成: $target"
    else
        echo "文件已存在: $target, 跳过下载"
    fi
}

# 修改优选函数
run_optimize() {
    local mode=$1
    cd "$WORK_DIR" || exit 1
    
    # 检查可执行文件是否存在且可执行
    if [ ! -f "cf" ] || [ ! -x "cf" ]; then
        echo "错误: cf 程序不存在或不可执行，尝试重新下载..."
        download_file "$BINARY" "cf"
        chmod +x "cf"
        if [ ! -x "cf" ]; then
            echo "错误: 无法设置执行权限或下载失败"
            return 1
        fi
    fi

    # 加载配置文件中的 IP_COUNT
    source "$CONFIG_FILE"

    # 创建输出目录和文件
    mkdir -p "$SCRIPT_DIR/ips"
    output_file="$SCRIPT_DIR/ips/selected.txt"
    > "$output_file"  # 清空或创建文件
    
    process_results() {
        local result_file=$1
        local is_ipv6=$2
        declare -A country_counts  # 使用关联数组来跟踪每个国家的IP数量
        
        tail -n +2 "$result_file" | while IFS=, read -r ip dc region city latency; do
            iata=${dc:0:3}
            cca2=$(jq -r --arg iata "$iata" '.[] | select(.iata == $iata) | .cca2' locations.json)
            
            # 初始化国家计数器（如果不存在）
            [[ -z "${country_counts[$cca2]}" ]] && country_counts[$cca2]=0
            
            if [ -n "$SELECTED_COUNTRIES" ]; then
                if [[ "$SELECTED_COUNTRIES" == *"$cca2"* ]] && [ "${country_counts[$cca2]}" -lt "$IP_COUNT" ]; then
                    for port in $PORTS; do
                        if [ "$is_ipv6" = true ]; then
                            echo "[${ip}]:${port}#${cca2}" >> "$output_file"
                        else
                            echo "${ip}:${port}#${cca2}" >> "$output_file"
                        fi
                    done
                    country_counts[$cca2]=$((country_counts[$cca2] + 1))
                fi
            else
                if [ "${country_counts[$cca2]}" -lt "$IP_COUNT" ]; then
                    for port in $PORTS; do
                        if [ "$is_ipv6" = true ]; then
                            echo "[${ip}]:${port}#${cca2}" >> "$output_file"
                        else
                            echo "${ip}:${port}#${cca2}" >> "$output_file"
                        fi
                    done
                    country_counts[$cca2]=$((country_counts[$cca2] + 1))
                fi
            fi
        done
    }

    case $mode in
        "ipv4")
            echo "开始 IPv4 优选..."
            if ! ./cf -ips 4 -outfile ipv4_result.csv; then
                echo "IPv4 优选失败"
                return 1
            fi
            process_results "ipv4_result.csv" false
            ;;
            
        "ipv6")
            echo "开始 IPv6 优选..."
            if ! ./cf -ips 6 -outfile ipv6_result.csv; then
                echo "IPv6 优选失败"
                return 1
            fi
            process_results "ipv6_result.csv" true
            ;;
            
        "both")
            echo "开始 IPv4 优选..."
            if ! ./cf -ips 4 -outfile ipv4_result.csv; then
                echo "IPv4 优选失败"
                return 1
            fi
            process_results "ipv4_result.csv" false
            
            echo "开始 IPv6 优选..."
            if ! ./cf -ips 6 -outfile ipv6_result.csv; then
                echo "IPv6 优选失败"
                return 1
            fi
            process_results "ipv6_result.csv" true
            ;;
    esac
    
    echo "优选完成，结果保存在: $output_file"
}

# 国家选择函数
select_country() {
    if ! command -v jq &> /dev/null; then
        echo "错误: 请先安装 jq"
        echo "Ubuntu/Debian: sudo apt-get install jq"
        echo "CentOS/RHEL: sudo yum install jq"
        read -p "按回车键继续..."
        return 1
    fi

    # 检查 locations.json 是否存在
    if [ ! -f "locations.json" ]; then
        echo "错误: locations.json 文件不存在"
        read -p "按回车键继续..."
        return 1
    fi

    local return_to_main=0
    while [ $return_to_main -eq 0 ]; do
        clear
        echo "================================"
        echo "          区域选择菜单           "
        echo "================================"
        
        # 获取唯一的区域列表并排序
        regions=$(jq -r '.[].region' locations.json | sort -u)
        readarray -t region_list <<< "$regions"
        
        # 显示区域列表
        count=1
        for region in "${region_list[@]}"; do
            echo "$count. $region"
            count=$((count + 1))
        done
        
        echo "0. 返回主菜单"
        echo "================================"
        read -p "请选择区域 [0-$((${#region_list[@]}))]:" region_choice

        if [[ "$region_choice" =~ ^[0-9]+$ ]]; then
            if [ "$region_choice" -eq 0 ]; then
                return_to_main=1
                break
            elif [ "$region_choice" -le "${#region_list[@]}" ]; then
                selected_region="${region_list[$((region_choice-1))]}"
                
                local return_to_region=0
                while [ $return_to_region -eq 0 ]; do
                    clear
                    echo "================================"
                    echo "     $selected_region 国家列表    "
                    echo "================================"
                    echo "当前已选: $SELECTED_COUNTRIES"
                    echo "================================"
                    
                    # 获取该区域的国家代码
                    countries=$(jq -r --arg region "$selected_region" \
                        '.[] | select(.region == $region) | .cca2' locations.json | sort -u)
                    readarray -t country_codes <<< "$countries"
                    
                    # 横向显示国家列表，每行5个
                    count=1
                    total=${#country_codes[@]}
                    for ((i=0; i<total; i++)); do
                        # 检查是否已选中
                        if [[ "$SELECTED_COUNTRIES" == *"${country_codes[i]}"* ]]; then
                            printf "%2d. [*]%-4s" "$count" "${country_codes[i]}"
                        else
                            printf "%2d. [ ]%-4s" "$count" "${country_codes[i]}"
                        fi
                        if [ $((count % 5)) -eq 0 ] || [ "$count" -eq "$total" ]; then
                            echo
                        else
                            printf "    "
                        fi
                        count=$((count + 1))
                    done
                    
                    echo "================================"
                    echo "输入数字选择/取消选择国家"
                    echo "a. 全选当前区域"
                    echo "c. 清空所有选择"
                    echo "0. 返回区域选择"
                    echo "================================"
                    read -p "请输入选项:" choice
                    
                    case $choice in
                        [0-9]*)
                            if [ "$choice" = "0" ]; then
                                return_to_region=1
                            else
                                # 分割输入的数字
                                IFS=' ' read -ra selections <<< "$choice"
                                for num in "${selections[@]}"; do
                                    if [[ "$num" =~ ^[1-9][0-9]*$ ]] && [ "$num" -le "$total" ]; then
                                        selected_code="${country_codes[$((num-1))]}"
                                        if [[ "$SELECTED_COUNTRIES" == *"$selected_code"* ]]; then
                                            # 取消选择
                                            SELECTED_COUNTRIES=${SELECTED_COUNTRIES//$selected_code/}
                                        else
                                            # 添加选择
                                            SELECTED_COUNTRIES="$SELECTED_COUNTRIES $selected_code"
                                        fi
                                        # 清理多余的空格
                                        SELECTED_COUNTRIES=$(echo "$SELECTED_COUNTRIES" | tr -s ' ' | sed 's/^ *//;s/ *$//')
                                    fi
                                done
                                # 更新配置文件
                                sed -i "s/SELECTED_COUNTRIES=.*/SELECTED_COUNTRIES=\"$SELECTED_COUNTRIES\"/" "$CONFIG_FILE"
                            fi
                            ;;
                        a)
                            # 全选当前区域
                            for code in "${country_codes[@]}"; do
                                if [[ "$SELECTED_COUNTRIES" != *"$code"* ]]; then
                                    SELECTED_COUNTRIES="$SELECTED_COUNTRIES $code"
                                fi
                            done
                            SELECTED_COUNTRIES=$(echo "$SELECTED_COUNTRIES" | tr -s ' ' | sed 's/^ *//;s/ *$//')
                            sed -i "s/SELECTED_COUNTRIES=.*/SELECTED_COUNTRIES=\"$SELECTED_COUNTRIES\"/" "$CONFIG_FILE"
                            ;;
                        c)
                            # 清空选择
                            SELECTED_COUNTRIES=""
                            sed -i "s/SELECTED_COUNTRIES=.*/SELECTED_COUNTRIES=\"\"/" "$CONFIG_FILE"
                            ;;
                        *)
                            echo "无效选择"
                            read -p "按回车键继续..."
                            ;;
                    esac
                done
            fi
        else
            echo "无效选择，请重试"
            read -p "按回车键继续..."
        fi
    done
}

# 修改主菜单函数
show_menu() {
    while true; do
        clear
        echo "================================"
        echo "        IP 优选工具菜单          "
        echo "================================"
        echo "工作目录: $WORK_DIR"
        echo "--------------------------------"
        echo "当前配置："
        echo "- IP数量: $IP_COUNT"
        echo "- 端口: $PORTS"
        echo "- 已选国家: $SELECTED_COUNTRIES"
        echo "================================"
        echo "1. IPv4 优选"
        echo "2. IPv6 优选"
        echo "3. IPv4 + IPv6 组合优选"
        echo "4. 重新下载文件"
        echo "5. 查看优选结果"
        echo "6. 配置设置"
        echo "7. 国家/地区优选"
        echo "8. 返回主菜单"
        echo "0. 退出"
        echo "================================"
        echo "使用说明："
        echo "1. 首次使用建议先进行配置设置"
        echo "2. IPv4/IPv6 优选说明："
        echo "   - IPv4：适用于大多数网络环境"
        echo "   - IPv6：适用于支持IPv6的网络"
        echo "   - 组合优选：同时获取两种IP"
        echo "3. 优选步骤建议："
        echo "   a) 设置合适的IP数量（菜单6）"
        echo "   b) 选择所需端口（菜单6）"
        echo "   c) 选择目标国家/地区（菜单7）"
        echo "   d) 执行优选（菜单1-3）"
        echo "4. 优选完成后可查看结果（菜单5）"
        echo "================================"
        read -p "请选择操作 [0-8]: " choice

        case $choice in
            1)
                echo "开始 IPv4 优选..."
                echo "提示：优选过程可能需要几分钟，请耐心等待"
                run_optimize "ipv4"
                read -p "按回车键继续..."
                ;;
            2)
                echo "开始 IPv6 优选..."
                echo "提示：优选过程可能需要几分钟，请耐心等待"
                echo "注意：请确保您的网络支持 IPv6"
                run_optimize "ipv6"
                read -p "按回车键继续..."
                ;;
            3)
                echo "开始 IPv4 + IPv6 组合优选..."
                echo "提示：优选过程可能需要较长时间，请耐心等待"
                echo "注意：如果网络不支持 IPv6，可能会出现部分错误提示"
                run_optimize "both"
                read -p "按回车键继续..."
                ;;
            4)
                cd "$WORK_DIR" || exit 1
                echo "正在重新下载文件..."
                echo "提示：这将会覆盖现有的程序文件，但不会影响配置"
                rm -f cf locations.json ips-v4.txt ips-v6.txt
                init_install
                echo "文件已重新下载完成!"
                read -p "按回车键继续..."
                ;;
            5)
                cd "$WORK_DIR" || exit 1
                echo "================================"
                echo "          优选结果查看          "
                echo "================================"
                if [ -f "output/selected.txt" ]; then
                    echo "最新优选结果："
                    cat "output/selected.txt"
                    echo "--------------------------------"
                    echo "结果说明："
                    echo "- 格式：IP:端口#国家代码"
                    echo "- IPv6 格式：[IP]:端口#国家代码"
                    echo "- 结果已保存在：$WORK_DIR/output/selected.txt"
                else
                    echo "暂无优选结果，请先进行优选操作"
                fi
                read -p "按回车键继续..."
                ;;
            6)
                show_config_menu
                ;;
            7)
                select_country
                ;;
            8)
                echo "返回主菜单..."
                if [ -f "/root/cf/main.sh" ]; then
                    cd /root/cf && exec bash main.sh
                else
                    echo -e "${RED}错误: 无法找到 /root/cf/main.sh${NC}"
                    read -p "按回车键继续..."
                fi
                ;;
            0)
                echo "退出程序..."
                exit 0
                ;;
            *)
                echo "无效选择，请重试"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 主入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${BLUE}初始化程序...${NC}"
    echo -e "${GREEN}工作目录: $WORK_DIR${NC}"
    init_config
    init_install
    
    # 处理命令行参数
    case "$1" in
        "--ipv4")
            echo -e "${BLUE}执行 IPv4 优选...${NC}"
            run_optimize "ipv4"
            ;;
        "--ipv6")
            echo -e "${BLUE}执行 IPv6 优选...${NC}"
            run_optimize "ipv6"
            ;;
        "--auto")
            echo -e "${BLUE}执行 IPv4 + IPv6 组合优选...${NC}"
            run_optimize "both"
            ;;
        *)
            echo -e "${BLUE}进入优选菜单...${NC}"
            show_menu
            ;;
    esac
fi 
