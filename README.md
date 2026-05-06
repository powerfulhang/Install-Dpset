# dpset

Lightweight Claude Code provider switcher for Windows. It manages User-scope
environment variables so Claude Code can run through DeepSeek V4 Pro or Xiaomi
MiMo without hand-editing Windows environment dialogs.

Windows 上轻量化的 Claude Code 提供商切换器。它通过管理用户级环境变量，让 Claude Code 可以在 DeepSeek V4 Pro 和 Xiaomi MiMo 之间切换，而不需要手动打开系统环境变量面板。

---

## What it does / 功能

`dpset` writes a complete provider configuration to the Windows User environment
and preserves the original pre-dpset state in `%USERPROFILE%\.dpset\backup.json`.

`dpset` 会把完整的 provider 配置写入 Windows User 级环境变量，并把首次使用前的原始状态保存到 `%USERPROFILE%\.dpset\backup.json`。

### Supported providers / 支持的提供商

| Provider | Main model / 主模型 | Base URL |
|----------|---------------------|----------|
| DeepSeek | `deepseek-v4-pro[1m]` | `https://api.deepseek.com/anthropic` |
| MiMo (CN Token Plan) | `mimo-v2.5-pro[1m]` | `https://token-plan-cn.xiaomimimo.com/anthropic` |

---

## Install or upgrade / 安装或升级

Run from this repository directory / 在本仓库目录下运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Dpset.ps1
```

The installer writes / 安装器会写入：

- `%USERPROFILE%\bin\dpset.ps1`
- `%USERPROFILE%\bin\dpset.bat`

It preserves existing dpset runtime state under `%USERPROFILE%\.dpset\`,
including `backup.json`.

安装器会保留 `%USERPROFILE%\.dpset\` 下的已有运行时状态，包括 `backup.json`。

After installation, close the current terminal, open a new PowerShell window,
then run / 安装完成后，关闭当前终端，重新打开 PowerShell，然后运行：

```powershell
dpset status
```

---

## Commands / 命令

| Command / 命令 | What it does / 作用 |
|----------------|---------------------|
| `dpset status` | Show Process, User, and Machine provider state / 显示三层配置状态 |
| `dpset list` | List supported providers / 列出支持的提供商 |
| `dpset on` | Pick a provider interactively / 交互式选择提供商 |
| `dpset on deepseek` | Switch persistent User env to DeepSeek / 切换到 DeepSeek |
| `dpset on mimo` | Switch persistent User env to MiMo CN Token Plan / 切换到 MiMo |
| `dpset test deepseek` | Test DeepSeek without writing User env / 测试 DeepSeek，不写入环境变量 |
| `dpset test mimo` | Test MiMo without writing User env / 测试 MiMo，不写入环境变量 |
| `dpset off` | Remove managed User env variables, keep backup / 清除受管变量，保留备份 |
| `dpset reset` | Restore the pre-dpset User env from backup / 从备份恢复原始环境 |

Always restart your terminal and Claude Code sessions after `on`, `off`, or
`reset`. Existing processes keep their current Process-scope environment.

执行 `on`、`off`、`reset` 后，需要重启终端和 Claude Code 会话才会生效。已打开的 Claude Code 会继续使用它启动时继承的 Process 环境变量。

---

## Recommended safe flow / 推荐安全流程

### Switch to MiMo / 切到 MiMo

```powershell
dpset status
dpset test mimo
dpset on mimo
```

### Switch to DeepSeek / 切到 DeepSeek

```powershell
dpset test deepseek
dpset on deepseek
```

Then close the terminal, open a new one, and run / 然后关闭终端，重新打开，再运行：

```powershell
claude
```

---

## Managed variables / 受管变量

`dpset on <provider>` writes these User-scope variables / 会写入以下 User 级环境变量：

| Variable / 变量 | Purpose / 作用 |
|-----------------|----------------|
| `ANTHROPIC_BASE_URL` | Provider Anthropic-compatible endpoint |
| `ANTHROPIC_MODEL` | Main Claude Code model / 主模型 |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus-tier model mapping / Opus 层模型映射 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet-tier model mapping / Sonnet 层模型映射 |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku-tier model mapping / Haiku 层模型映射 |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Subagent model / 子代理模型 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Disable nonessential traffic / 关闭非必要流量 |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | Avoid nonstreaming fallback / 关闭 non-streaming fallback |
| `CLAUDE_CODE_EFFORT_LEVEL` | Effort level, set to `max` / 推理强度，固定为 `max` |
| `ANTHROPIC_AUTH_TOKEN` | Provider API key in User env / Provider API Key，保存到 User 环境变量 |

`ANTHROPIC_API_KEY` is cleared during provider switches to avoid conflicting
`X-Api-Key` authentication.

切换 provider 时会清除 `ANTHROPIC_API_KEY`，避免它以 `X-Api-Key` 方式和 `ANTHROPIC_AUTH_TOKEN` 冲突。

---

## Runtime files / 运行时文件

```text
%USERPROFILE%\.dpset\
  backup.json       Original pre-dpset User environment snapshot / 首次使用前的环境快照
  active_provider   Last provider written by dpset / 最近一次写入的 provider
  last_switch.json  Non-secret switch metadata / 不含 API key 的切换记录
```

API keys are stored in Windows User environment as `ANTHROPIC_AUTH_TOKEN` so
new Claude Code sessions can use them. They are not written to dpset runtime
state files.

API key 会保存为 Windows User 环境变量 `ANTHROPIC_AUTH_TOKEN`，以便新启动的 Claude Code 使用；不会写入 dpset 的运行时状态文件。

---

## Rollback / 回滚

Remove the active provider configuration while preserving the original backup /
只清除当前 provider 配置，保留原始备份：

```powershell
dpset off
```

Restore the pre-dpset User environment from `backup.json` /
从 `backup.json` 恢复到 pre-dpset 原始 User 环境：

```powershell
dpset reset
```
