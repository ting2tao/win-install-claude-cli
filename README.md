# Claude Code CLI 一键安装脚本

Windows 环境下一键安装 Claude Code CLI + CC-Switch 桌面客户端。

## 包含文件

| 文件 | 说明 |
|------|------|
| `安装Claude.bat` | 双击运行的启动脚本 |
| `install-claude.ps1` | PowerShell 安装主脚本 |
| `CC-Switch-v3.14.1-Windows.msi` | CC-Switch 桌面客户端安装包 |

## 安装步骤

1. 将 3 个文件放在同一个文件夹
2. 右键 `安装Claude.bat` -> **以管理员身份运行**
3. 等待安装完成

## 安装内容

脚本自动完成以下 7 个步骤：

| 步骤 | 内容 |
|------|------|
| 1/7 | 检查 PowerShell 版本（需要 5.1+） |
| 2/7 | 检查管理员权限 |
| 3/7 | 自动安装 Node.js LTS（如果没有或版本过低） |
| 4/7 | 配置 npm 镜像源（npmmirror） |
| 5/7 | 安装 Claude Code CLI |
| 6/7 | 安装 CC-Switch 桌面客户端 + 创建桌面快捷方式 |
| 7/7 | 显示安装结果与下一步配置说明 |

## 安全措施

| 措施 | 说明 |
|------|------|
| 安装前确认 | 脚本启动后显示将要安装的内容，用户确认后才继续 |
| MSI 数字签名验证 | Node.js 和 CC-Switch 安装前验证 Authenticode 签名 |
| SHA256 哈希校验 | Node.js 下载后与官方 SHASUMS256 比对，防止文件被篡改 |
| npm 完整性校验 | npm 安装时使用 `--integrity` 校验包哈希 |

## 网络要求

- 国内网络可直接使用，无需代理
- Node.js 和 npm 通过 npmmirror 国内镜像下载
- CC-Switch 优先使用本地 MSI，未找到时从 GitHub 下载

## 安装后配置

安装完成后需要配置 API 密钥：

```powershell
# 临时配置（当前会话有效）
$env:ANTHROPIC_API_KEY  = "your-api-key"
$env:ANTHROPIC_BASE_URL = "https://你的中转地址"

# 永久写入用户环境变量
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "your-api-key", "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://你的中转地址", "User")
```

> 注意：`ANTHROPIC_BASE_URL` 是否带 `/v1` 取决于你的中转服务商。

## 启动 Claude Code

安装并配置好 API 后，可以通过以下方式启动：

1. 按 `Win + R` 打开运行窗口
2. 输入 `cmd`，回车打开命令提示符
3. 输入 `claude`，回车进入交互模式

```cmd
claude
```

进入交互模式后可以直接与 Claude 对话，输入问题后回车即可。

其他常用命令：

```cmd
# 单次提问（不进入交互模式）
claude -p "你好"

# 查看版本
claude --version

# 查看帮助
claude --help
```

## 常见问题

### 执行策略报错

如果遇到"在此系统上禁止运行脚本"，在 PowerShell 中执行：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Node.js 安装失败

- 确保以管理员身份运行
- 可手动下载安装：https://npmmirror.com/mirrors/node/

### Claude Code 安装失败

手动执行：

```powershell
npm install -g --include=optional @anthropic-ai/claude-code --registry https://registry.npmmirror.com
```
