# ============================================================
#  Claude Code CLI + ccswitch 一键安装脚本
#  适用：Windows 10/11 大陆网络环境 · PowerShell 5.1+
#  功能：自动安装 Node.js LTS、配置 npm 镜像、安装 Claude Code CLI
#  使用方法：
#    1. 右键 PowerShell -> 以管理员身份运行
#    2. Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
#    3. .\install-claude.ps1
# ============================================================

# ── [0] 编码 & 错误处理 ──────────────────────────────────
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

# Windows PowerShell 5.1 在老系统上可能默认不用 TLS 1.2，访问 HTTPS 镜像会失败。
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$NpmRegistry      = "https://registry.npmmirror.com"
$NodeMirror       = "https://npmmirror.com/mirrors/node"
$CcSwitchVersion  = "v3.14.1"
$CcSwitchMsiFile  = "CC-Switch-$CcSwitchVersion-Windows.msi"
$CcSwitchMsiUrl   = "https://github.com/farion1231/cc-switch/releases/download/$CcSwitchVersion/$CcSwitchMsiFile"

# ── 工具函数 ─────────────────────────────────────────────
function Write-Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg)     Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Fail { param($msg)     Write-Host "    ERR $msg" -ForegroundColor Red }
function Write-Warn { param($msg)     Write-Host "    WRN $msg" -ForegroundColor Yellow }
function Write-Info { param($msg)     Write-Host "    ... $msg" -ForegroundColor DarkGray }

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal]`
        [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) { $paths += $machinePath }
    if (-not [string]::IsNullOrWhiteSpace($userPath)) { $paths += $userPath }
    $env:Path = ($paths -join ";")
}

function Split-PathList {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }
    return $PathValue.Split(";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().TrimEnd("\") }
}

function Test-PathContains {
    param([string]$PathValue, [string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
    $normalizedTarget = $Target.Trim().TrimEnd("\")
    foreach ($item in (Split-PathList $PathValue)) {
        if ([string]::Equals($item, $normalizedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Add-UserPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) { return }

    if (-not (Test-PathContains $env:Path $Directory)) {
        if ([string]::IsNullOrWhiteSpace($env:Path)) {
            $env:Path = $Directory
        } else {
            $env:Path = "$env:Path;$Directory"
        }
        Write-OK "已加入当前会话 PATH：$Directory"
    } else {
        Write-OK "当前会话 PATH 已包含：$Directory"
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-PathContains $userPath $Directory)) {
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            [Environment]::SetEnvironmentVariable("Path", $Directory, "User")
        } else {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$Directory", "User")
        }
        Write-OK "已永久写入用户 PATH：$Directory"
    } else {
        Write-OK "用户 PATH 已包含：$Directory"
    }
}

function Get-CommandText {
    param([string]$Command, [string[]]$Arguments)
    $output = & $Command @Arguments 2>&1
    return @{
        ExitCode = $LASTEXITCODE
        Text     = ($output | Out-String).Trim()
    }
}

function Test-FileSignature {
    param([string]$FilePath, [string]$Label)
    Write-Info "验证 $Label 数字签名..."
    $sig = Get-AuthenticodeSignature $FilePath
    switch ($sig.Status) {
        "Valid" {
            $signer = $sig.SignerCertificate.Subject
            Write-OK "$Label 签名有效：$signer"
            return $true
        }
        "NotSigned" {
            Write-Warn "$Label 未签名（开源软件常见）"
            $confirm = Read-Host "    是否继续安装未签名文件？(Y/N)"
            return ($confirm -in @("Y", "y", "yes", "是"))
        }
        default {
            Write-Fail "$Label 签名验证失败：$($sig.Status)"
            Write-Info "文件可能被篡改，请从官方渠道重新下载"
            return $false
        }
    }
}

function Confirm-Installation {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host "   即将安装以下内容（需要管理员权限）"
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Node.js LTS          来源：npmmirror.com（国内镜像）"
    Write-Host "  [2] Claude Code CLI       来源：registry.npmmirror.com（npm 镜像）"
    Write-Host "  [3] CC-Switch $CcSwitchVersion    来源：本地 MSI 或 GitHub"
    Write-Host ""
    Write-Host "  以上操作将修改系统 PATH 和 npm 全局配置。" -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "是否继续安装？(Y/N)"
    if ($confirm -notin @("Y", "y", "yes", "是")) {
        Write-Info "用户取消，退出安装"
        exit 0
    }
    Write-Host ""
}

function Get-NodeVersionInfo {
    $result = Get-CommandText "node" @("--version")
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Text)) {
        return $null
    }

    $version = $result.Text.Trim().TrimStart("v")
    $parts = $version.Split(".")
    if ($parts.Count -lt 1) { return $null }

    try {
        $major = [int]$parts[0]
    } catch {
        return $null
    }

    return @{
        Raw     = $result.Text.Trim()
        Version = $version
        Major   = $major
    }
}

function Get-WindowsNodeArch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "ARM64" { return "arm64" }
        "AMD64" { return "x64" }
        default {
            if ([Environment]::Is64BitOperatingSystem) { return "x64" }
            Write-Fail "Node.js 官方 Windows MSI 不再支持当前架构：$env:PROCESSOR_ARCHITECTURE"
            exit 1
        }
    }
}

function Get-LatestNodeLts {
    Write-Info "读取 Node.js LTS 版本列表：$NodeMirror/index.json"
    try {
        $releases = Invoke-RestMethod -Uri "$NodeMirror/index.json" -UseBasicParsing -TimeoutSec 60
    } catch {
        Write-Fail "无法读取 Node.js 镜像版本列表：$_"
        Write-Info "请检查网络，或手动下载：https://npmmirror.com/mirrors/node/"
        exit 1
    }

    $lts = $releases | Where-Object { $_.lts -ne $false } | Select-Object -First 1
    if ($null -eq $lts -or [string]::IsNullOrWhiteSpace($lts.version)) {
        Write-Fail "未能从 npmmirror 版本列表中找到 LTS 版本"
        exit 1
    }

    return $lts.version
}

function Install-NodeLts {
    param([string]$Version)

    $arch = Get-WindowsNodeArch
    $fileName = "node-$Version-$arch.msi"
    $url = "$NodeMirror/$Version/$fileName"
    $installer = Join-Path $env:TEMP $fileName

    Write-Info "下载 Node.js $Version ($arch)：$url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Fail "Node.js 安装包下载失败：$_"
        Write-Info "可手动下载：$url"
        exit 1
    }

    if (-not (Test-Path $installer)) {
        Write-Fail "下载后未找到安装包：$installer"
        exit 1
    }

    # SHA256 哈希校验
    Write-Info "校验 Node.js 下载文件完整性..."
    try {
        $shasums = Invoke-WebRequest -Uri "$NodeMirror/$Version/SHASUMS256.txt" -UseBasicParsing -TimeoutSec 30
        $expectedHash = ($shasums.Content -split "`n" | Where-Object { $_ -match $fileName } | ForEach-Object { ($_ -split "\s+")[0] }).Trim()
        $actualHash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLower()
        if ($expectedHash -and $actualHash -eq $expectedHash.ToLower()) {
            Write-OK "SHA256 校验通过"
        } else {
            Write-Fail "SHA256 校验失败！文件可能被篡改"
            Write-Info "期望：$expectedHash"
            Write-Info "实际：$actualHash"
            exit 1
        }
    } catch {
        Write-Warn "SHA256 校验跳过（无法获取校验文件）：$_"
    }

    if (-not (Test-FileSignature $installer "Node.js MSI")) {
        Write-Info "如需跳过验证，可手动运行：$installer"
        exit 1
    }

    Write-Info "静默安装 Node.js，请稍等..."
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", "`"$installer`"", "/qn", "/norestart") -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Fail "Node.js MSI 安装失败，退出码：$($process.ExitCode)"
        Write-Info "可手动运行安装包：$installer"
        exit 1
    }

    Write-OK "Node.js MSI 安装完成"
}

