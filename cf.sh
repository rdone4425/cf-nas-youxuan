#!/bin/bash

###################
# 全局变量和常量定义 #
###################
readonly BASE_URL="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/qita/main/CloudflareSpeedTest/extracted/linux"
readonly IP_BASE_URL="https://git.910626.xyz/https://raw.githubusercontent.com/rdone4425/yuming-ip/main/ios_rule_script"
readonly IP_API_URL="http://ip-api.com/json"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# 目录和文件
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"  # 获取脚本实际所在目录
ORIGINAL_DIR=$(pwd)
INSTALL_DIR="${SCRIPT_DIR}/CloudflareST"
CONFIG_FILE="${INSTALL_DIR}/config.conf"
readonly IPS_DIR="${SCRIPT_DIR}/ips"

# 默认配置
readonly DEFAULT_CONFIG=(
    "# CloudflareSpeedTest配置文件"
    "# 每行一个参数,格式: 参数名=参数值"
    "# 注释行以#开头"
    ""
    "# 延迟测速线程数"
    "n=200"
    ""
    "# 延迟测速次数"
    "t=4"
    ""
    "# 选择的IP数量"
    "sl=10"
    ""
    "# 测速端口"
    "tp=443"
    ""
    "# 输出端口 (用于生成的txt文件，多个端口用逗号分隔)"
    "output_port=2096,443"
    ""
    "# 延迟上限(ms)"
    "tl=500"
    ""
    "# 下载测试配置"
    "# 禁用下载测速(删除此行启用下载测速)"
    "#dd"
    ""
    "# 下载测试地址(dd参数删除后此项生效)"
    "url=http://cp.cloudflare.com/generate_204"
    ""
    "# 下载速度下限(MB/s)"
    "#dl=5"
    ""
    "# 下载速度上限(MB/s)"
    "#dr=0"
)

###################
# 工具函数        #
###################
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    cd "$ORIGINAL_DIR"
    exit 1
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        error_exit "$1 命令未找到，请先安装"
    fi
}

###################
# 文件处理函数     #
###################
download_file() {
    local url="$1"
    local output="$2"
    local desc="$3"
    
    if [ -s "$output" ]; then
        echo -e "${GREEN}${desc}已存在，跳过下载${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}正在下载${desc}...${NC}"
    wget -q --show-progress "$url" -O "$output" || error_exit "下载${desc}失败"
}

check_update() {
    echo -e "${YELLOW}是否要更新现有文件？[y/N]${NC}"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -f CloudflareST ip.txt ipv6.txt
        echo -e "${GREEN}已删除现有文件，准备重新下载${NC}"
        return 0
    fi
    return 1
}

###################
# 配置管理函数     #
###################
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}未找到配置文件，创建默认配置...${NC}"
        printf "%s\n" "${DEFAULT_CONFIG[@]}" > "$CONFIG_FILE"
    fi
    mapfile -t CONFIG_ARRAY < "$CONFIG_FILE"
}

show_config() {
    echo -e "\n${GREEN}当前配置：${NC}"
    cat "$CONFIG_FILE"
}

