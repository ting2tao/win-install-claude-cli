$ErrorActionPreference = 'Stop'

# Load functions without starting the interactive Windows installer.
$installer = Join-Path $PSScriptRoot '../install-claude.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors -join "`n") }
$functions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $false)
foreach ($definition in $functions) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

function Assert-Equal($Expected, $Actual, $Scenario) {
    if ($Expected -cne $Actual) {
        throw "${Scenario}: expected '$Expected', got '$Actual'"
    }
}

foreach ($name in 'Ensure-ClaudeCode', 'Ensure-ClaudeDesktop', 'Ensure-CcSwitch') {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing installer behavior: $name"
    }
}

function Write-OK {}
function Write-Info {}
function Write-Warn {}
function Write-Fail {}
function Refresh-Path {}
function Ensure-NpmGlobalPath {}

function claude {}
function winget.exe {}
function Get-AppxPackage {
    if ($script:appxInstalled) {
        [pscustomobject]@{ PackageFamilyName = 'Claude_pzs8sxrjxfjjc' }
    }
}
function Get-ItemProperty { $script:registeredApp }

function Get-CommandText {
    param($Command, $Arguments)
    if ($Command -eq 'claude') {
        if ($script:cliInstalled) { return @{ ExitCode = 0; Text = '2.1.121 (Claude Code)' } }
        return @{ ExitCode = 1; Text = '' }
    }

    $script:wingetCalls += $Arguments[0]
    Assert-Equal 'Anthropic.Claude' $Arguments[2] 'Exact desktop package ID'
    if ($Arguments[0] -eq 'list') {
        return @{ ExitCode = $script:wingetListCode; Text = '' }
    }
    Assert-Equal $true ($Arguments -contains '--no-upgrade') 'Do not upgrade if app appears after detection'
    return @{ ExitCode = $script:wingetInstallCode; Text = '' }
}

function Install-NpmPackage {
    $script:npmInstallCount++
    $script:cliInstalled = $true
    return $true
}

function Find-CcSwitchExecutable {}
function Test-FileSignature { return $true }
function Start-Process {
    $script:msiInstallCount++
    return @{ ExitCode = 0 }
}

$script:npmInstallCount = 0
$script:cliInstalled = $true
Assert-Equal $true (Ensure-ClaudeCode) 'Existing Claude Code'
Assert-Equal 0 $script:npmInstallCount 'Skip npm install'

$script:cliInstalled = $false
Assert-Equal $true (Ensure-ClaudeCode) 'Missing Claude Code'
Assert-Equal 1 $script:npmInstallCount 'Install Claude Code once'

$script:wingetCalls = @()
$script:appxInstalled = $true
Assert-Equal $true (Ensure-ClaudeDesktop) 'Existing Claude Desktop MSIX'
Assert-Equal '' ($script:wingetCalls -join ',') 'Skip WinGet for existing MSIX'

$script:appxInstalled = $false
$script:registeredApp = [pscustomobject]@{ DisplayName = 'Claude'; Publisher = 'Anthropic, PBC' }
Assert-Equal $true (Ensure-ClaudeDesktop) 'Existing Claude Desktop via legacy installer'
Assert-Equal '' ($script:wingetCalls -join ',') 'Skip WinGet for existing legacy install'

$script:registeredApp = $null
$script:wingetListCode = 0
Assert-Equal $true (Ensure-ClaudeDesktop) 'Existing Claude Desktop via WinGet'
Assert-Equal 'list' ($script:wingetCalls -join ',') 'Skip desktop install'

$script:wingetCalls = @()
$script:wingetListCode = -1978335212
$script:wingetInstallCode = 0
Assert-Equal $true (Ensure-ClaudeDesktop) 'Missing Claude Desktop'
Assert-Equal 'list,install' ($script:wingetCalls -join ',') 'Install missing desktop app once'

$script:wingetCalls = @()
$script:wingetInstallCode = 0x8A150061
Assert-Equal $true (Ensure-ClaudeDesktop) 'Desktop installed between check and installation'
Assert-Equal 'list,install' ($script:wingetCalls -join ',') 'WinGet skips an app installed concurrently'

$script:wingetCalls = @()
$script:wingetInstallCode = -1978335195
Assert-Equal $false (Ensure-ClaudeDesktop) 'Desktop installer failed'
Assert-Equal 'list,install' ($script:wingetCalls -join ',') 'Report failed desktop install'

$script:wingetCalls = @()
$script:wingetListCode = 1
Assert-Equal $false (Ensure-ClaudeDesktop) 'WinGet detection failed'
Assert-Equal 'list' ($script:wingetCalls -join ',') 'Do not install when detection fails'

$CcSwitchVersion = 'v4.0.9'
$CcSwitchMsiFile = 'CC-Switch-v4.0.9-Windows.msi'
$repoDir = Split-Path $PSScriptRoot
$script:msiInstallCount = 0
$script:registeredApp = [pscustomobject]@{ DisplayName = 'CC Switch'; DisplayVersion = '4.1.0' }
Assert-Equal $true (Ensure-CcSwitch $repoDir) 'Existing CC-Switch'
Assert-Equal 0 $script:msiInstallCount 'Do not reinstall or downgrade CC-Switch'

$script:registeredApp = $null
Assert-Equal $true (Ensure-CcSwitch $repoDir) 'Missing CC-Switch'
Assert-Equal 1 $script:msiInstallCount 'Install CC-Switch once'

Write-Host 'Installer behavior tests passed'
