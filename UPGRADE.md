# dpset v2 upgrade notes

This upgrade turns `dpset` into a Claude Code provider switcher for DeepSeek and
Xiaomi MiMo.

## What changes

- `dpset status` now checks Process, User, and Machine environment scopes.
- `dpset on deepseek` writes the DeepSeek configuration to User environment.
- `dpset on mimo` writes the Xiaomi MiMo Token Plan SGP configuration to User
  environment.
- `dpset on mimo-token-cn|sgp|ams` writes a specific MiMo Token Plan region.
- `dpset on mimo-paygo` writes the Xiaomi MiMo pay-as-you-go API endpoint.
- `dpset test <provider>` validates a provider endpoint and key without changing
  User environment.
- Existing `%USERPROFILE%\.dpset\backup.json` is preserved and is not overwritten.
- `ANTHROPIC_API_KEY` is cleared during provider switches to avoid auth conflicts.

## Overwrite an existing install

From this repository directory, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Dpset.ps1
```

The installer overwrites:

```text
%USERPROFILE%\bin\dpset.ps1
%USERPROFILE%\bin\dpset.bat
```

It preserves:

```text
%USERPROFILE%\.dpset\backup.json
```

Close all current Claude Code and terminal sessions, open a new PowerShell
window, then run:

```powershell
dpset status
```

To switch providers:

```powershell
dpset on deepseek
dpset on mimo
```

Each switch prompts for the provider API key. The key is saved to User
environment as `ANTHROPIC_AUTH_TOKEN` so that newly opened Claude Code sessions
can use it. It is not written to dpset state files.

## Recommended safe flow

```powershell
dpset status
dpset test mimo
dpset on mimo
```

`mimo` is an alias for `mimo-token-sgp`. If your Token Plan console shows a
different region, use that exact provider:

```powershell
dpset test mimo-token-cn
dpset on mimo-token-cn
```

or:

```powershell
dpset test mimo-token-ams
dpset on mimo-token-ams
```

Token Plan keys usually start with `tp-`; those keys should not be used with
`mimo-paygo`.

After `dpset on mimo`, close the current terminal and start a new one before
running:

```powershell
claude
```

To switch back:

```powershell
dpset test deepseek
dpset on deepseek
```

Again, restart the terminal before launching Claude Code.

## Rollback

To remove the active provider configuration but keep the original backup:

```powershell
dpset off
```

To restore the pre-dpset User environment from the original backup:

```powershell
dpset reset
```