edit_config() {
    echo -e "\n${GREEN}当前配置：${NC}"
    local i=1
    local options=()
    declare -A descriptions=(
        ["n"]="延迟测速线程数 (建议值: 50-1000)"
        ["t"]="延迟测速次数 (建议值: 2-10)"
        ["sl"]="选择的IP数量 (建议值: 1-1000)"
        ["tp"]="测速端口 (可选: 443, 80, 8080)"
        ["output_port"]="输出文件端口 (建议: 2096, 443, 80)"
        ["tl"]="延迟上限(ms) (建议值: 200-2000)"
        ["dd"]="下载测速开关 (启用/禁用)"
        ["url"]="下载测试地址"
        ["dl"]="下载速度下限(MB/s)"
        ["dr"]="下载速度上限(MB/s) (0 表示不限制)"
    )
    
    # 显示常规配置项
    for param in "n" "t" "sl" "tp" "output_port" "tl"; do
        local value=$(grep "^$param=" "$CONFIG_FILE" | cut -d'=' -f2)
        echo -e "${YELLOW}$i.${NC} $param=$value"
        echo -e "   ${GREEN}说明：${descriptions[$param]}${NC}"
        options+=("$param")
        ((i++))
    done

    # 显示下载测速状态
    if grep -q "^#dd" "$CONFIG_FILE" || ! grep -q "^dd" "$CONFIG_FILE"; then
        echo -e "${YELLOW}$i.${NC} 下载测速：当前已禁用"
    else
        echo -e "${YELLOW}$i.${NC} 下载测速：当前已启用"
    fi
    echo -e "   ${GREEN}说明：${descriptions[dd]}${NC}"
    options+=("dd")
    ((i++))

    # 显示下载相关配置
    for param in "url" "dl" "dr"; do
        local line=$(grep "^$param=" "$CONFIG_FILE" || grep "^#$param=" "$CONFIG_FILE")
        if [[ -n "$line" ]]; then
            echo -e "${YELLOW}$i.${NC} $line"
            echo -e "   ${GREEN}说明：${descriptions[$param]}${NC}"
            options+=("$param")
            ((i++))
        fi
    done
    
    echo -e "\n${YELLOW}请选择要修改的配置项 [1-$((i-1))] 或输入 0 返回：${NC}"
    read -r choice

    if [ "$choice" = "0" ]; then
        return 0
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        local param_name="${options[$((choice-1))]}"
        echo -e "\n${GREEN}当前修改：${descriptions[$param_name]}${NC}"
        
        case "$param_name" in
            dd)
                if grep -q "^#dd" "$CONFIG_FILE"; then
                    echo -e "${YELLOW}下载测速当前已禁用，是否要启用？[Y/n]：${NC}"
                    read -r answer
                    if [[ "$answer" =~ ^[Nn]$ ]]; then
                        echo -e "${YELLOW}保持禁用状态${NC}"
                    else
                        sed -i 's/^#dd/dd/' "$CONFIG_FILE"
                        # 同时启用下载速度限制
                        sed -i 's/^#dl=/dl=/' "$CONFIG_FILE"
                        sed -i 's/^#dr=/dr=/' "$CONFIG_FILE"
                        echo -e "${GREEN}已启用下载测速${NC}"
                        echo -e "${YELLOW}提示：您现在可以设置下载速度限制参数（dl和dr）${NC}"
                    fi
                else
                    echo -e "${YELLOW}下载测速当前已启用，是否要禁用？[y/N]：${NC}"
                    read -r answer
                    if [[ "$answer" =~ ^[Yy]$ ]]; then
                        sed -i 's/^dd/#dd/' "$CONFIG_FILE"
                        # 同时注释掉下载速度限制
                        sed -i 's/^dl=/#dl=/' "$CONFIG_FILE"
                        sed -i 's/^dr=/#dr=/' "$CONFIG_FILE"
                        echo -e "${GREEN}已禁用下载测速${NC}"
                    else
                        echo -e "${YELLOW}保持启用状态${NC}"
                    fi
                fi
                ;;
            tp|output_port)
                echo -e "${YELLOW}请选择端口（多选请用逗号分隔，如：443,2096）：${NC}"
                echo "1. 443 (默认，推荐)"
                echo "2. 80"
                echo "3. 2096"
                echo "4. 8080"
                echo "5. 自定义"
                read -r port_choice
                
                # 处理端口选择
                if [[ "$port_choice" =~ ^[1-5](,[1-5])*$ ]]; then
                    # 处理多选
                    new_value=""
                    for choice in ${port_choice//,/ }; do
                        case $choice in
                            1) port="443";;
                            2) port="80";;
                            3) port="2096";;
                            4) port="8080";;
                            5) 
                                echo -e "${YELLOW}请输入自定义端口：${NC}"
                                read -r custom_port
                                port="$custom_port"
                                ;;
                        esac
                        new_value="${new_value}${new_value:+,}${port}"
                    done
                elif [[ "$port_choice" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                    # 直接输入的端口号（逗号分隔）
                    new_value="$port_choice"
                else
                    echo -e "${RED}无效的选择！${NC}"
                    return 1
                fi
                
                sed -i "s/^$param_name=.*/$param_name=$new_value/" "$CONFIG_FILE"
                ;;
            url)
                echo -e "${YELLOW}请输入新的下载测试地址：${NC}"
                echo "1. http://cp.cloudflare.com/generate_204 (默认)"
                echo "2. 自定义地址"
                read -r url_choice
                case $url_choice in
                    1) new_value="http://cp.cloudflare.com/generate_204";;
                    2)
                        echo -e "${YELLOW}请输入完整的URL地址：${NC}"
                        read -r new_value
                        ;;
                    *)
                        echo -e "${RED}无效的选择！${NC}"
                        return 1
                        ;;
                esac
                sed -i "s|^$param_name=.*|$param_name=$new_value|" "$CONFIG_FILE"
                ;;
            *)
                echo -e "${YELLOW}请输入新的值：${NC}"
                read -r new_value
                if [[ ! "$new_value" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}错误：请输入数字！${NC}"
                    return 1
                fi
                sed -i "s/^$param_name=.*/$param_name=$new_value/" "$CONFIG_FILE"
                ;;
        esac
        echo -e "${GREEN}配置已更新！${NC}"
        # 显示更新后的配置状态
        if [ "$param_name" = "dd" ]; then
            if grep -q "^#dd" "$CONFIG_FILE"; then
                echo -e "${YELLOW}下载测速状态：${NC}已禁用"
            else
                echo -e "${YELLOW}下载测速状态：${NC}已启用"
            fi
        else
            local new_line=$(grep "^$param_name=" "$CONFIG_FILE")
            echo -e "${YELLOW}新的配置：${NC}$new_line"
        fi
    else
        echo -e "${RED}无效的选择！${NC}"
        return 1
    fi
}

