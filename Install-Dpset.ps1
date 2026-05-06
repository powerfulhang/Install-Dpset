# =============================================================================
# Install-Dpset.ps1
# One-time installer/upgrader for the 'dpset' command-line tool.
#
# USAGE:
#   Right-click this file -> "Run with PowerShell"
#   OR open PowerShell and run:
#       powershell -ExecutionPolicy Bypass -File .\Install-Dpset.ps1
#
# AFTER INSTALLATION (restart terminal first):
#   dpset status       - Show effective Process/User/Machine configuration
#   dpset on deepseek  - Apply DeepSeek V4 Pro config to User environment
#   dpset on mimo      - Apply Xiaomi MiMo Token Plan (CN) config to User environment
#   dpset test mimo    - Validate a provider without changing User environment
# =============================================================================

$ErrorActionPreference = "Stop"

$INSTALL_DIR = Join-Path $HOME "bin"
$PS1_PATH    = Join-Path $INSTALL_DIR "dpset.ps1"
$BAT_PATH    = Join-Path $INSTALL_DIR "dpset.bat"

Write-Host ""
Write-Host "=== dpset Installer / Upgrader ===" -ForegroundColor Cyan
Write-Host "Install directory: $INSTALL_DIR"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Create install directory
# ---------------------------------------------------------------------------
if (!(Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null
    Write-Host "[1/4] Created directory: $INSTALL_DIR" -ForegroundColor Green
} else {
    Write-Host "[1/4] Directory already exists: $INSTALL_DIR" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# 2. Write dpset.ps1  (the main logic script)
# ---------------------------------------------------------------------------
$dpsetScript = @'
# =============================================================================
# dpset.ps1 - Claude Code provider switcher for DeepSeek and Xiaomi MiMo.
# Installed by Install-Dpset.ps1  |  Runtime state lives in %USERPROFILE%\.dpset.
#
# Usage:
#   dpset status
#   dpset list
#   dpset on [deepseek|mimo]
#   dpset test [deepseek|mimo]
#   dpset off
#   dpset reset
# =============================================================================

param(
    [Parameter(Position = 0)]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [string]$Provider = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$CONFIG_DIR           = Join-Path $HOME ".dpset"
$BACKUP_FILE          = Join-Path $CONFIG_DIR "backup.json"
$ACTIVE_PROVIDER_FILE = Join-Path $CONFIG_DIR "active_provider"
$LAST_SWITCH_FILE     = Join-Path $CONFIG_DIR "last_switch.json"

$PROVIDERS = [ordered]@{
    "deepseek" = [ordered]@{
        "Label"                                = "DeepSeek V4 Pro"
        "BaseUrl"                              = "https://api.deepseek.com/anthropic"
        "ANTHROPIC_MODEL"                      = "deepseek-v4-pro[1m]"
        "ANTHROPIC_DEFAULT_OPUS_MODEL"         = "deepseek-v4-pro[1m]"
        "ANTHROPIC_DEFAULT_SONNET_MODEL"       = "deepseek-v4-pro[1m]"
        "ANTHROPIC_DEFAULT_HAIKU_MODEL"        = "deepseek-v4-flash"
        "CLAUDE_CODE_SUBAGENT_MODEL"           = "deepseek-v4-flash"
        "TestModel"                            = "deepseek-v4-pro"
    }
    "mimo" = [ordered]@{
        "Label"                                = "Xiaomi MiMo Token Plan (CN)"
        "BaseUrl"                              = "https://token-plan-cn.xiaomimimo.com/anthropic"
        "ANTHROPIC_MODEL"                      = "mimo-v2.5-pro[1m]"
        "ANTHROPIC_DEFAULT_OPUS_MODEL"         = "mimo-v2.5-pro[1m]"
        "ANTHROPIC_DEFAULT_SONNET_MODEL"       = "mimo-v2.5-pro[1m]"
        "ANTHROPIC_DEFAULT_HAIKU_MODEL"        = "mimo-v2-flash"
        "CLAUDE_CODE_SUBAGENT_MODEL"           = "mimo-v2-flash"
        "TestModel"                            = "mimo-v2.5-pro"
        "BillingMode"                          = "token-plan"
    }
}

$COMMON_VALUES = [ordered]@{
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"  = "1"
    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK" = "1"
    "CLAUDE_CODE_EFFORT_LEVEL"                  = "max"
}

$PROVIDER_KEYS = [string[]]@(
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "CLAUDE_CODE_SUBAGENT_MODEL",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK",
    "CLAUDE_CODE_EFFORT_LEVEL"
)

$ALL_KEYS = [string[]]($PROVIDER_KEYS + @(
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_API_KEY"
))

function Ensure-ConfigDir {
    if (!(Test-Path $CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $CONFIG_DIR | Out-Null
    }
}

function Get-ProviderConfig {
    param([string]$Name)
    $normalized = $Name.Trim().ToLowerInvariant()
    if (!$PROVIDERS.Contains($normalized)) {
        Write-Host "[dpset] ERROR: Unknown provider '$Name'." -ForegroundColor Red
        Write-Host "        Run 'dpset list' to see supported providers."
        exit 1
    }
    return $PROVIDERS[$normalized]
}

function Select-ProviderInteractive {
    Write-Host ""
    Write-Host "Available providers:" -ForegroundColor Cyan
    $names = @($PROVIDERS.Keys)
    for ($i = 0; $i -lt $names.Count; $i++) {
        $cfg = $PROVIDERS[$names[$i]]
        Write-Host ("  {0}. {1,-8} {2}" -f ($i + 1), $names[$i], $cfg.Label)
    }
    Write-Host ""
    $choice = Read-Host "[dpset] Select provider by name or number"
    $choice = $choice.Trim().ToLowerInvariant()
    if ($choice -match '^\d+$') {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $names.Count) {
            return $names[$index]
        }
    }
    if ($PROVIDERS.Contains($choice)) {
        return $choice
    }
    Write-Host "[dpset] ERROR: Invalid provider selection." -ForegroundColor Red
    exit 1
}

function Get-UserVarSnapshot {
    $snap = [ordered]@{}
    foreach ($k in $ALL_KEYS) {
        $v = [Environment]::GetEnvironmentVariable($k, "User")
        $snap[$k] = if ($null -eq $v) { "" } else { $v }
    }
    return $snap
}

function Write-BackupIfMissing {
    Ensure-ConfigDir
    if (Test-Path $BACKUP_FILE) {
        return
    }
    $snap = Get-UserVarSnapshot
    $snap | ConvertTo-Json -Depth 2 | Set-Content -Path $BACKUP_FILE -Encoding UTF8
    Write-Host "[dpset] Original User environment saved to: $BACKUP_FILE" -ForegroundColor Cyan
}

function Get-PlainSecret {
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Get-ProviderValues {
    param(
        [string]$Name,
        [string]$Token
    )

    $cfg = Get-ProviderConfig $Name
    $values = [ordered]@{}
    $values["ANTHROPIC_BASE_URL"] = $cfg.BaseUrl
    $values["ANTHROPIC_MODEL"] = $cfg.ANTHROPIC_MODEL
    $values["ANTHROPIC_DEFAULT_OPUS_MODEL"] = $cfg.ANTHROPIC_DEFAULT_OPUS_MODEL
    $values["ANTHROPIC_DEFAULT_SONNET_MODEL"] = $cfg.ANTHROPIC_DEFAULT_SONNET_MODEL
    $values["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = $cfg.ANTHROPIC_DEFAULT_HAIKU_MODEL
    $values["CLAUDE_CODE_SUBAGENT_MODEL"] = $cfg.CLAUDE_CODE_SUBAGENT_MODEL
    foreach ($kv in $COMMON_VALUES.GetEnumerator()) {
        $values[$kv.Key] = $kv.Value
    }
    $values["ANTHROPIC_AUTH_TOKEN"] = $Token
    return $values
}

function Set-UserVar {
    param(
        [string]$Name,
        [AllowNull()][string]$Value
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
}

function Clear-UserVar {
    param([string]$Name)
    [Environment]::SetEnvironmentVariable($Name, $null, "User")
}

function Get-ScopeSnapshot {
    param([string]$Scope)
    $snap = [ordered]@{}
    foreach ($k in $ALL_KEYS) {
        $v = [Environment]::GetEnvironmentVariable($k, $Scope)
        $snap[$k] = if ($null -eq $v) { "" } else { $v }
    }
    return $snap
}

function Detect-ProviderFromSnapshot {
    param($Snapshot)
    $base = $Snapshot["ANTHROPIC_BASE_URL"]
    $model = $Snapshot["ANTHROPIC_MODEL"]
    foreach ($name in $PROVIDERS.Keys) {
        $cfg = $PROVIDERS[$name]
        if ($base -eq $cfg.BaseUrl) {
            return $name
        }
        if ($model -eq $cfg.ANTHROPIC_MODEL -or $model -eq $cfg.TestModel) {
            return $name
        }
    }
    if ([string]::IsNullOrWhiteSpace($base) -and [string]::IsNullOrWhiteSpace($model)) {
        return "inactive"
    }
    return "unknown"
}

function Format-ValueForDisplay {
    param(
        [string]$Name,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "(not set)"
    }
    if ($Name -match "TOKEN|KEY") {
        return "***hidden***"
    }
    return $Value
}

function Write-ScopeStatus {
    param([string]$Scope)
    $snap = Get-ScopeSnapshot $Scope
    $detected = Detect-ProviderFromSnapshot $snap
    Write-Host ("  {0,-8}: {1}" -f $Scope, $detected)
    Write-Host ("    {0,-44} {1}" -f "ANTHROPIC_BASE_URL", (Format-ValueForDisplay "ANTHROPIC_BASE_URL" $snap["ANTHROPIC_BASE_URL"]))
    Write-Host ("    {0,-44} {1}" -f "ANTHROPIC_MODEL", (Format-ValueForDisplay "ANTHROPIC_MODEL" $snap["ANTHROPIC_MODEL"]))
    Write-Host ("    {0,-44} {1}" -f "CLAUDE_CODE_EFFORT_LEVEL", (Format-ValueForDisplay "CLAUDE_CODE_EFFORT_LEVEL" $snap["CLAUDE_CODE_EFFORT_LEVEL"]))
    Write-Host ("    {0,-44} {1}" -f "CLAUDE_CODE_SUBAGENT_MODEL", (Format-ValueForDisplay "CLAUDE_CODE_SUBAGENT_MODEL" $snap["CLAUDE_CODE_SUBAGENT_MODEL"]))
    Write-Host ("    {0,-44} {1}" -f "ANTHROPIC_AUTH_TOKEN", (Format-ValueForDisplay "ANTHROPIC_AUTH_TOKEN" $snap["ANTHROPIC_AUTH_TOKEN"]))
    Write-Host ("    {0,-44} {1}" -f "ANTHROPIC_API_KEY", (Format-ValueForDisplay "ANTHROPIC_API_KEY" $snap["ANTHROPIC_API_KEY"]))
}

function Get-ActiveProviderFileValue {
    if (Test-Path $ACTIVE_PROVIDER_FILE) {
        $val = (Get-Content -Path $ACTIVE_PROVIDER_FILE -Encoding UTF8 -Raw).Trim()
        # Migrate legacy provider names from v1
        if ($val -eq "mimo-token-cn") {
            Set-Content -Path $ACTIVE_PROVIDER_FILE -Value "mimo" -Encoding UTF8
            return "mimo"
        }
        return $val
    }
    return ""
}

function Strip-ContextSuffix {
    param([string]$Model)
    return ($Model -replace '\[1m\]$', '')
}

function Invoke-ProviderTest {
    param(
        [string]$Name,
        [string]$Token
    )

    $cfg = Get-ProviderConfig $Name
    if ($cfg.BillingMode -eq "token-plan" -and !$Token.Trim().StartsWith("tp-")) {
        Write-Host "[dpset] WARNING: Token Plan keys usually start with 'tp-'." -ForegroundColor Yellow
    }
    $uri = $cfg.BaseUrl.TrimEnd("/") + "/v1/messages"
    $testModel = Strip-ContextSuffix $cfg.TestModel

    $headers = @{
        "Authorization"     = "Bearer $Token"
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }
    $body = @{
        model = $testModel
        max_tokens = 8
        messages = @(
            @{
                role = "user"
                content = "Reply with ok."
            }
        )
    } | ConvertTo-Json -Depth 8

    Write-Host "[dpset] Testing $($cfg.Label) endpoint..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 60 | Out-Null
        Write-Host "[dpset] Provider test passed." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[dpset] Provider test failed." -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)"
        return $false
    }
}

function Invoke-List {
    Write-Host ""
    Write-Host "Supported providers:" -ForegroundColor Cyan
    foreach ($name in $PROVIDERS.Keys) {
        $cfg = $PROVIDERS[$name]
        Write-Host ("  {0,-8} {1}" -f $name, $cfg.Label)
        Write-Host ("           base   : {0}" -f $cfg.BaseUrl)
        Write-Host ("           model  : {0}" -f $cfg.ANTHROPIC_MODEL)
        Write-Host ("           haiku  : {0}" -f $cfg.ANTHROPIC_DEFAULT_HAIKU_MODEL)
        Write-Host ("           subagt : {0}" -f $cfg.CLAUDE_CODE_SUBAGENT_MODEL)
    }
    Write-Host ""
}

function Invoke-Status {
    Write-Host ""
    Write-Host "=== dpset status ===" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $BACKUP_FILE) {
        Write-Host "  Backup          : FOUND ($BACKUP_FILE)" -ForegroundColor Yellow
    } else {
        Write-Host "  Backup          : none" -ForegroundColor Gray
    }

    $active = Get-ActiveProviderFileValue
    if ([string]::IsNullOrWhiteSpace($active)) {
        Write-Host "  Active provider : none" -ForegroundColor Gray
    } else {
        Write-Host "  Active provider : $active"
    }

    if (Test-Path $LAST_SWITCH_FILE) {
        Write-Host "  Last switch     : $LAST_SWITCH_FILE"
    }

    Write-Host ""
    Write-Host "  Scope snapshots:"
    Write-ScopeStatus "Process"
    Write-ScopeStatus "User"
    Write-ScopeStatus "Machine"

    $processProvider = Detect-ProviderFromSnapshot (Get-ScopeSnapshot "Process")
    $userProvider = Detect-ProviderFromSnapshot (Get-ScopeSnapshot "User")
    if ($processProvider -ne $userProvider) {
        Write-Host ""
        Write-Host "  Drift           : Process scope differs from persistent User scope." -ForegroundColor Yellow
        Write-Host "                    Current Claude sessions may keep using Process values until restarted."
    }

    Write-Host ""
}

function Invoke-On {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Select-ProviderInteractive
    } else {
        $Name = $Name.Trim().ToLowerInvariant()
    }
    $cfg = Get-ProviderConfig $Name

    Write-Host ""
    Write-Host "[dpset] Target provider: $($cfg.Label)" -ForegroundColor Cyan
    Write-BackupIfMissing

    $token = Get-PlainSecret "[dpset] Enter API key for $($cfg.Label)"
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host "[dpset] ERROR: API key cannot be empty. Aborting." -ForegroundColor Red
        exit 1
    }
    $token = $token.Trim()

    $shouldTest = Read-Host "[dpset] Test provider before writing User environment? (Y/n)"
    if ($shouldTest.Trim().ToLowerInvariant() -ne "n") {
        if (!(Invoke-ProviderTest -Name $Name -Token $token)) {
            Write-Host "[dpset] Aborted. User environment was not changed." -ForegroundColor Yellow
            exit 1
        }
    }

    $previousUserProvider = Detect-ProviderFromSnapshot (Get-ScopeSnapshot "User")
    $values = Get-ProviderValues -Name $Name -Token $token

    foreach ($kv in $values.GetEnumerator()) {
        Set-UserVar -Name $kv.Key -Value $kv.Value
    }
    Clear-UserVar "ANTHROPIC_API_KEY"

    Ensure-ConfigDir
    Set-Content -Path $ACTIVE_PROVIDER_FILE -Value $Name -Encoding UTF8
    [ordered]@{
        switched_at = (Get-Date).ToString("o")
        previous_user_provider = $previousUserProvider
        active_provider = $Name
        model = $values["ANTHROPIC_MODEL"]
        base_url = $values["ANTHROPIC_BASE_URL"]
        token_saved_in_user_env = $true
    } | ConvertTo-Json -Depth 3 | Set-Content -Path $LAST_SWITCH_FILE -Encoding UTF8

    Write-Host ""
    Write-Host "[dpset] $($cfg.Label) configuration written to User environment." -ForegroundColor Green
    Write-Host "        ANTHROPIC_AUTH_TOKEN is stored in User environment, but not in dpset files."
    Write-Host "        ANTHROPIC_API_KEY was cleared to avoid header/auth conflicts."
    Write-Host ""
    Write-Host "[dpset] IMPORTANT: Close current Claude/terminal sessions and open a new terminal for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

function Invoke-Test {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = Select-ProviderInteractive
    } else {
        $Name = $Name.Trim().ToLowerInvariant()
    }
    $cfg = Get-ProviderConfig $Name
    $token = Get-PlainSecret "[dpset] Enter API key for $($cfg.Label)"
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host "[dpset] ERROR: API key cannot be empty. Aborting." -ForegroundColor Red
        exit 1
    }
    if (!(Invoke-ProviderTest -Name $Name -Token $token.Trim())) {
        exit 1
    }
}

function Invoke-Off {
    Write-Host ""
    foreach ($k in $ALL_KEYS) {
        Clear-UserVar $k
    }
    if (Test-Path $ACTIVE_PROVIDER_FILE) {
        Remove-Item -Path $ACTIVE_PROVIDER_FILE -Force
    }
    Write-Host "[dpset] Managed variables removed from User scope." -ForegroundColor Yellow
    Write-Host "        Backup is preserved. Run 'dpset reset' to restore the pre-dpset baseline."
    Write-Host ""
    Write-Host "[dpset] IMPORTANT: Restart terminal/Claude sessions for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

function Invoke-Reset {
    Write-Host ""
    if (!(Test-Path $BACKUP_FILE)) {
        Write-Host "[dpset] ERROR: No backup file found at:" -ForegroundColor Red
        Write-Host "        $BACKUP_FILE"
        exit 1
    }

    $json = Get-Content -Path $BACKUP_FILE -Encoding UTF8 -Raw | ConvertFrom-Json
    $snap = @{}
    $json.PSObject.Properties | ForEach-Object { $snap[$_.Name] = $_.Value }

    Write-Host "[dpset] Restoring User environment to pre-dpset baseline..." -ForegroundColor Cyan
    foreach ($k in $ALL_KEYS) {
        if ($snap.ContainsKey($k)) {
            $v = $snap[$k]
            if ($null -eq $v -or $v -eq "") {
                Clear-UserVar $k
            } else {
                Set-UserVar -Name $k -Value $v
            }
        } else {
            Clear-UserVar $k
        }
    }

    Remove-Item -Path $BACKUP_FILE -Force
    if (Test-Path $ACTIVE_PROVIDER_FILE) {
        Remove-Item -Path $ACTIVE_PROVIDER_FILE -Force
    }
    if (Test-Path $LAST_SWITCH_FILE) {
        Remove-Item -Path $LAST_SWITCH_FILE -Force
    }

    Write-Host "[dpset] Reset complete. Backup and dpset provider state were cleared." -ForegroundColor Green
    Write-Host "[dpset] IMPORTANT: Restart terminal/Claude sessions for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

switch ($Action.Trim().ToLowerInvariant()) {
    "on"     { Invoke-On -Name $Provider }
    "test"   { Invoke-Test -Name $Provider }
    "off"    { Invoke-Off }
    "reset"  { Invoke-Reset }
    "status" { Invoke-Status }
    "list"   { Invoke-List }
    default  {
        Write-Host ""
        Write-Host "dpset - Claude Code provider switcher" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  dpset status          Show Process/User/Machine provider state"
        Write-Host "  dpset list            List supported providers"
        Write-Host "  dpset on              Pick provider interactively"
        Write-Host "  dpset on deepseek     Switch persistent User env to DeepSeek"
        Write-Host "  dpset on mimo         Switch persistent User env to MiMo Token Plan (CN)"
        Write-Host "  dpset test deepseek   Test DeepSeek key/endpoint without writing env"
        Write-Host "  dpset test mimo       Test MiMo Token Plan (CN) without writing env"
        Write-Host "  dpset off             Remove managed User env variables, keep backup"
        Write-Host "  dpset reset           Restore pre-dpset User env and clear dpset state"
        Write-Host ""
        Write-Host "Notes:"
        Write-Host "  - Provider switches write User-scope variables; restart terminals/Claude sessions."
        Write-Host "  - API keys are stored in User env for Claude Code, not in dpset state files."
        Write-Host "  - ANTHROPIC_API_KEY is cleared to avoid conflicting X-Api-Key authentication."
        Write-Host ""
    }
}
'@

Set-Content -Path $PS1_PATH -Value $dpsetScript -Encoding UTF8
Write-Host "[2/4] Written: $PS1_PATH" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Write dpset.bat  (thin wrapper so 'dpset' works from PowerShell / CMD)
# ---------------------------------------------------------------------------
$batContent = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dpset.ps1" %*
"@

Set-Content -Path $BAT_PATH -Value $batContent -Encoding ASCII
Write-Host "[3/4] Written: $BAT_PATH" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Add $HOME\bin to User PATH if not already present
# ---------------------------------------------------------------------------
$userPath  = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($null -eq $userPath) { $userPath = "" }

$pathParts = $userPath -split ";" | Where-Object { $_.Trim() -ne "" }

if ($pathParts -contains $INSTALL_DIR) {
    Write-Host "[4/4] '$INSTALL_DIR' is already in User PATH." -ForegroundColor Gray
} else {
    $newPath = ($pathParts + $INSTALL_DIR) -join ";"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "[4/4] Added '$INSTALL_DIR' to User PATH." -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installation / upgrade complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Files installed:"
Write-Host "    $PS1_PATH"
Write-Host "    $BAT_PATH"
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "    1. Close this terminal completely."
Write-Host "    2. Open a new PowerShell window."
Write-Host "    3. Run: dpset status"
Write-Host "    4. Run: dpset on deepseek   or   dpset on mimo"
Write-Host ""
Write-Host "  Available commands after restart:"
Write-Host "    dpset status       - Show Process/User/Machine provider state"
Write-Host "    dpset list         - List providers"
Write-Host "    dpset on deepseek  - Switch persistent User env to DeepSeek"
Write-Host "    dpset on mimo      - Switch persistent User env to MiMo Token Plan (CN)"
Write-Host "    dpset test mimo    - Test MiMo without changing env"
Write-Host "    dpset off          - Remove managed User env variables"
Write-Host "    dpset reset        - Restore pre-dpset User env"
Write-Host ""
