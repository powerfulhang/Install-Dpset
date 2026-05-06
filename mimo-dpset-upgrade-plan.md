# dpset 多提供商升级计划

> 作者: hang.shi | 版本: 1.0 | 日期: 2026-05-02

## 背景

当前 `dpset` 只支持 DeepSeek V4 Pro 单一提供商。用户需要在 DeepSeek 和 Xiaomi MiMo 之间自由切换，且保证切换过程安全可逆。

## 1. 现状分析

### 1.1 当前文件布局

```
%USERPROFILE%\bin\
  dpset.ps1          ← 主逻辑脚本（单提供商：硬编码 DeepSeek）
  dpset.bat          ← 薄封装，调用 dpset.ps1

%USERPROFILE%\.dpset\
  backup.json        ← 记录 pre-dpset 原始环境快照
```

### 1.2 当前环境变量状态

| 变量 | 值 | 来源 |
|------|-----|------|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` | dpset |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro[1m]` | dpset |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `deepseek-v4-pro` | dpset |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `deepseek-v4-pro` | dpset |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `deepseek-v4-flash` | dpset |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `deepseek-v4-pro` | dpset |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | dpset |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | `1` | dpset |
| `CLAUDE_CODE_EFFORT_LEVEL` | `max` | dpset |
| `ANTHROPIC_AUTH_TOKEN` | `***`（DeepSeek API Key） | 交互输入 |
| `ANTHROPIC_API_KEY` | （未管理） | — |
| `ANTHROPIC_BASE_URL` 等 | `***`（DeepSeek API Key） | 交互输入 |

### 1.3 发现的问题

| # | 问题 | 严重性 | 修复方式 |
|---|------|--------|---------|
| 1 | **`ANTHROPIC_API_KEY` 未被管理** — 如果用户之前设过 Anthropic 原生 Key，会和第三方提供商冲突（Claude Code 会优先走原生 API） | 中 | 纳入 `$ALL_KEYS`，`on` 时显式清空 |
| 2 | **无法切换提供商** — 只能切到 DeepSeek，切换到 MiMo 需手动改变量 | 核心需求 | 提供商抽象层 |
| 3 | **Legacy 升级路径缺失** — 旧版已安装用户升级时，backup.json 已存在，需正确处理 | 高 | 检测 legacy 状态 + 兼容逻辑 |

## 2. 新增提供商：Xiaomi MiMo

### 2.1 端点与认证

| 项目 | DeepSeek | Xiaomi MiMo |
|------|----------|-------------|
| Anthropic 端点 | `https://api.deepseek.com/anthropic` | `https://api.xiaomimimo.com/anthropic` |
| Token Plan 端点 | — | `https://token-plan-cn.xiaomimimo.com/anthropic` |
| 认证方式 | `x-api-key` 头 | `Authorization: Bearer` (也接受 `api-key`) |
| 环境变量 | `ANTHROPIC_AUTH_TOKEN` | `ANTHROPIC_AUTH_TOKEN` |