get_config_params() {
    local params=""
    
    # 读取基本参数
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z $line ]] && continue
        
        # 获取参数名和值
        local name="${line%%=*}"
        local value="${line#*=}"
        
        # 跳过被注释的参数
        [[ $name =~ ^# ]] && continue
        
        # 构建参数
        case "$name" in
            n) params="$params -n $value";;
            t) params="$params -t $value";;
            sl) params="$params -dn $value";;
            tp) params="$params -tp $value";;
            tl) params="$params -tl $value";;
            url) params="$params -url $value";;
            dl) 
                # 只有在下载测速启用时才添加下载速度限制
                if ! grep -q "^#dd" "$CONFIG_FILE"; then
                    params="$params -sl $value"
                fi
                ;;
        esac
    done < "$CONFIG_FILE"
    
    # 检查下载测速状态
    if ! grep -q "^#dd" "$CONFIG_FILE" && ! grep -q "^dd" "$CONFIG_FILE"; then
        # 如果dd参数不存在或被注释，则添加-dd参数禁用下载测速
        params="$params -dd"
    fi
    
    echo "$params"
}

get_output_filename() {
    local ip_type="$1"
    echo "result_${ip_type}.csv"
}

###################
# 测速功能函数     #
###################
run_speed_test() {
    local ip_type="$1"
    local ip_file="$2"
    local params=$(get_config_params)
    local output_file=$(get_output_filename "$ip_type")
    
    echo -e "\n${GREEN}当前测速配置：${NC}"
    echo -e "${YELLOW}测试线程数：${NC}$(grep "^n=" "$CONFIG_FILE" | cut -d'=' -f2)"
    echo -e "${YELLOW}延迟测速次数：${NC}$(grep "^t=" "$CONFIG_FILE" | cut -d'=' -f2)"
    echo -e "${YELLOW}选择的IP数量：${NC}$(grep "^sl=" "$CONFIG_FILE" | cut -d'=' -f2)"
    echo -e "${YELLOW}测速端口：${NC}$(grep "^tp=" "$CONFIG_FILE" | cut -d'=' -f2)"
    echo -e "${YELLOW}延迟上限：${NC}$(grep "^tl=" "$CONFIG_FILE" | cut -d'=' -f2) ms"
    
    # 检查下载测速是否启用
    if ! grep -q "^#dd" "$CONFIG_FILE" && ! grep -q "^dd" "$CONFIG_FILE"; then
        echo -e "${YELLOW}下载测速：${NC}禁用"
    else
        echo -e "${YELLOW}下载测速：${NC}启用"
        echo -e "${YELLOW}下载测试地址：${NC}$(grep "^url=" "$CONFIG_FILE" | cut -d'=' -f2)"
        if grep -q "^dl=" "$CONFIG_FILE"; then
            echo -e "${YELLOW}下载速度下限：${NC}$(grep "^dl=" "$CONFIG_FILE" | cut -d'=' -f2) MB/s"
        fi
    fi
    
    echo -e "\n${GREEN}开始 ${ip_type} 测速，结果将保存至：${output_file}${NC}"
    # 修改 awk 命令，添加错误处理
    ./CloudflareST -f "$ip_file" -o "${output_file}" $params | awk '
        /\// {
            split($1, nums, "/");
            current = nums[1];
            total = nums[2];
            if (total > 0) {  # 添加除数检查
                percent = (current/total) * 100;
                printf("\r%d / %d [进度：%.1f%%] %s", current, total, percent, $0);
                fflush();
            }
        }
        !/\// {print}
    '

    # 测速完成后处理结果文件
    if [ -f "${output_file}" ]; then
        echo -e "\n${GREEN}测速完成，正在获取IP地理位置信息...${NC}"
        # 创建临时文件
        local temp_file="${output_file}.tmp"
        # 添加国家列标题
        echo "IP,已发送,已接收,丢包率,平均延迟,下载速度,国家" > "$temp_file"
        
        # 读取CSV文件（跳过标题行）并添加国家信息
        tail -n +2 "${output_file}" | while IFS=, read -r ip rest; do
            local country=$(get_ip_location "$ip")
            echo "${ip},${rest},${country}" >> "$temp_file"
        done
        
        # 替换原文件
        mv "$temp_file" "${output_file}"
        echo -e "${GREEN}已添加国家信息到结果文件：${output_file}${NC}"
        
        # 将结果追加到统一的txt文件中
        convert_csv_to_txt "${output_file}"
    fi
}