function Ensure-Node {
    $node = Get-NodeVersionInfo
    if ($null -ne $node -and $node.Major -ge 18) {
        Write-OK "已检测到 Node.js $($node.Raw)"
        return
    }

    if ($null -eq $node) {
        Write-Warn "未检测到 Node.js，将自动安装最新 LTS"
    } else {
        Write-Warn "Node.js 版本过低（当前 $($node.Raw)），将自动升级到最新 LTS"
    }

    $version = Get-LatestNodeLts
    Install-NodeLts $version
    Refresh-Path

    $nodeAfter = Get-NodeVersionInfo
    if ($null -eq $nodeAfter -or $nodeAfter.Major -lt 18) {
        Write-Fail "安装后当前 PowerShell 仍无法识别 Node.js 18+"
        Write-Info "请关闭并重新打开管理员 PowerShell 后，再运行：node -v"
        exit 1
    }

    Write-OK "Node.js 已刷新：$($nodeAfter.Raw)"
}

function Ensure-NpmGlobalPath {
    $prefix = (npm prefix -g 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($prefix)) {
        Write-Fail "无法获取 npm 全局目录：$prefix"
        exit 1
    }

    Write-Info "npm 全局命令目录：$prefix"
    Add-UserPath $prefix
}

function Install-NpmPackage {
    param(
        [string]$Package,
        [string]$Label,
        [string[]]$ExtraArgs = @()
    )

    $extraStr = if ($ExtraArgs.Count -gt 0) { $ExtraArgs -join " " } else { "" }
    $npmCmd = "npm install -g $extraStr $Package --registry $NpmRegistry"
    $tmpCmdFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "claude_install_$([System.IO.Path]::GetRandomFileName()).cmd")

    for ($i = 1; $i -le 2; $i++) {
        Write-Info "安装 $Label（第 $i 次尝试）..."
        Write-Info "命令：$npmCmd"
        Set-Content -Path $tmpCmdFile -Value "@echo off`r`n$npmCmd" -Encoding ASCII
        $output = & cmd /c $tmpCmdFile 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-OK "$Label 安装命令执行成功"
            Remove-Item -Path $tmpCmdFile -Force -ErrorAction SilentlyContinue
            return $true
        }

        Write-Warn "$Label 安装失败，npm 退出码：$exitCode"
        $lines = @($output | ForEach-Object { $_.ToString() })
        $tail = $lines | Select-Object -Last 20
        if ($tail.Count -gt 0) {
            Write-Host "    --- npm 输出最后 20 行 ---" -ForegroundColor DarkYellow
            foreach ($line in $tail) { Write-Host "    $line" -ForegroundColor DarkYellow }
            Write-Host "    ------------------------" -ForegroundColor DarkYellow
        }

        if ($i -lt 2) {
            Write-Warn "5 秒后重试..."
            Start-Sleep 5
        }
    }

    Remove-Item -Path $tmpCmdFile -Force -ErrorAction SilentlyContinue
    return $false
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Claude Code CLI + CC-Switch 安装脚本"
Write-Host "================================================" -ForegroundColor Cyan

