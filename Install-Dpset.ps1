# =============================================================================
# Install-Dpset.ps1
# One-time installer for the 'dpset' command-line tool.
#
# USAGE:
#   Right-click this file -> "Run with PowerShell"
#   OR open PowerShell and run:
#       powershell -ExecutionPolicy Bypass -File .\Install-Dpset.ps1
#
# AFTER INSTALLATION (restart terminal first):
#   dpset on      - Apply DeepSeek V4 Pro config to User environment variables
#   dpset off     - Remove all managed environment variables
#   dpset reset   - Restore environment to the state before the first 'dpset on'
#   dpset status  - Show current values of all managed variables
# =============================================================================

$ErrorActionPreference = "Stop"

$INSTALL_DIR = Join-Path $HOME "bin"
$PS1_PATH    = Join-Path $INSTALL_DIR "dpset.ps1"
$BAT_PATH    = Join-Path $INSTALL_DIR "dpset.bat"

Write-Host ""
Write-Host "=== dpset Installer ===" -ForegroundColor Cyan
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
# dpset.ps1  -  DeepSeek V4 Pro / Claude Code environment variable manager
# Installed by Install-Dpset.ps1  |  Do not move this file independently.
#
# Usage: dpset <on | off | reset | status>
# =============================================================================

param(
    [Parameter(Position = 0)]
    [string]$Action = "help"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$CONFIG_DIR  = Join-Path $HOME ".dpset"
$BACKUP_FILE = Join-Path $CONFIG_DIR "backup.json"

# Fixed key-value pairs that dpset manages (excluding ANTHROPIC_AUTH_TOKEN
# which is prompted interactively to avoid storing it in this script).
$DS_VALUES = [ordered]@{
    "ANTHROPIC_BASE_URL"                        = "https://api.deepseek.com/anthropic"
    "ANTHROPIC_MODEL"                           = "deepseek-v4-pro[1m]"
    "ANTHROPIC_DEFAULT_OPUS_MODEL"              = "deepseek-v4-pro"
    "ANTHROPIC_DEFAULT_SONNET_MODEL"            = "deepseek-v4-pro"
    "ANTHROPIC_DEFAULT_HAIKU_MODEL"             = "deepseek-v4-flash"
    "CLAUDE_CODE_SUBAGENT_MODEL"                = "deepseek-v4-pro"
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"  = "1"
    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK" = "1"
    "CLAUDE_CODE_EFFORT_LEVEL"                  = "max"
}

# All keys tracked by dpset (used for backup / restore)
$ALL_KEYS = [string[]]($DS_VALUES.Keys) + "ANTHROPIC_AUTH_TOKEN"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-UserVarSnapshot {
    $snap = @{}
    foreach ($k in $ALL_KEYS) {
        $v = [Environment]::GetEnvironmentVariable($k, "User")
        $snap[$k] = if ($null -eq $v) { "" } else { $v }
    }
    return $snap
}

function Write-Backup {
    if (!(Test-Path $CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $CONFIG_DIR | Out-Null
    }
    $snap = Get-UserVarSnapshot
    $snap | ConvertTo-Json -Depth 2 | Set-Content -Path $BACKUP_FILE -Encoding UTF8
    Write-Host "[dpset] Original state saved to: $BACKUP_FILE" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# dpset on
# ---------------------------------------------------------------------------
function Invoke-On {
    Write-Host ""

    if (Test-Path $BACKUP_FILE) {
        # Backup already exists: user has run 'on' before without 'reset'
        Write-Host "[dpset] WARNING: A backup already exists." -ForegroundColor Yellow
        Write-Host "        This means 'dpset on' was previously applied and not reset."
        Write-Host "        The existing backup will be preserved (protecting your true original state)."
        Write-Host ""
        $confirm = Read-Host "[dpset] Re-apply DeepSeek config? This will overwrite current settings. (y/N)"
        if ($confirm.Trim().ToLower() -ne "y") {
            Write-Host "[dpset] Aborted." -ForegroundColor Yellow
            return
        }
    } else {
        # First run: snapshot current state before touching anything
        Write-Host "[dpset] First run detected. Saving original environment state..."
        Write-Backup
    }

    Write-Host ""
    $apiKey = Read-Host "[dpset] Enter your DeepSeek API Key"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host "[dpset] ERROR: API key cannot be empty. Aborting." -ForegroundColor Red
        exit 1
    }

    # Apply all fixed variables
    foreach ($kv in $DS_VALUES.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "User")
    }
    # Apply the API key
    [Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $apiKey.Trim(), "User")

    Write-Host ""
    Write-Host "[dpset] DeepSeek V4 Pro configuration applied." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Variables written to User environment:"
    foreach ($kv in $DS_VALUES.GetEnumerator()) {
        Write-Host ("    {0,-48} = {1}" -f $kv.Key, $kv.Value)
    }
    Write-Host ("    {0,-48} = {1}" -f "ANTHROPIC_AUTH_TOKEN", "***hidden***")
    Write-Host ""
    Write-Host "[dpset] IMPORTANT: Restart your terminal for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
# dpset off
# ---------------------------------------------------------------------------
function Invoke-Off {
    Write-Host ""

    $anySet = $false
    foreach ($k in $ALL_KEYS) {
        $v = [Environment]::GetEnvironmentVariable($k, "User")
        if ($null -ne $v -and $v -ne "") { $anySet = $true; break }
    }

    if (!$anySet) {
        Write-Host "[dpset] No managed variables are currently set. Nothing to remove." -ForegroundColor Gray
        return
    }

    foreach ($k in $ALL_KEYS) {
        [Environment]::SetEnvironmentVariable($k, $null, "User")
    }

    Write-Host "[dpset] All managed environment variables removed from User scope." -ForegroundColor Yellow
    Write-Host "        (Backup is preserved. Run 'dpset reset' to fully restore the original state.)"
    Write-Host ""
    Write-Host "[dpset] IMPORTANT: Restart your terminal for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
# dpset reset
# ---------------------------------------------------------------------------
function Invoke-Reset {
    Write-Host ""

    if (!(Test-Path $BACKUP_FILE)) {
        Write-Host "[dpset] ERROR: No backup file found at:" -ForegroundColor Red
        Write-Host "        $BACKUP_FILE"
        Write-Host "        Run 'dpset on' at least once before using 'dpset reset'."
        exit 1
    }

    # Parse backup JSON into a hashtable
    $json = Get-Content -Path $BACKUP_FILE -Encoding UTF8 -Raw | ConvertFrom-Json
    $snap = @{}
    $json.PSObject.Properties | ForEach-Object { $snap[$_.Name] = $_.Value }

    Write-Host "[dpset] Restoring environment to pre-dpset state..." -ForegroundColor Cyan
    Write-Host ""

    foreach ($k in $ALL_KEYS) {
        $v = $snap[$k]
        if ($null -eq $v -or $v -eq "") {
            [Environment]::SetEnvironmentVariable($k, $null, "User")
            Write-Host ("    {0,-48}  cleared (was not set originally)" -f $k) -ForegroundColor Gray
        } else {
            [Environment]::SetEnvironmentVariable($k, $v, "User")
            if ($k -eq "ANTHROPIC_AUTH_TOKEN") {
                Write-Host ("    {0,-48}  restored (***hidden***)" -f $k) -ForegroundColor Green
            } else {
                Write-Host ("    {0,-48}  restored = {1}" -f $k, $v) -ForegroundColor Green
            }
        }
    }

    # Delete the backup so next 'dpset on' creates a fresh baseline
    Remove-Item -Path $BACKUP_FILE -Force

    Write-Host ""
    Write-Host "[dpset] Environment fully restored to original state." -ForegroundColor Green
    Write-Host "        Backup cleared. Next 'dpset on' will create a fresh baseline."
    Write-Host ""
    Write-Host "[dpset] IMPORTANT: Restart your terminal for changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
# dpset status
# ---------------------------------------------------------------------------
function Invoke-Status {
    Write-Host ""
    Write-Host "=== dpset status ===" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $BACKUP_FILE) {
        Write-Host "  Backup : FOUND  ($BACKUP_FILE)" -ForegroundColor Yellow
        Write-Host "           Run 'dpset reset' to restore the original state."
    } else {
        Write-Host "  Backup : none" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  Current User Environment Variables (managed by dpset):"
    Write-Host ""

    $anyActive = $false
    foreach ($k in $ALL_KEYS) {
        $v = [Environment]::GetEnvironmentVariable($k, "User")
        if ($null -eq $v -or $v -eq "") {
            Write-Host ("    {0,-48}  (not set)" -f $k) -ForegroundColor Gray
        } elseif ($k -eq "ANTHROPIC_AUTH_TOKEN") {
            Write-Host ("    {0,-48}  ***hidden***" -f $k) -ForegroundColor Green
            $anyActive = $true
        } else {
            Write-Host ("    {0,-48}  {1}" -f $k, $v) -ForegroundColor Green
            $anyActive = $true
        }
    }

    Write-Host ""
    if ($anyActive) {
        Write-Host "  State : ACTIVE (DeepSeek config is applied)" -ForegroundColor Green
    } else {
        Write-Host "  State : INACTIVE (no managed variables are set)" -ForegroundColor Gray
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
switch ($Action.ToLower()) {
    "on"     { Invoke-On }
    "off"    { Invoke-Off }
    "reset"  { Invoke-Reset }
    "status" { Invoke-Status }
    default  {
        Write-Host ""
        Write-Host "dpset - DeepSeek V4 Pro / Claude Code environment manager" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  dpset on      Apply DeepSeek V4 Pro config to User environment variables"
        Write-Host "  dpset off     Remove all managed environment variables"
        Write-Host "  dpset reset   Restore to the state before the very first 'dpset on'"
        Write-Host "  dpset status  Show current values of all managed variables"
        Write-Host ""
        Write-Host "Notes:"
        Write-Host "  - 'on'    backs up current state on first run, then applies DeepSeek config."
        Write-Host "  - 'off'   removes the variables but keeps the backup."
        Write-Host "  - 'reset' restores from backup AND clears it (fresh baseline on next 'on')."
        Write-Host "  - All changes affect the User scope only (not System-wide)."
        Write-Host "  - Always restart your terminal after any dpset command."
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

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Files installed:"
Write-Host "    $PS1_PATH"
Write-Host "    $BAT_PATH"
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "    1. Close this terminal completely."
Write-Host "    2. Open a new PowerShell window."
Write-Host "    3. Run: dpset on"
Write-Host ""
Write-Host "  Available commands after restart:"
Write-Host "    dpset on      - Apply DeepSeek V4 Pro config"
Write-Host "    dpset off     - Remove DeepSeek config"
Write-Host "    dpset reset   - Restore original environment"
Write-Host "    dpset status  - Show current variable state"
Write-Host ""