###################
# 初始化函数      #
###################
init_environment() {
    # 检查必需的命令
    check_command wget
    check_command chmod

    # 创建和检查目录
    echo -e "${YELLOW}正在检查目录...${NC}"
    # 先创建 ips 目录
    if [ ! -d "$IPS_DIR" ]; then
        mkdir -p "$IPS_DIR" || error_exit "无法创建 ips 目录"
    fi
    
    # 再创建 CloudflareST 目录
    if [ -e "$INSTALL_DIR" ]; then
        if [ -f "$INSTALL_DIR" ]; then
            rm -f "$INSTALL_DIR" || error_exit "无法删除同名文件"
            mkdir -p "$INSTALL_DIR" || error_exit "无法创建目录"
        fi
    else
        mkdir -p "$INSTALL_DIR" || error_exit "无法创建目录"
    fi
    
    cd "${INSTALL_DIR}" || error_exit "无法进入目录"
    mkdir -p "$(dirname "${CONFIG_FILE}")" || error_exit "无法创建配置目录"

    # 如果文件不存在，才下载
    if [ ! -f "CloudflareST" ] || [ ! -f "ip.txt" ] || [ ! -f "ipv6.txt" ]; then
        download_resources
    fi
}

download_resources() {
    # 获取系统架构
    local ARCH=$(uname -m)
    local FILE
    
    # 选择对应的文件
    case ${ARCH} in
        x86_64)  FILE="CloudflareST_amd64" ;;
        i386|i686) FILE="CloudflareST_386" ;;
        aarch64) FILE="CloudflareST_arm64" ;;
        armv7*) FILE="CloudflareST_armv7" ;;
        armv6*) FILE="CloudflareST_armv6" ;;
        armv5*) FILE="CloudflareST_armv5" ;;
        mips64) FILE="CloudflareST_mips64" ;;
        mips64le) FILE="CloudflareST_mips64le" ;;
        mips) FILE="CloudflareST_mips" ;;
        mipsle) FILE="CloudflareST_mipsle" ;;
        *) error_exit "不支持的系统架构: ${ARCH}" ;;
    esac

    echo -e "${GREEN}检测到系统架构: ${ARCH}${NC}"

    # 下载文件
    download_file "${BASE_URL}/${FILE}" "CloudflareST" "主程序"
    download_file "${IP_BASE_URL}/dns_results_ipv4.txt" "ip.txt" "IPv4列表"
    download_file "${IP_BASE_URL}/dns_results_ipv6.txt" "ipv6.txt" "IPv6列表"

    # 设置权限
    chmod +x CloudflareST || error_exit "无法添加执行权限"

    # 验证文件
    for file in "CloudflareST" "ip.txt" "ipv6.txt"; do
        [ ! -s "$file" ] && error_exit "${file} 不存在或为空"
    done
}