Confirm-Installation

# ── STEP 1: PowerShell 版本检查 ──────────────────────────
Write-Step "1/7" "检查 PowerShell 版本..."
$psVer = $PSVersionTable.PSVersion.Major
if ($psVer -lt 5) {
    Write-Fail "PowerShell 版本过低（当前 $psVer.x），需要 5.1 或以上"
    Write-Info "请升级 PowerShell：https://aka.ms/PSWindows"
    exit 1
}
Write-OK "PowerShell $($PSVersionTable.PSVersion)"

# ── STEP 2: 管理员权限检查 ───────────────────────────────
Write-Step "2/7" "检查运行权限..."
if (Test-IsAdmin) {
    Write-OK "当前以管理员身份运行"
} else {
    Write-Warn "未以管理员身份运行，Node.js 静默安装可能失败"
    Write-Info "建议：右键 PowerShell -> 以管理员身份运行，再执行本脚本"
    Write-Info "继续尝试安装（5 秒后）..."
    Start-Sleep 5
}

# ── STEP 3: 自动安装 / 检查 Node.js ──────────────────────
Write-Step "3/7" "检查并安装 Node.js LTS..."
Ensure-Node
Refresh-Path

$nodeText = (node -v 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nodeText)) {
    Write-Fail "刷新后仍无法执行 node -v，请重启 PowerShell 后重试"
    exit 1
}
Write-OK "node -v => $nodeText"

$npmText = (npm -v 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmText)) {
    Write-Fail "无法执行 npm -v，Node.js 安装可能不完整"
    exit 1
}
Write-OK "npm -v  => $npmText"

# ── STEP 4: 配置 npm 镜像源 ──────────────────────────────
Write-Step "4/7" "配置 npm npmmirror 镜像源..."
npm config set registry $NpmRegistry
npm config set fetch-retries 3
npm config set fetch-timeout 120000
npm config set fetch-retry-mintimeout 20000
npm config set fetch-retry-maxtimeout 120000

$reg = (npm config get registry 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($reg)) {
    Write-Fail "无法读取 npm registry 配置"
    exit 1
}
Write-OK "镜像源：$reg"

$omit = (npm config get omit 2>&1 | Out-String).Trim()
if ($omit -match "optional") {
    Write-Warn "检测到 npm omit 包含 optional，本脚本安装 Claude Code 时会强制 --include=optional"
}

Ensure-NpmGlobalPath

# ── STEP 5: 安装 Claude Code CLI ─────────────────────────
Write-Step "5/7" "安装 Claude Code CLI..."
$ok = Install-NpmPackage "@anthropic-ai/claude-code" "Claude Code" @("--include=optional")
if (-not $ok) {
    Write-Fail "Claude Code 安装失败，请检查网络、npm 权限或 npmmirror 同步状态"
    Write-Info "可手动执行：npm install -g --include=optional @anthropic-ai/claude-code --registry $NpmRegistry"
    exit 1
}

Refresh-Path
Ensure-NpmGlobalPath
$claudeVer = (claude --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($claudeVer)) {
    Write-Fail "Claude Code 已安装，但当前 PowerShell 未识别 claude 命令"
    Write-Info "请重启 PowerShell 后运行：claude --version"
    exit 1
}
Write-OK "Claude Code 安装成功：$claudeVer"

