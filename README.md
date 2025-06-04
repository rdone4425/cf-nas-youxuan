# Cloudflare IP 优选工具

这是一个用于优选 Cloudflare CDN 节点 IP 的命令行工具。支持 IPv4 和 IPv6，适用于各类 Linux 系统，特别优化了 NAS 设备的使用体验。

## 功能特点

- 支持 IPv4/IPv6 优选
- 自动化测速与筛选
- 多源下载自动切换
- 结果自动上传到 GitHub
- 兼容 NAS 系统
- 友好的命令行界面

## 使用方法

### 安装

#### 方法一：快速安装（推荐）

# 一键安装运行
```bash
bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/main.sh)
```

此方法会直接下载并执行脚本，适合快速部署。

#### 方法二：手动安装

```bash
# 下载主脚本
curl -o main.sh https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/main.sh
chmod +x main.sh

# 运行脚本
./main.sh
```

此方法会将脚本下载到本地后运行，适合需要检查脚本内容或重复使用的场景。

### 命令行参数

```bash
./main.sh [选项]

选项:
  --ipv4    仅优选 IPv4
  --ipv6    仅优选 IPv6
  --all     优选 IPv4 和 IPv6
  --update  更新脚本
```

### 交互式菜单选项

1. CFNAS IPv4 优选
2. CFNAS IPv6 优选
3. 全部优选 (CFNAS + CF)
4. CF IPv4 优选
5. CF IPv6 优选
6. 更新脚本
7. 进入 CFNAS 菜单
8. 上传结果到 GitHub
9. 配置 GitHub
0. 退出

## 配置说明

### GitHub 配置

使用 GitHub 功能需要配置以下信息：

1. 访问令牌 (Personal Access Token)
   - 访问 GitHub Settings -> Developer settings -> Personal access tokens
   - 生成新的 token，需要赋予 `repo` 权限
   
2. 仓库信息
   - 仓库名称格式：`用户名/仓库名`
   - 分支名称（默认为 main）

### 文件结构

```
cf/
├── main.sh     # 主程序
├── cfnas.sh    # NAS 优选脚本
├── cf.sh       # 通用优选脚本
└── ips/        # IP 结果目录
    └── merged_all.txt  # 合并后的优选结果
```

## 工作原理

1. 下载优选脚本
   - 优先从 GitHub 直接下载
   - 如果失败则使用代理下载
   
2. 执行优选过程
   - 运行 CFNAS 优选（支持 IPv4/IPv6）
   - 运行通用 CF 优选
   - 合并优选结果
   
3. 结果处理
   - 自动去重和排序
   - 可选上传到 GitHub 仓库

## 注意事项

1. 确保系统已安装以下依赖：
   - curl
   - jq
   - dos2unix (可选)
   
2. 如果遇到下载问题，脚本会自动切换到备用下载源
3. GitHub 上传功能需要正确配置访问令牌
4. 建议定期更新脚本以获取最新功能

## 常见问题

1. 下载失败
   - 检查网络连接
   - 尝试使用代理
   
2. GitHub 上传失败
   - 验证访问令牌
   - 确认仓库名称格式
   - 检查仓库权限

## 更新日志

### v1.0.0
- 初始版本发布
- 支持基本的 IP 优选功能
- 添加 GitHub 上传支持

### v1.1.0
- 优化下载逻辑，增加备用源
- 改进错误处理机制
- 添加详细的日志输出

### 定时任务示例

如果您想要定期自动运行优选，可以设置 crontab：

```bash
# 编辑 crontab
crontab -e

# 添加以下内容（每天凌晨3点运行）
0 3 * * * bash <(curl -Ls https://raw.githubusercontent.com/rdone4425/cf-nas-youxuan/main/main.sh) --all

# 或者如果您已经下载了脚本（推荐）
0 3 * * * /root/cf/main.sh --all
```

提示：建议将脚本下载到本地后使用第二种方式，这样更加稳定可靠。

## 许可证

MIT License