> **Ref**: [Claude Code Docs — Environment Variables](https://code.claude.com/docs/en/env-vars): `ANTHROPIC_AUTH_TOKEN` → `Authorization: Bearer <value>`; `ANTHROPIC_API_KEY` → `X-Api-Key`。MiMo 同时接受两种，但推荐 Bearer 方式。
>
> **Ref**: [CSDN: Claude Code 接入小米 MiMo-V2-Pro](https://blog.csdn.net/lljss1980/article/details/159390083)

### 2.2 模型列表

| 分层 | DeepSeek | MiMo | 说明 |
|------|----------|------|------|
| 默认模型 | `deepseek-v4-pro[1m]` | `mimo-v2-pro[1m]` | `[1m]` 后缀激活扩展上下文，发送前被 Claude Code 剥离 |
| Opus 层 | `deepseek-v4-pro` | `mimo-v2-pro` | 旗舰推理模型 |
| Sonnet 层 | `deepseek-v4-pro` | `mimo-v2-pro` | 同上 |
| Haiku 层 | `deepseek-v4-flash` | `mimo-v2-flash` | 轻量快速模型（15B 激活参数） |
| Sub-agent | `deepseek-v4-pro` | `mimo-v2-flash` | 子代理用轻量模型节省成本 |

> **关于 `[1m]` 后缀**: Claude Code 检测到模型名末尾的 `[1m]` 时会剥离它再发送给 API 提供商，同时在内部启用 1M token 上下文窗口。发送到 MiMo API 的实际模型 ID 是 `mimo-v2-pro`。
>
> **Ref**: [Claude Code Docs — Model Config](https://code.claude.com/docs/en/model-config)

### 2.3 已知限制

| 限制 | 说明 | 影响 |
|------|------|------|
| **Thinking 签名差异** | MiMo 的 extended thinking 与 Anthropic 原生不完全一致 | 可能导致 `CLAUDE_CODE_EFFORT_LEVEL=max` 时行为有差异，实测再调 |
| **上下文未达理论值** | 宣传 1M，实际使用可能不到 | 长任务可能提前触发 compact |
| **stop_reason 可能不同** | 返回值可能与 Anthropic 原生略有差异 | Claude Code 的错误处理层会吸收大部分差异 |

> **Ref**: [Zed Discussion #45091](https://github.com/zed-industries/zed/discussions/45091), [CSDN: MiMo V2 Pro in Claude Code vs OpenCode](https://blog.csdn.net/lljss1980/article/details/159472257)

## 3. 新版命令设计

```
dpset on              交互式选择提供商（显示菜单）
dpset on deepseek     直接切到 DeepSeek
dpset on mimo          直接切到 MiMo
dpset off             移除所有受管变量（不变）
dpset reset           恢复 pre-dpset 原始环境 + 清除备份
dpset status          显示当前状态 + 活跃提供商
dpset list            列出所有可用提供商
```

## 4. 切换流程设计

### 4.1 用户实操：首次从 Legacy 升级

```
当前状态: DeepSeek 已生效，backup.json 存在，无 active_provider 文件

1. 替换 dpset.ps1（新版）
2. 运行: dpset status
   → 检测到 legacy 状态（env 中有 DeepSeek 变量但无 active_provider）
   → 提示: "Legacy install detected. Auto-detected provider: deepseek."
   → 写入 active_provider = "deepseek"
3. 运行: dpset on mimo
   → backup.json 存在 → 不重新备份
   → 交互输入 MiMo API Key
   → 写入 MiMo 全套变量（覆盖 DeepSeek 的）
   → 更新 active_provider = "mimo"
   → 提示: 重启终端
4. 重启终端 → Claude Code 使用 MiMo
```

### 4.2 用户实操：切回 DeepSeek

```
5. 运行: dpset on deepseek
   → backup.json 存在 → 不重新备份
   → 交互输入 DeepSeek API Key（不存盘，每次切换都问）
   → 写入 DeepSeek 全套变量（覆盖 MiMo 的）
   → 更新 active_provider = "deepseek"
   → 提示: 重启终端
6. 重启终端 → Claude Code 使用 DeepSeek
```

### 4.3 用户实操：彻底恢复原始环境

```
7. 运行: dpset reset
   → 从 backup.json 恢复所有变量到 pre-dpset 原始值
   → 删除 backup.json
   → 删除 active_provider
   → 提示: 重启终端
8. 重启终端 → 回到第一天什么都没装的状态
```

### 4.4 安全保证

| 保证 | 实现 |
|------|------|
| **备份永不覆盖** | `backup.json` 只在首次 `on` 时创建，后续 `on` 只读不写 |
| **切换原子性** | 每次 `on` 写入完整变量集，不依赖旧值，不留残留 |
| **reset 始终可用** | 只要 backup.json 存在，就能回到原点 |
| **API Key 不落盘** | 每次切换交互输入，不写入任何文件 |
| **旧版无感升级** | 检测 backup.json 存在 → 跳过首次备份；检测 env 值自动推断 active_provider |

## 5. 代码结构变更

### 5.1 提供商配置抽象

```powershell
$PROVIDERS = @{
    "deepseek" = @{
        "Label" = "DeepSeek V4 Pro"
        "ANTHROPIC_BASE_URL" = "https://api.deepseek.com/anthropic"
        "ANTHROPIC_MODEL" = "deepseek-v4-pro[1m]"
        "ANTHROPIC_DEFAULT_OPUS_MODEL" = "deepseek-v4-pro"
        "ANTHROPIC_DEFAULT_SONNET_MODEL" = "deepseek-v4-pro"
        "ANTHROPIC_DEFAULT_HAIKU_MODEL" = "deepseek-v4-flash"
        "CLAUDE_CODE_SUBAGENT_MODEL" = "deepseek-v4-pro"
    }
    "mimo" = @{
        "Label" = "Xiaomi MiMo"
        "ANTHROPIC_BASE_URL" = "https://api.xiaomimimo.com/anthropic"
        "ANTHROPIC_MODEL" = "mimo-v2-pro[1m]"
        "ANTHROPIC_DEFAULT_OPUS_MODEL" = "mimo-v2-pro"
        "ANTHROPIC_DEFAULT_SONNET_MODEL" = "mimo-v2-pro"
        "ANTHROPIC_DEFAULT_HAIKU_MODEL" = "mimo-v2-flash"
        "CLAUDE_CODE_SUBAGENT_MODEL" = "mimo-v2-flash"
    }
}
```

### 5.2 固定变量（所有提供商共用）

```powershell
$COMMON_VALUES = [ordered]@{
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" = "1"
    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK" = "1"
    "CLAUDE_CODE_EFFORT_LEVEL" = "max"
    "ANTHROPIC_API_KEY" = ""                    # 显式清空防冲突
}
```

### 5.3 受管 Key 全集

```powershell
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

$ALL_KEYS = $PROVIDER_KEYS + @("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY")
```

### 5.4 新增状态文件

```
%USERPROFILE%\.dpset\
  backup.json            ← 原有：原始环境快照（永不覆盖）
  active_provider        ← 新增：单行文本 "deepseek" / "mimo"
```

`active_provider` 的作用：
- `status` 命令显示当前活跃提供商
- Legacy 升级检测：env 中有配置但无此文件 → legacy 模式
- 切换时校验：避免对空参数执行 `on`

## 6. 分发与升级

### 6.1 已安装用户升级

```powershell
# 直接替换已安装的脚本文件
# 无需重跑安装器，不动 PATH 和 .bat
Copy-Item "新版dpset.ps1" "$env:USERPROFILE\bin\dpset.ps1" -Force
```

升级后第一次运行 `dpset status` 会自动检测 legacy 状态并初始化。

### 6.2 新机器安装

更新 `Install-Dpset.ps1` 中的内嵌脚本为多提供商版本。安装流程不变。

### 6.3 项目目录迁移

**不受影响。** dpset 的所有运行时文件（脚本、配置、备份）都在 `%USERPROFILE%` 下，与项目目录无关。

## 7. 不改的内容

- `dpset.bat` — 薄封装，逻辑在 `.ps1` 中，无需修改
- `backup.json` 格式 — 保持不变，向后兼容
- `reset` 逻辑 — 从 backup 恢复 + 删除 backup，保持不变
- 安装器文件结构 — `bin/dpset.ps1` + `bin/dpset.bat` + PATH 配置

## 8. 参考资料

- [Claude Code Docs — Environment Variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code Docs — Model Configuration](https://code.claude.com/docs/en/model-config)
- [DeepSeek API Docs — Coding Agents](https://api-docs.deepseek.com/guides/coding_agents)
- [Xiaomi MiMo 开放平台](https://platform.xiaomimimo.com)
- [CSDN: Claude Code 接入小米 MiMo-V2-Pro](https://blog.csdn.net/lljss1980/article/details/159390083)
- [Zed Discussion: MiMo Anthropic Compatibility](https://github.com/zed-industries/zed/discussions/45091)
- [Claude Code Issue #18028: Streaming Stalls](https://github.com/anthropics/claude-code/issues/18028)
