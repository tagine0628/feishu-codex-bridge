# Feishu Codex Bridge

A local bridge that connects Feishu/Lark bot messages to Codex CLI through an event-triggered queue runner.

The bridge receives Feishu messages in real time, writes safe task JSON files into a local queue, and a local runner starts `codex exec` only when a queued task exists. There is no Codex heartbeat polling loop.

## Architecture

```text
Feishu message
  -> bridge.js receives events in real time
  -> bridge.js writes a task JSON into bridge_queue
  -> runner.js watches bridge_queue with fs.watch and fallback scans
  -> runner.js starts codex exec only for status=queued tasks
  -> results are written under _codex_bridge_outputs
  -> runner replies to Feishu when messageId is present
```

## Modules

### bridge.js

`bridge.js` is the ingress layer only:

- listens to Feishu/Lark events via `lark-cli event consume`;
- checks `allowedSenderOpenIds`;
- filters messages by `triggerPrefixes`;
- writes task JSON files into `queueFolder`;
- replies that the task has been queued.

It does not call Codex and does not execute tasks.

### runner.js

`runner.js` is a local long-running Node process:

- scans `queueFolder` on startup;
- watches `queueFolder` with `fs.watch`;
- runs a fallback scan every `runnerScanIntervalSeconds` seconds;
- processes only task JSON files with `status = queued`;
- changes a task to `running` before execution to avoid duplicates;
- runs one task at a time by default;
- starts `codex exec` only when a real queued task exists;
- sends the Codex prompt through stdin, not through shell arguments;
- writes `<task>.result.json` and a Markdown result file;
- marks success as `completed`, failure as `failed`;
- marks destructive or out-of-scope requests as `needs_confirmation` without calling Codex.

## Trigger Prefixes

By default, only messages starting with one of these prefixes are queued:

- `codex:`
- `Codex:` or `Codex：`
- `execute:` or `执行:`

You can change this in `bridge.config.json`.

## Safety Boundary

The intended safety model is:

- original files in allowed workspaces are read-only;
- generated or edited files must be placed under `_codex_bridge_outputs`;
- destructive operations are not executed automatically;
- deleting, moving, renaming, overwriting original files, out-of-scope paths, and unknown script execution are marked as `needs_confirmation`;
- `resultMdPath` must be under the task's `outputRoot`.

## Setup

Install prerequisites:

- Node.js
- `lark-cli`
- OpenAI Codex CLI

Copy the example config:

```powershell
Copy-Item bridge.config.example.json bridge.config.json
```

Then edit `bridge.config.json` and fill in your own values:

```text
allowedSenderOpenIds
allowedWorkspaces
defaultWorkspace
queueFolder
logsFolder
larkCliPath
codexCliPath
```

Use placeholder-style paths such as:

```text
F:\your_workspace
F:\another_allowed_workspace
E:\optional_workspace
F:\path\to\lark-cli.exe
F:\path\to\codex.cmd
```

## Configuration

Important fields:

- `triggerPrefixes`: Feishu message prefixes that create tasks.
- `ignorePrefixes`: prefixes that are intentionally ignored.
- `allowedSenderOpenIds`: Feishu/Lark users allowed to enqueue tasks.
- `allowedWorkspaces`: workspaces Codex may work inside.
- `queueFolder`: local queue directory.
- `logsFolder`: bridge and runner log directory.
- `larkCliPath`: path to `lark-cli`.
- `codexCliPath`: path to `codex` or `codex.cmd`.
- `maxConcurrency`: default `1`.
- `taskTimeoutMinutes`: default `30`.
- `codexSandbox`: default `workspace-write`.
- `runnerScanIntervalSeconds`: default `10`.

## Start

Start bridge and runner once:

```powershell
.\start-all.ps1
```

Ensure both processes are running:

```powershell
.\ensure-all.ps1
```

Install the user startup watchdog:

```powershell
.\install-startup-watchdog.ps1
```

The watchdog calls `ensure-all.ps1`, so both bridge and runner are kept alive.

## Stop

Stop bridge, runner, and watchdog, and remove the startup entry:

```powershell
.\uninstall-startup-watchdog.ps1
```

## Outputs

Queue files are written to:

```text
<your_workspace>\_codex_bridge_outputs\bridge_queue
```

Codex Markdown results are written to:

```text
<task.outputRoot>\codex_runner_results\<task>.md
```

Runtime logs are written to:

```text
<your_workspace>\_codex_bridge_outputs\bridge_logs\bridge.log
<your_workspace>\_codex_bridge_outputs\bridge_logs\runner.log
<repo_dir>\bridge.watchdog.log
```

## GitHub Hygiene

Do not commit local runtime files or private config:

- `bridge.config.json`
- `*.pid`
- `*.log`
- `*.stdout.log`
- `*.stderr.log`
- `_codex_bridge_outputs/`
- task JSON files
- `.result.json` files
- `node_modules/`