# ── STEP 6: 安装 CC-Switch 桌面版 + 快捷方式 ─────────────
Write-Step "6/7" "安装 CC-Switch $CcSwitchVersion..."

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path } else { $PWD.Path }
$localMsi  = Join-Path $scriptDir $CcSwitchMsiFile
Write-Info "查找本地 MSI：$localMsi"
if (Test-Path $localMsi) {
    $msiFile = $localMsi
    Write-OK "使用本地 MSI：$msiFile"
} else {
    $msiFile = Join-Path $env:TEMP $CcSwitchMsiFile
    Write-Info "本地未找到，开始下载：$CcSwitchMsiUrl"
    try {
        Invoke-WebRequest -Uri $CcSwitchMsiUrl -OutFile $msiFile -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Fail "CC-Switch 下载失败：$_"
        Write-Info "可手动下载：$CcSwitchMsiUrl"
        $msiFile = $null
    }
}

if ($msiFile -and (Test-Path $msiFile)) {
    if (-not (Test-FileSignature $msiFile "CC-Switch MSI")) {
        Write-Info "如需跳过验证，可手动运行：$msiFile"
        $msiFile = $null
    }
}

if ($msiFile -and (Test-Path $msiFile)) {
    Write-Info "静默安装 CC-Switch，请稍等..."
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", "`"$msiFile`"", "/qn", "/norestart") -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Warn "CC-Switch MSI 安装失败，退出码：$($proc.ExitCode)"
        Write-Info "可手动运行安装包：$msiFile"
    } else {
        Write-OK "CC-Switch 安装完成"
        Refresh-Path

        # 查找 CC-Switch.exe
        $ccExe = $null
        $searchDirs = @(
            "$env:ProgramFiles\CC-Switch",
            "${env:ProgramFiles(x86)}\CC-Switch",
            "$env:LOCALAPPDATA\Programs\CC-Switch",
            "$env:LOCALAPPDATA\CC-Switch"
        )
        foreach ($dir in $searchDirs) {
            $candidate = Join-Path $dir "CC-Switch.exe"
            if (Test-Path $candidate) { $ccExe = $candidate; break }
        }
        if (-not $ccExe) {
            $found = Get-ChildItem -Path "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA\Programs" -Filter "CC-Switch.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $ccExe = $found.FullName }
        }

        if ($ccExe) {
            $desktop = [Environment]::GetFolderPath("Desktop")
            $lnkPath = "$desktop\CC-Switch.lnk"
            if (Test-Path $lnkPath) {
                Write-OK "桌面快捷方式已存在：$lnkPath"
            } else {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($lnkPath)
                $shortcut.TargetPath = $ccExe
                $shortcut.WorkingDirectory = Split-Path $ccExe
                $shortcut.IconLocation = "$ccExe,0"
                $shortcut.Save()
                Write-OK "桌面快捷方式已创建：$lnkPath"
            }
        } else {
            Write-Warn "未找到 CC-Switch.exe，桌面快捷方式未创建"
            Write-Info "请手动查找安装目录并创建快捷方式"
        }
    }
} else {
    Write-Warn "CC-Switch 未安装，不影响 Claude Code 使用"
}

# ── STEP 7: 完成提示 ────────────────────────────────────
Write-Step "7/7" "安装结果与下一步..."
Write-OK "node -v：$((node -v 2>&1 | Out-String).Trim())"
Write-OK "npm -v ：$((npm -v 2>&1 | Out-String).Trim())"
Write-OK "claude ：$((claude --version 2>&1 | Out-String).Trim())"

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   CLI 已安装，下一步：配置 API"
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  当前会话临时配置：" -ForegroundColor Yellow
Write-Host '    $env:ANTHROPIC_API_KEY  = "your-api-key"'
Write-Host '    $env:ANTHROPIC_BASE_URL = "https://中转地址"'
Write-Host ""
Write-Host "  永久写入用户环境变量：" -ForegroundColor Yellow
Write-Host '    [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "your-api-key", "User")'
Write-Host '    [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://中转地址", "User")'
Write-Host ""
Write-Host "  注意：ANTHROPIC_BASE_URL 是否带 /v1 取决于你的中转服务商。" -ForegroundColor Yellow
Write-Host ""
Write-Host "  用 CC-Switch 桌面版管理多个供应商：" -ForegroundColor Yellow
Write-Host "    桌面双击 CC-Switch 快捷方式即可打开"
Write-Host ""
Write-Host "  启动 Claude Code：" -ForegroundColor Yellow
Write-Host "    Win+R -> 输入 cmd -> 回车 -> 输入 claude"
Write-Host ""
Write-Host "  测试连接：" -ForegroundColor Yellow
Write-Host '    claude -p "你好"'
Write-Host ""
