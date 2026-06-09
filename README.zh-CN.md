[English README](./README.md)

# Feishu Codex Bridge

Feishu Codex Bridge 是一个把飞书 / Lark 机器人消息转成本机 Codex CLI 任务的本地桥接工具，通过事件触发队列让 Codex 只在有真实任务时运行。

## 使用 Codex 一句话辅助安装

这不是完全无人值守安装。你仍然需要自己创建飞书 / Lark 应用，完成 `lark-cli` 授权，完成 Codex 登录，并填写本机工作区路径和允许触发任务的用户 `open_id`。

把下面这段 prompt 复制给 Codex：

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

## 本地快速命令

在仓库根目录中运行：

```powershell
.\scripts\install-local.ps1
.\scripts\doctor.ps1
.\start-all.ps1
```

## 架构

整体流程是：

```text
飞书 / Lark 消息
  -> bridge.js
  -> bridge_queue/*.json
  -> runner.js
  -> codex exec
  -> 结果 markdown + result json
  -> 飞书 / Lark 回复
```

Codex 不再作为定时 heartbeat 巡检器使用。`runner.js` 是普通 Node.js 常驻进程，监听本地队列，只有发现真实 queued 任务时才启动 `codex exec`。

## 模块说明

- `bridge.js`：监听飞书 / Lark 事件，校验允许的发送人和触发前缀，写入任务 JSON，并回复“已入队”。
- `runner.js`：监听 `bridge_queue`，把 queued 任务标记为 running，调用 `codex exec`，写入结果，并回复最终摘要。
- `start-all.ps1`：同时启动 bridge 和 runner，并分别写日志。
- `ensure-all.ps1`：检查 pid 文件，发现 bridge 或 runner 未运行时自动拉起。
- `scripts/install-local.ps1`：本地安装引导和依赖检查。
- `scripts/doctor.ps1`：检查配置、CLI、语法、目录和进程状态。
- `bridge.config.example.json`：公开配置模板。复制为 `bridge.config.json` 后填写私有配置。

## 触发前缀

默认触发前缀是：

```json
["codex:", "Codex:", "Codex：", "execute:", "执行:"]
```

只有来自允许用户、并匹配这些前缀之一的消息会被写入队列。

## 安全边界

默认安全边界比较保守：

- 任务 prompt 会把原始工作区文件视为只读。
- 生成结果应写入 `_codex_bridge_outputs`。
- 涉及删除、移动、重命名、覆盖原文件、越权路径或运行未知脚本的任务，会先标记为 `needs_confirmation`，不会直接调用 Codex。
- 私有配置、队列、日志、pid、运行结果和本地凭证都不会提交进 Git。

## 安装准备

1. 安装 Node.js、Git、`lark-cli` 和 Codex CLI。
2. 在飞书 / Lark 开放平台创建自己的应用。
3. 自行完成 `lark-cli` 配置和授权：

```powershell
lark-cli config init
lark-cli auth login
```

4. 自行完成 Codex 登录。
5. 创建本地私有配置：

```powershell
Copy-Item bridge.config.example.json bridge.config.json
```

6. 编辑 `bridge.config.json`，填入自己的本机路径和允许发送人的 `open_id`。

## 配置说明

私有配置 `bridge.config.json` 至少需要包含：

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

不要提交 `bridge.config.json`。

## 验证与启动

先运行安装引导：

```powershell
.\scripts\install-local.ps1
```

再运行诊断：

```powershell
.\scripts\doctor.ps1
```

doctor 通过后再启动：

```powershell
.\start-all.ps1
```

## 启动

启动 bridge 和 runner：

```powershell
.\start-all.ps1
```

也可以使用 watchdog：

```powershell
.\ensure-all.ps1
```

## 停止

停止与本项目对应的 Node.js 进程。停止前建议查看命令行，避免误杀其他 Node.js 进程。

## 输出目录

常见运行输出包括：

- `bridge_queue/*.json`：队列任务文件。
- `codex_runner_results/*.md`：Codex 最终回复 markdown。
- `*.result.json`：执行元数据。
- `bridge_logs/`：bridge 和 runner 日志。

这些运行态文件都应被 Git 排除。

## GitHub 提交注意事项

提交或发布前，确认这些内容不要进入 Git：

- `bridge.config.json`
- `.env` 或 token 文件
- `*.pid`
- `*.log`
- `_codex_bridge_outputs/`
- `bridge_queue/`
- `bridge_logs/`
- `codex_runner_results/`
- 包含真实 `open_id`、`messageId`、`chatId` 或本机路径的任务 JSON

公开示例只使用 `bridge.config.example.json`。

## 项目定位

这个项目适合把飞书里的自然语言任务转成本机 Codex 可执行任务，尤其适合需要保留本地文件安全边界、异步处理科研资料、整理文档、跑数据清洗和生成结果摘要的场景。