update_resources() {
    if check_update; then
        download_resources
        echo -e "${GREEN}更新完成！${NC}"
    else
        echo -e "${YELLOW}取消更新${NC}"
    fi
}

###################
# 菜单函数        #
###################
show_menu() {
    load_config
    
    while true
    do
        echo -e "\n${GREEN}=== CloudflareST 测速工具菜单 ===${NC}"
        echo -e "1. ${YELLOW}查看当前配置${NC}"
        echo -e "2. ${YELLOW}修改配置参数${NC}"
        echo -e "3. ${YELLOW}开始 IPv4 测速${NC}"
        echo -e "4. ${YELLOW}开始 IPv6 测速${NC}"
        echo -e "5. ${YELLOW}双栈同时测速${NC}"
        echo -e "6. ${YELLOW}自定义参数测速${NC}"
        echo -e "7. ${YELLOW}更新程序和 IP 列表${NC}"
        echo -e "8. ${YELLOW}查看帮助信息${NC}"
        echo -e "0. ${YELLOW}退出程序${NC}"
        
        echo -e "\n请选择操作 [0-8]: "
        read -r choice

        case $choice in
            1) show_config ;;
            2) edit_config ;;
            3) run_speed_test "ipv4" "ip.txt" ;;
            4) run_speed_test "ipv6" "ipv6.txt" ;;
            5)
                echo -e "${GREEN}===== 开始双栈测速 =====${NC}"
                echo -e "${YELLOW}第一步：IPv4 测速${NC}"
                run_speed_test "ipv4" "ip.txt"
                echo -e "\n${YELLOW}第二步：IPv6 测速${NC}"
                run_speed_test "ipv6" "ipv6.txt"
                echo -e "${GREEN}===== 双栈测速完成 =====${NC}"
                ;;
            6)
                echo -e "${YELLOW}请输入自定义参数（如: -n 500 -t 4 -dt 5）：${NC}"
                read -r custom_params
                output_file=$(get_output_filename "custom")
                [ "$custom_params" != *"-o "* ] && custom_params="$custom_params -o ${output_file}"
                ./CloudflareST $custom_params
                ;;
            7) update_resources ;;
            8) ./CloudflareST -h ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *) echo -e "${RED}无效的选择，请重试${NC}" ;;
        esac
        
        echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
        read -r
    done
}

