# Feishu Codex Bridge

一个将飞书 / Lark 机器人消息接入本机 Codex CLI 的本地桥接工具。

它可以实时接收飞书消息，将安全任务写入本地 JSON 队列，并由本机常驻 `runner.js` 在发现 `queued` 任务时才启动 `codex exec` 执行。没有任务时不会运行 Codex heartbeat 巡检，也不会额外消耗 Codex 上下文。

## 架构

```text
Feishu message
  -> bridge.js 实时接收飞书事件
  -> bridge.js 将任务 JSON 写入 bridge_queue
  -> runner.js 通过 fs.watch 和兜底扫描监听 bridge_queue
  -> runner.js 只对 status=queued 的任务启动 codex exec
  -> 结果写入 _codex_bridge_outputs
  -> 如果存在 messageId，runner 将结果回复到飞书
```

## 模块说明

### bridge.js

`bridge.js` 只负责入口层：

* 通过 `lark-cli event consume` 监听飞书 / Lark 事件；
* 校验 `allowedSenderOpenIds`；
* 根据 `triggerPrefixes` 过滤消息；
* 将任务 JSON 写入 `queueFolder`；
* 回复“任务已入队”。

`bridge.js` 不调用 Codex，也不执行任务。

### runner.js

`runner.js` 是本地常驻 Node 进程：

* 启动时扫描 `queueFolder`；
* 使用 `fs.watch` 监听 `queueFolder`；
* 每隔 `runnerScanIntervalSeconds` 秒执行一次兜底扫描；
* 只处理 `status = queued` 的任务 JSON；
* 执行前将任务状态改为 `running`，避免重复执行；
* 默认一次只处理一个任务；
* 只有存在真实任务时才启动 `codex exec`；
* 通过 stdin 向 Codex 传入 prompt，而不是通过 shell 参数传入；
* 写入 `<task>.result.json` 和 Markdown 结果文件；
* 成功时将任务标记为 `completed`，失败时标记为 `failed`；
* 对删除、移动、重命名、覆盖原文件、越权路径、未知脚本执行等危险请求，标记为 `needs_confirmation`，不自动调用 Codex。

## 触发前缀

默认只有以下前缀开头的飞书消息会进入任务队列：

* `codex:`
* `Codex:` 或 `Codex：`
* `execute:` 或 `执行:`

你可以在 `bridge.config.json` 中自行修改。

## 安全边界

本项目的安全模型是：

* 允许工作区内的原始文件默认只读；
* 新生成或修改的文件必须放在 `_codex_bridge_outputs` 下；
* 不自动执行破坏性操作；
* 删除、移动、重命名、覆盖原文件、访问越权路径、执行未知脚本等请求会被标记为 `needs_confirmation`；
* `resultMdPath` 必须位于任务自己的 `outputRoot` 下。

## 使用 Codex 一句话辅助安装

这不是完全无人值守的一键安装器。你仍然需要自己创建飞书 / Lark 应用、完成 `lark-cli` 授权、完成 Codex 登录，并提供本机工作区路径和允许发送者的 `open_id`。

你可以把下面这段 prompt 交给另一个 Codex 会话：

```text
Clone this repository and help me install Feishu Codex Bridge on Windows.

Repository:
https://github.com/<your-github-username>/feishu-codex-bridge

Rules:
- Do not ask for or store my GitHub password, GitHub token, Feishu App Secret, OpenAI token, or any credential.
- Let me complete browser/CLI authentication myself.
- Run scripts/install-local.ps1 first.
- Help me fill bridge.config.json using my local paths and Feishu open_id.
- Run scripts/doctor.ps1.
- Start bridge and runner with start-all.ps1 only after doctor passes.
- Do not modify original files outside _codex_bridge_outputs.
```

普通本地安装流程：

```powershell
.\scripts\install-local.ps1
.\scripts\doctor.ps1
.\start-all.ps1
```

## 安装准备

需要提前安装：

* Node.js
* `lark-cli`
* OpenAI Codex CLI

先运行本地安装引导：

```powershell
.\scripts\install-local.ps1
```

如果安装脚本还没有生成配置文件，也可以手动复制示例配置：

```powershell
Copy-Item bridge.config.example.json bridge.config.json
```

然后编辑 `bridge.config.json`，填写你自己的配置：

```text
allowedSenderOpenIds
allowedWorkspaces
defaultWorkspace
queueFolder
logsFolder
larkCliPath
codexCliPath
```

示例路径格式：

```text
F:\your_workspace
F:\another_allowed_workspace
E:\optional_workspace
F:\path\to\lark-cli.exe
F:\path\to\codex.cmd
```

## 配置说明

主要字段：

* `triggerPrefixes`：触发任务入队的飞书消息前缀。
* `ignorePrefixes`：明确忽略的消息前缀。
* `allowedSenderOpenIds`：允许发起任务的飞书 / Lark 用户。
* `allowedWorkspaces`：Codex 可访问的工作区。
* `queueFolder`：本地任务队列目录。
* `logsFolder`：bridge 和 runner 的日志目录。
* `larkCliPath`：`lark-cli` 路径。
* `codexCliPath`：`codex` 或 `codex.cmd` 路径。
* `maxConcurrency`：默认 `1`。
* `taskTimeoutMinutes`：默认 `30`。
* `codexSandbox`：默认 `workspace-write`。
* `runnerScanIntervalSeconds`：默认 `10`。

## 验证与启动

启动前建议先运行诊断：

```powershell
.\scripts\doctor.ps1
```

## 启动

一次性启动 bridge 和 runner：

```powershell
.\start-all.ps1
```

检查并确保 bridge 和 runner 都在运行：

```powershell
.\ensure-all.ps1
```

安装当前用户开机自恢复 watchdog：

```powershell
.\install-startup-watchdog.ps1
```

watchdog 会循环调用 `ensure-all.ps1`，因此 bridge 和 runner 都会被保活。

## 停止

停止 bridge、runner、watchdog，并移除开机启动项：

```powershell
.\uninstall-startup-watchdog.ps1
```

## 输出目录

任务队列写入：

```text
<your_workspace>\_codex_bridge_outputs\bridge_queue
```

Codex Markdown 结果写入：

```text
<task.outputRoot>\codex_runner_results\<task>.md
```

运行日志写入：

```text
<your_workspace>\_codex_bridge_outputs\bridge_logs\bridge.log
<your_workspace>\_codex_bridge_outputs\bridge_logs\runner.log
<repo_dir>\bridge.watchdog.log
```

## GitHub 提交注意事项

不要提交本地运行文件或私有配置：

* `bridge.config.json`
* `*.pid`
* `*.log`
* `*.stdout.log`
* `*.stderr.log`
* `_codex_bridge_outputs/`
* 任务 JSON 文件
* `.result.json` 文件
* `node_modules/`

## 项目定位

这个项目不是 Codex 移动端的替代品，而是一个低网络门槛的本地 AI Agent 任务入口。

手机端只需要能发送飞书消息；真正访问本机文件、运行 Codex CLI、写入结果的是电脑端。它适合以下场景：

* 手机端无法稳定访问 Codex / ChatGPT；
* 想用飞书作为轻量任务入口；
* 想远程调度本机 Codex 处理文件任务；
* 想保留本地任务队列、日志、状态和安全边界；
* 想把企业 IM 变成本地 AI Agent 的任务投递层。
