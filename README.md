# dpset

One-command installer and manager for DeepSeek V4 Pro / Claude Code environment variables on Windows.

[中文说明](README_CN.md)

## What it does

`dpset` switches your Claude Code (or any Anthropic-compatible client) between **DeepSeek V4 Pro** and your original API configuration by managing Windows User environment variables — no manual editing of system dialogs, no leftover state.

## Quick install

Right-click `Install-Dpset.ps1` → **Run with PowerShell**, or run in a terminal:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Dpset.ps1
```

The installer:
- Creates `%USERPROFILE%\bin\`
- Writes `dpset.ps1` and `dpset.bat`
- Adds `%USERPROFILE%\bin` to your User `PATH`

After installation, **restart your terminal**, then:

```powershell
dpset on
```

Enter your DeepSeek API key when prompted. The config is applied instantly to User environment variables.

## Commands

| Command | What it does |
|---------|-------------|
| `dpset on` | Backs up current state (first run only), then applies DeepSeek config + prompts for API key |
| `dpset off` | Removes all managed variables (backup is preserved) |
| `dpset reset` | Restores the original environment from backup, then clears the backup |
| `dpset status` | Shows current values of all managed variables and backup status |

Always restart your terminal after any `dpset` command for changes to take effect.

## Managed variables

`dpset on` sets these User environment variables:

| Variable | Value |
|----------|-------|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro[1m]` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `deepseek-v4-pro` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `deepseek-v4-pro` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `deepseek-v4-flash` |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `deepseek-v4-pro` |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | `1` |
| `CLAUDE_CODE_EFFORT_LEVEL` | `max` |
| `ANTHROPIC_AUTH_TOKEN` | Your API key (prompted interactively, never stored in script) |

## Safety

- All changes are scoped to **User** environment variables (not System)
- The first `dpset on` takes a snapshot saved to `%USERPROFILE%\.dpset\backup.json`
- `dpset reset` fully restores the original environment and clears the backup
- Your API key is prompted interactively — it is never written into the script file

## Requirements

- Windows 10 or later
- PowerShell 5.1 or later

## Uninstall

Run `dpset reset` to restore your original environment, then delete:
- `%USERPROFILE%\bin\dpset.ps1`
- `%USERPROFILE%\bin\dpset.bat`
- `%USERPROFILE%\.dpset\` (directory)

Remove `%USERPROFILE%\bin` from your User `PATH` via System Environment Variables dialog.
