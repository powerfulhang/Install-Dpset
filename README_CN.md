# dpset

在 Windows 上一键安装和管理 DeepSeek V4 Pro / Claude Code 环境变量。

[English](README.md)

## 功能

`dpset` 通过管理 Windows 用户环境变量，让你的 Claude Code（或任何兼容 Anthropic 协议的客户端）在 **DeepSeek V4 Pro** 和原始 API 配置之间一键切换——无需手动修改系统对话框，不留残留状态。

## 快速安装

右键 `Install-Dpset.ps1` → **使用 PowerShell 运行**，或在终端中执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Dpset.ps1
```

安装程序会：
- 创建 `%USERPROFILE%\bin\` 目录
- 写入 `dpset.ps1` 和 `dpset.bat` 两个文件
- 将 `%USERPROFILE%\bin` 添加到用户的 `PATH` 环境变量中

安装完成后，**重启终端**，然后运行：

```powershell
dpset on
```

根据提示输入你的 DeepSeek API Key。配置会立即写入用户环境变量。

## 命令

| 命令 | 作用 |
|------|------|
| `dpset on` | 备份当前环境变量（仅首次），然后应用 DeepSeek 配置并提示输入 API Key |
| `dpset off` | 移除所有 dpset 管理的环境变量（备份文件保留） |
| `dpset reset` | 从备份恢复原始环境变量，并清除备份文件 |
| `dpset status` | 查看所有受管变量当前值及备份状态 |

每次执行 dpset 命令后，都需要**重启终端**才能使变更生效。

## 管理的变量

`dpset on` 会设置以下用户环境变量：

| 变量名 | 值 |
|--------|-----|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro[1m]` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `deepseek-v4-pro` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `deepseek-v4-pro` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `deepseek-v4-flash` |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `deepseek-v4-pro` |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | `1` |
| `CLAUDE_CODE_EFFORT_LEVEL` | `max` |
| `ANTHROPIC_AUTH_TOKEN` | 你的 API Key（交互式输入，不会写入脚本文件） |

## 安全保障

- 所有修改仅作用于**用户**环境变量（不影响系统级）
- 首次 `dpset on` 会在 `%USERPROFILE%\.dpset\backup.json` 创建环境快照
- `dpset reset` 能完全恢复到原始状态并清除备份
- API Key 通过交互式提示输入，绝不会写入脚本文件

## 系统要求

- Windows 10 或更高版本
- PowerShell 5.1 或更高版本

## 卸载

先运行 `dpset reset` 恢复原始环境，然后手动删除：
- `%USERPROFILE%\bin\dpset.ps1`
- `%USERPROFILE%\bin\dpset.bat`
- `%USERPROFILE%\.dpset\`（整个目录）

最后通过系统环境变量对话框，从用户 `PATH` 中移除 `%USERPROFILE%\bin`。
