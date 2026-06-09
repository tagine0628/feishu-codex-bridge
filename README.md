[中文文档](./README.zh-CN.md)

# Feishu Codex Bridge

Feishu Codex Bridge turns Feishu/Lark bot messages into local Codex CLI tasks through a safe event-triggered queue runner.

## One-prompt setup with Codex

This is not a fully unattended installer. You still need to create your own Feishu/Lark app, complete `lark-cli` authentication, complete Codex login, and provide your local workspace paths and allowed sender `open_id`.

Copy this prompt into Codex:

```text
Clone this repository and help me install Feishu Codex Bridge on Windows.

Repository:
https://github.com/tagine0628/feishu-codex-bridge

Rules:
- Do not ask for or store my GitHub password, GitHub token, Feishu App Secret, OpenAI token, or any credential.
- Let me complete browser/CLI authentication myself.
- Run scripts/install-local.ps1 first.
- Help me fill bridge.config.json using my local paths and Feishu open_id.
- Run scripts/doctor.ps1.
- Start bridge and runner with start-all.ps1 only after doctor passes.
- Do not modify original files outside _codex_bridge_outputs.
```

## Quick local commands

For a normal local setup, run these from the repository root:

```powershell
.\scripts\install-local.ps1
.\scripts\doctor.ps1
.\start-all.ps1
```

## Architecture

The bridge has two long-running local processes:

```text
Feishu/Lark message
  -> bridge.js
  -> bridge_queue/*.json
  -> runner.js
  -> codex exec
  -> result markdown + result json
  -> Feishu/Lark reply
```

Codex is no longer used as a timer-based heartbeat poller. `runner.js` is a plain Node.js process that watches the local queue and starts `codex exec` only when a real queued task exists.

## Modules

- `bridge.js`: listens to Feishu/Lark events, checks allowed senders and trigger prefixes, writes task JSON files, and replies that the task was queued.
- `runner.js`: watches `bridge_queue`, marks queued tasks as running, calls `codex exec`, writes results, and replies with a final summary.
- `start-all.ps1`: starts both bridge and runner and writes separate logs.
- `ensure-all.ps1`: checks pid files and restarts missing bridge/runner processes.
- `scripts/install-local.ps1`: local installation guide and dependency check.
- `scripts/doctor.ps1`: configuration, CLI, syntax, folder, and process diagnostics.
- `bridge.config.example.json`: public configuration template. Copy it to `bridge.config.json` and fill your private values.

## Trigger Prefixes

Default trigger prefixes are:

```json
["codex:", "Codex:", "Codex：", "execute:", "执行:"]
```

Only messages from allowed senders and matching one of these prefixes are queued.

## Safety Boundary

The default safety model is intentionally conservative:

- Original workspace files are treated as read-only by the task prompt.
- Generated outputs should stay under `_codex_bridge_outputs`.
- Tasks involving deletion, moving, renaming, overwriting original files, out-of-scope paths, or unknown script execution are marked `needs_confirmation` before Codex is called.
- Private config, queue files, logs, pid files, runtime outputs, and local credentials are ignored by Git.

## Setup

1. Install Node.js, Git, `lark-cli`, and Codex CLI.
2. Create your Feishu/Lark app in the Feishu/Lark developer console.
3. Complete `lark-cli` setup yourself:

```powershell
lark-cli config init
lark-cli auth login
```

4. Complete Codex login yourself.
5. Create local config:

```powershell
Copy-Item bridge.config.example.json bridge.config.json
```

6. Edit `bridge.config.json` with your own local values.

## Configuration

The private `bridge.config.json` should define at least:

```json
{
  "allowedSenderOpenIds": ["ou_xxx_replace_with_allowed_user_open_id"],
  "triggerPrefixes": ["codex:", "Codex:", "Codex：", "execute:", "执行:"],
  "defaultWorkspace": "F:\\your_workspace",
  "allowedWorkspaces": [
    "F:\\your_workspace",
    "F:\\another_allowed_workspace",
    "E:\\optional_workspace"
  ],
  "queueFolder": "F:\\your_workspace\\_codex_bridge_outputs\\bridge_queue",
  "logsFolder": "F:\\your_workspace\\_codex_bridge_outputs\\bridge_logs",
  "larkCliPath": "F:\\path\\to\\lark-cli.exe",
  "codexCliPath": "codex",
  "maxConcurrency": 1,
  "taskTimeoutMinutes": 30,
  "codexSandbox": "workspace-write",
  "runnerScanIntervalSeconds": 10
}
```

Do not commit `bridge.config.json`.

## Validate and Start

Run the installer helper first:

```powershell
.\scripts\install-local.ps1
```

Then run diagnostics:

```powershell
.\scripts\doctor.ps1
```

Start bridge and runner only after doctor checks pass:

```powershell
.\start-all.ps1
```

## Start

Start both bridge and runner:

```powershell
.\start-all.ps1
```

Or use the watchdog:

```powershell
.\ensure-all.ps1
```

## Stop

Stop the Node.js processes that correspond to this bridge/runner installation. Do not kill unrelated Node.js processes unless you have checked their command line.

## Outputs

Typical runtime outputs are:

- `bridge_queue/*.json`: queued task files.
- `codex_runner_results/*.md`: final Codex response markdown.
- `*.result.json`: execution metadata.
- `bridge_logs/`: bridge and runner logs.

These runtime files are excluded from Git.

## GitHub Hygiene

Before publishing or committing, make sure these never enter Git:

- `bridge.config.json`
- `.env` or token files
- `*.pid`
- `*.log`
- `_codex_bridge_outputs/`
- `bridge_queue/`
- `bridge_logs/`
- `codex_runner_results/`
- task JSON files containing real `open_id`, `messageId`, `chatId`, or local paths

Use `bridge.config.example.json` for public examples only.