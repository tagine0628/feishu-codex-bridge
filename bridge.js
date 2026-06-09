const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = __dirname;
const configPath = path.join(root, "bridge.config.json");
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const larkCliExe = config.larkCliPath || "lark-cli";

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function nowStamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function appendLog(line) {
  ensureDir(config.logsFolder);
  fs.appendFileSync(
    path.join(config.logsFolder, "bridge.log"),
    `[${new Date().toISOString()}] ${line}\n`,
    "utf8"
  );
}

function bridgeEnv() {
  const env = { ...process.env };
  const pathEntries = [env.Path || env.PATH || ""]; if (path.isAbsolute(larkCliExe)) pathEntries.push(path.dirname(larkCliExe)); env.Path = pathEntries.filter(Boolean).join(";"); delete env.PATH;
  env.LARK_CLI_NO_PROXY = "1";
  env.LANG = "zh_CN.UTF-8";
  env.LC_ALL = "zh_CN.UTF-8";
  env.PYTHONIOENCODING = "utf-8";
  env.NODE_DISABLE_COLORS = "1";
  for (const key of [
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "GIT_HTTP_PROXY",
    "GIT_HTTPS_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy"
  ]) {
    delete env[key];
  }
  return env;
}

function runLark(args) {
  return new Promise((resolve) => {
    const child = spawn(larkCliExe, args, {
      cwd: root,
      env: bridgeEnv(),
      windowsHide: true
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
}

async function reply(messageId, text) {
  if (!messageId) return;
  const result = await runLark([
    "im",
    "+messages-reply",
    "--as",
    "bot",
    "--message-id",
    messageId,
    "--text",
    text,
    "--format",
    "json"
  ]);
  if (result.code !== 0) {
    appendLog(`reply failed code=${result.code} stderr=${result.stderr || result.stdout}`);
  }
}

function stripTrigger(text) {
  for (const prefix of config.ignorePrefixes || []) {
    if (text.startsWith(prefix)) return null;
  }
  if (!config.triggerPrefixes || config.triggerPrefixes.length === 0) {
    return text.trim();
  }
  for (const prefix of config.triggerPrefixes) {
    if (text.startsWith(prefix)) return text.slice(prefix.length).trim();
  }
  return null;
}

function selectWorkspace(text) {
  const normalized = text.toLowerCase();
  for (const workspace of config.allowedWorkspaces) {
    if (normalized.includes(workspace.toLowerCase())) return workspace;
    if (normalized.includes(path.basename(workspace).toLowerCase())) return workspace;
  }
  return config.defaultWorkspace;
}

function isAllowedSender(senderId) {
  return config.allowedSenderOpenIds.includes(senderId);
}

function taskFileName(event) {
  const id = event.event_id || event.message_id || Math.random().toString(36).slice(2);
  return `${nowStamp()}_${id.replace(/[^\w.-]/g, "_")}.json`;
}

function buildTask(event, instruction, workspace) {
  const outputRoot = path.join(workspace, config.outputFolderName);
  return {
    version: 1,
    status: "queued",
    createdAt: new Date().toISOString(),
    source: "feishu",
    senderOpenId: event.sender_id,
    chatId: event.chat_id,
    messageId: event.message_id || event.id,
    eventId: event.event_id,
    originalContent: event.content,
    instruction,
    selectedWorkspace: workspace,
    allowedWorkspaces: config.allowedWorkspaces,
    outputRoot,
    safetyRules: [
      "Only read original files inside allowedWorkspaces.",
      "Do not delete, move, rename, or overwrite existing original files.",
      `Create and edit only files under ${config.outputFolderName}.`,
      "If the task requires destructive or out-of-scope work, ask for confirmation instead of executing.",
      "Preserve the user's natural-language instruction verbatim when handing off to Codex."
    ]
  };
}

async function handleEvent(event) {
  if (!event || event.type !== config.eventKey) return;
  if (!isAllowedSender(event.sender_id)) {
    appendLog(`ignored sender=${event.sender_id || "unknown"} message=${event.message_id || ""}`);
    return;
  }
  if (event.message_type && event.message_type !== "text" && event.message_type !== "post") {
    await reply(event.message_id || event.id, "Codex bridge currently accepts text messages only.");
    return;
  }

  const instruction = stripTrigger(String(event.content || "").trim());
  if (!instruction) {
    appendLog(`ignored non-trigger message=${event.message_id || ""}`);
    return;
  }

  const workspace = selectWorkspace(instruction);
  const outputRoot = path.join(workspace, config.outputFolderName);
  ensureDir(outputRoot);
  ensureDir(config.queueFolder);

  const task = buildTask(event, instruction, workspace);
  const filePath = path.join(config.queueFolder, taskFileName(event));
  fs.writeFileSync(filePath, JSON.stringify(task, null, 2), "utf8");
  appendLog(`queued ${filePath}`);

  await reply(
    event.message_id || event.id,
    `Codex task queued.\nWorkspace: ${workspace}\nOutput root: ${outputRoot}\nRule: original files are read-only; generated files must stay under _codex_bridge_outputs.`
  );}

function startConsumer() {
  ensureDir(config.queueFolder);
  ensureDir(config.logsFolder);
  appendLog("starting bridge");

  const child = spawn(
    larkCliExe,
    ["event", "consume", config.eventKey, "--as", "bot"],
    {
      cwd: root,
      env: bridgeEnv(),
      windowsHide: true
    }
  );

  child.stdin.write("\n");
  child.stderr.on("data", (chunk) => {
    const text = chunk.toString();
    process.stderr.write(text);
    appendLog(`stderr ${text.trim()}`);
  });

  let buffer = "";
  child.stdout.on("data", (chunk) => {
    buffer += chunk.toString();
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      try {
        const event = JSON.parse(line);
        handleEvent(event).catch((error) => appendLog(`handle error ${error.stack || error}`));
      } catch (error) {
        appendLog(`json parse failed ${line}`);
      }
    }
  });

  child.on("close", (code) => {
    appendLog(`consumer exited code=${code}`);
    process.exitCode = code || 0;
  });

  process.on("SIGINT", () => {
    appendLog("SIGINT received");
    child.kill("SIGTERM");
  });
  process.on("SIGTERM", () => {
    appendLog("SIGTERM received");
    child.kill("SIGTERM");
  });
}

startConsumer();