###################
# 主函数          #
###################
main() {
    # 如果有命令行参数，则处理参数
    if [ $# -gt 0 ]; then
        handle_args "$@"
        return
    fi

    # 无参数时显示菜单
    init_environment
    echo -e "\n${GREEN}程序已就绪！正在启动菜单...${NC}"
    show_menu
}

# 添加新的函数，用于查询 IP 地理位置
get_ip_location() {
    local ip="$1"
    local cache_file="${INSTALL_DIR}/.ip_cache"
    local cache_duration=86400  # 24小时缓存
    
    # 检查缓存
    if [ -f "$cache_file" ]; then
        # 使用 awk 来安全地处理数值计算
        local cached_result=$(awk -F',' -v ip="$ip" -v now="$(date +%s)" -v duration="$cache_duration" '
            $1 == ip {
                if ($3 ~ /^[0-9]+$/ && now - $3 < duration) {
                    print $2
                    exit 0
                }
            }
        ' "$cache_file")
        
        if [ -n "$cached_result" ]; then
            echo "$cached_result"
            return 0
        fi
    fi
    
    # 如果缓存不存在或已过期，查询 API
    local result=$(curl -s --connect-timeout 5 "${IP_API_URL}/${ip}?fields=countryCode")
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        local country=$(echo "$result" | grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$country" ]; then
            local timestamp=$(date +%s)
            echo "${ip},${country},${timestamp}" >> "$cache_file"
            echo "$country"
        else
            echo "UN"
        fi
    else
        echo "UN"  # 查询失败时返回未知
    fi
}

convert_csv_to_txt() {
    local csv_file="$1"
    local txt_file="${IPS_DIR}/result.txt"
    
    # 从配置文件获取输出端口
    local output_ports=($(grep "^output_port=" "$CONFIG_FILE" | cut -d'=' -f2 | tr ',' ' '))
    [ ${#output_ports[@]} -eq 0 ] && output_ports=("2096")  # 如果未设置，使用默认值
    
    echo -e "${GREEN}正在生成结果文件...${NC}"
    
    # 如果是第一次运行（IPv4），创建新文件；如果是第二次运行（IPv6），追加到现有文件
    if [[ $csv_file == *"ipv4"* ]] && [ -f "$txt_file" ]; then
        echo -e "${YELLOW}检测到 IPv4 测速，创建新的结果文件...${NC}"
        > "$txt_file"  # 如果是 IPv4 且文件存在，则清空文件
    else
        echo -e "${YELLOW}检测到 IPv6 测速，将追加到现有结果文件...${NC}"
    fi
    
    # 对于每个IP，生成所有端口的条目
    tail -n +2 "$csv_file" | while IFS=, read -r ip _ _ _ _ _ country; do
        for port in "${output_ports[@]}"; do
            # 对IPv6地址添加方括号，使用当前端口
            if [[ $ip =~ ":" ]]; then
                echo "[${ip}]:${port}#${country}" >> "$txt_file"
            else
                # IPv4地址不需要方括号
                echo "${ip}:${port}#${country}" >> "$txt_file"
            fi
        done
    done
    
    echo -e "${GREEN}已生成结果文件：${txt_file}${NC}"
    echo -e "${YELLOW}当前文件包含记录数：$(wc -l < "$txt_file") 行${NC}"
}

# 修改参数处理函数
handle_args() {
    case "$1" in
        "--ipv4")
            init_environment
            run_speed_test "ipv4" "ip.txt"
            ;;
        "--ipv6")
            init_environment
            run_speed_test "ipv6" "ipv6.txt"
            ;;
        "--both")
            init_environment
            echo -e "${GREEN}===== 开始双栈测速 =====${NC}"
            echo -e "${YELLOW}第一步：IPv4 测速${NC}"
            run_speed_test "ipv4" "ip.txt"
            echo -e "\n${YELLOW}第二步：IPv6 测速${NC}"
            run_speed_test "ipv6" "ipv6.txt"
            echo -e "${GREEN}===== 双栈测速完成 =====${NC}"
            ;;
        "--update")
            init_environment
            update_resources
            ;;
        "--config")
            init_environment
            show_config
            ;;
        "--help")
            echo -e "${GREEN}CloudflareST 测速工具使用说明：${NC}"
            echo -e "${YELLOW}可用参数：${NC}"
            echo "  --ipv4    仅测试 IPv4"
            echo "  --ipv6    仅测试 IPv6"
            echo "  --both    同时测试 IPv4 和 IPv6"
            echo "  --update  更新程序和 IP 列表"
            echo "  --config  显示当前配置"
            echo "  --help    显示此帮助信息"
            echo "  无参数    启动交互式菜单"
            ;;
        *)
            echo -e "${RED}错误：未知参数 $1${NC}"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
}

# 启动脚本
main "$@"

