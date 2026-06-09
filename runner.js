const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = __dirname;
const configPath = path.join(root, "bridge.config.json");
const config = JSON.parse(fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, ""));
const larkCliExe = config.larkCliPath || "lark-cli";
const codexCliExe = config.codexCliPath || "codex";
const maxConcurrency = Math.max(1, Number(config.maxConcurrency || 1));
const scanIntervalMs = Math.max(1, Number(config.runnerScanIntervalSeconds || 10)) * 1000;
const taskTimeoutMs = Math.max(1, Number(config.taskTimeoutMinutes || 30)) * 60 * 1000;

let activeCount = 0;
let scanScheduled = false;

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function appendLog(line) {
  ensureDir(config.logsFolder);
  fs.appendFileSync(
    path.join(config.logsFolder, "runner.log"),
    `[${new Date().toISOString()}] ${line}\n`,
    "utf8"
  );
}

function bridgeEnv() {
  const env = { ...process.env };
  const currentPath = env.Path || env.PATH || "";
  const pathEntries = [currentPath];
  if (path.isAbsolute(larkCliExe)) pathEntries.push(path.dirname(larkCliExe));
  if (path.isAbsolute(codexCliExe)) pathEntries.push(path.dirname(codexCliExe));
  env.Path = pathEntries.filter(Boolean).join(";");
  delete env.PATH;
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

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), "utf8");
}

function resultJsonPath(taskPath) {
  return taskPath.replace(/\.json$/i, ".result.json");
}

function safeBaseName(taskPath) {
  return path.basename(taskPath, ".json").replace(/[^\w.-]/g, "_");
}

function normalizePath(value) {
  return path.resolve(String(value || ""));
}

function isUnder(child, parent) {
  const childPath = normalizePath(child).toLowerCase();
  const parentPath = normalizePath(parent).toLowerCase();
  return childPath === parentPath || childPath.startsWith(parentPath + path.sep.toLowerCase());
}

function isAllowedWorkspace(workspace) {
  return (config.allowedWorkspaces || []).some((allowed) => {
    return normalizePath(workspace).toLowerCase() === normalizePath(allowed).toLowerCase();
  });
}

function hasOutOfScopeAbsolutePath(instruction) {
  const matches = String(instruction || "").match(/[A-Za-z]:\\[^\s"'\uFF0C\u3002\uFF1B;]+/g) || [];
  return matches.some((candidate) => {
    return !(config.allowedWorkspaces || []).some((allowed) => isUnder(candidate, allowed));
  });
}

function requiresConfirmation(task) {
  const instruction = String(task.instruction || "");
  const selectedWorkspace = String(task.selectedWorkspace || "");
  const outputRoot = String(task.outputRoot || "");

  if (!selectedWorkspace || !isAllowedWorkspace(selectedWorkspace)) {
    return "selectedWorkspace is outside allowedWorkspaces";
  }
  if (!outputRoot || !isUnder(outputRoot, selectedWorkspace)) {
    return "outputRoot is outside selectedWorkspace";
  }
  if (path.basename(outputRoot) !== config.outputFolderName) {
    return `outputRoot must be ${config.outputFolderName}`;
  }
  if (hasOutOfScopeAbsolutePath(instruction)) {
    return "instruction references an out-of-scope absolute path";
  }

  const destructivePatterns = [
    /\bdelete\b/i,
    /\bremove\b/i,
    /\bmove\b/i,
    /\brename\b/i,
    /\boverwrite\b/i,
    /\brm\s+-/i,
    /\bdel\s+/i,
    /\berase\s+/i,
    /\u5220\u9664/,
    /\u5220\u6389/,
    /\u79FB\u9664/i,
    /\u79FB\u52A8/i,
    /\u91CD\u547D\u540D/i,
    /\u8986\u76D6/i,
    /\u66FF\u6362\u539F\u6587\u4EF6/i,
    /\u8FD0\u884C.*\u811A\u672C/i,
    /\u6267\u884C.*\u811A\u672C/i,
    /\brun\b.*\bscript\b/i,
    /\.ps1\b/i,
    /\.bat\b/i,
    /\.cmd\b/i
  ];
  if (destructivePatterns.some((pattern) => pattern.test(instruction))) {
    return "instruction appears destructive or asks to run an unknown script";
  }

  return null;
}

function buildPrompt(task) {
  return [
    "You are processing a Feishu Codex bridge task.",
    "",
    "Natural-language instruction:",
    task.instruction || "",
    "",
    "Safety rules:",
    "- Original files inside allowedWorkspaces are read-only.",
    `- Create or edit files only under: ${task.outputRoot}`,
    "- Never delete, move, rename, or overwrite existing original files.",
    "- If the instruction is unclear, destructive, or out of scope, do not execute it; explain what confirmation is needed.",
    "- Preserve the user's natural-language instruction when describing the work.",
    "",
    "Allowed workspaces:",
    ...(task.allowedWorkspaces || config.allowedWorkspaces || []).map((workspace) => `- ${workspace}`),
    "",
    "Return a concise final summary of what you did, where outputs were written, and any limitations."
  ].join("\n");
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
    child.on("error", (error) => resolve({ code: -1, stdout, stderr: String(error) }));
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

function runCodex(task, resultMdPath) {
  return new Promise((resolve) => {
    const prompt = buildPrompt(task);
    const args = [
      "exec",
      "--cd",
      task.selectedWorkspace,
      "--sandbox",
      config.codexSandbox || "workspace-write",
      "--skip-git-repo-check",
      "--output-last-message",
      resultMdPath
    ];

    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let child;
    try {
      child = spawn(codexCliExe, args, {
        cwd: task.selectedWorkspace,
        env: bridgeEnv(),
        windowsHide: true,
        shell: process.platform === "win32" && !codexCliExe.toLowerCase().endsWith(".exe")
      });
    } catch (error) {
      resolve({ code: -1, timedOut, stdout, stderr: `${stderr}\n${error.stack || error}` });
      return;
    }

    child.stdin.write(prompt, "utf8");
    child.stdin.end();

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
    }, taskTimeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ code: -1, timedOut, stdout, stderr: `${stderr}\n${error.stack || error}` });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code: timedOut ? -2 : code, timedOut, stdout, stderr });
    });
  });
}

function summaryFromResult(resultMdPath, fallback) {
  if (fs.existsSync(resultMdPath)) {
    const text = fs.readFileSync(resultMdPath, "utf8").trim();
    if (text) return text.slice(0, 1200);
  }
  return String(fallback || "").trim().slice(0, 1200);
}

function feishuDocOutputConfig() {
  const cfg = config.feishuDocOutput || {};
  const mode = String(cfg.mode || "on_demand").trim();
  const validModes = ["off", "always", "on_demand"];
  if (!validModes.includes(mode)) {
    appendLog(`feishuDocOutput.mode "${mode}" is invalid; falling back to on_demand`);
  }
  return {
    enabled: cfg.enabled === true,
    mode: validModes.includes(mode) ? mode : "on_demand",
    triggerKeywords: Array.isArray(cfg.triggerKeywords) ? cfg.triggerKeywords.filter(Boolean) : [],
    as: cfg.as || "user",
    apiVersion: cfg.apiVersion || "v2",
    docFormat: cfg.docFormat || "markdown",
    parentToken: String(cfg.parentToken || "").trim(),
    parentPosition: String(cfg.parentPosition || "my_library").trim(),
    maxContentChars: Math.max(1000, Number(cfg.maxContentChars || 24000))
  };
}

function shouldCreateFeishuDocForTask(task) {
  const cfg = feishuDocOutputConfig();
  if (!cfg.enabled) return false;

  if (cfg.mode === "off") return false;
  if (cfg.mode === "always") return true;

  // mode === "on_demand" (or unrecognized, already normalised in feishuDocOutputConfig)
  const instruction = String(task.instruction || "").toLowerCase();
  const keywords = cfg.triggerKeywords.length > 0
    ? cfg.triggerKeywords
    : ["飞书文档", "云文档", "生成文档", "创建文档", "上传飞书", "doc", "docs"];

  return keywords.some((keyword) => instruction.includes(keyword.toLowerCase()));
}

function readTextIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return "";
  return fs.readFileSync(filePath, "utf8");
}

function localTimestamp() {
  const pad = (value) => String(value).padStart(2, "0");
  const now = new Date();
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
}

function buildFeishuDocMarkdown(task, resultMdPath, summary) {
  const cfg = feishuDocOutputConfig();
  const resultMarkdown = readTextIfExists(resultMdPath).trim();
  const instruction = String(task.instruction || "").trim();
  const title = `# Codex task result - ${localTimestamp()}`;
  const fullDoc = [
    title,
    "",
    "> Source: Feishu Codex Bridge  ",
    "> Status: completed  ",
    `> Workspace: ${task.selectedWorkspace || ""}  `,
    `> Local result file: ${resultMdPath}`,
    "",
    "## Original instruction",
    "",
    instruction || "(empty)",
    "",
    "## Result",
    "",
    resultMarkdown || summary || "(empty)"
  ].join("\n");

  if (fullDoc.length <= cfg.maxContentChars) return fullDoc;

  return [
    title,
    "",
    "> The result content is long. This Feishu/Lark document keeps a summary only; the complete result is saved in the local Markdown file.",
    "",
    "## Original instruction",
    "",
    instruction || "(empty)",
    "",
    "## Summary",
    "",
    summary || "(empty)",
    "",
    "## Local result file",
    "",
    resultMdPath
  ].join("\n");
}

function runLarkDocsCreate(markdownContent) {
  const cfg = feishuDocOutputConfig();
  const args = [
    "docs",
    "+create",
    "--api-version",
    cfg.apiVersion,
    "--doc-format",
    cfg.docFormat,
    "--content",
    markdownContent,
    "--format",
    "json"
  ];

  if (cfg.as) args.push("--as", cfg.as);
  if (cfg.parentToken) {
    args.push("--parent-token", cfg.parentToken);
  } else if (cfg.parentPosition) {
    args.push("--parent-position", cfg.parentPosition);
  }

  return runLark(args);
}

function findDeep(value, predicate) {
  if (!value || typeof value !== "object") return null;
  if (predicate(value)) return value;
  for (const child of Object.values(value)) {
    const found = findDeep(child, predicate);
    if (found) return found;
  }
  return null;
}

function extractFeishuDocUrl(larkResult) {
  const text = String(larkResult && larkResult.stdout ? larkResult.stdout : "").trim();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    const match = text.match(/https?:\/\/[^\s"']+/);
    return match ? { url: match[0], documentId: null } : { url: null, documentId: null };
  }

  const document =
    parsed?.data?.document ||
    parsed?.document ||
    findDeep(parsed, (node) => typeof node.url === "string" && /\/docx?\//.test(node.url));
  const url = document?.url || parsed?.data?.url || parsed?.url || null;
  const documentId =
    document?.document_id ||
    document?.documentId ||
    document?.token ||
    parsed?.data?.document_id ||
    parsed?.data?.documentId ||
    null;
  return { url, documentId };
}

async function createFeishuDocForTask(task, resultMdPath, summary) {
  const cfg = feishuDocOutputConfig();
  if (!cfg.enabled) return { enabled: false, status: "disabled" };

  try {
    const markdownContent = buildFeishuDocMarkdown(task, resultMdPath, summary);
    const larkResult = await runLarkDocsCreate(markdownContent);
    if (larkResult.code !== 0) {
      return {
        enabled: true,
        mode: cfg.mode,
        status: "failed",
        error: String(larkResult.stderr || larkResult.stdout || `lark-cli exited with code ${larkResult.code}`).slice(0, 2000),
        as: cfg.as
      };
    }

    const extracted = extractFeishuDocUrl(larkResult);
    return {
      enabled: true,
      mode: cfg.mode,
      status: "created",
      url: extracted.url,
      documentId: extracted.documentId,
      as: cfg.as
    };
  } catch (error) {
    return {
      enabled: true,
      mode: cfg.mode,
      status: "failed",
      error: String(error.stack || error).slice(0, 2000),
      as: cfg.as
    };
  }
}

async function markNeedsConfirmation(taskPath, task, reason) {
  const now = new Date().toISOString();
  task.status = "needs_confirmation";
  task.startedAt = task.startedAt || now;
  task.endedAt = now;
  task.confirmationReason = reason;
  writeJson(taskPath, task);

  const result = {
    status: "needs_confirmation",
    startedAt: task.startedAt,
    endedAt: task.endedAt,
    exitCode: null,
    resultMdPath: null,
    reason
  };
  writeJson(resultJsonPath(taskPath), result);
  await reply(task.messageId, `Needs confirmation; Codex was not started.\nReason: ${reason}`);
}

async function processTask(taskPath) {
  let task;
  try {
    task = readJson(taskPath);
  } catch (error) {
    appendLog(`skip unreadable task ${taskPath}: ${error.message}`);
    return;
  }

  if (task.status !== "queued") return;

  const confirmationReason = requiresConfirmation(task);
  if (confirmationReason) {
    appendLog(`needs_confirmation ${taskPath}: ${confirmationReason}`);
    await markNeedsConfirmation(taskPath, task, confirmationReason);
    return;
  }

  const startedAt = new Date().toISOString();
  task.status = "running";
  task.startedAt = startedAt;
  writeJson(taskPath, task);

  const resultDir = path.join(task.outputRoot, "codex_runner_results");
  ensureDir(resultDir);
  const resultMdPath = path.join(resultDir, `${safeBaseName(taskPath)}.md`);
  if (!isUnder(resultMdPath, task.outputRoot)) {
    await markNeedsConfirmation(taskPath, task, "resultMdPath is outside task.outputRoot");
    return;
  }

  appendLog(`running ${taskPath}`);
  await reply(task.messageId, "Codex has started processing this task.");

  const execution = await runCodex(task, resultMdPath);
  const endedAt = new Date().toISOString();
  const completed = execution.code === 0;
  const summary = summaryFromResult(resultMdPath, execution.stderr || execution.stdout);
  const cfg = feishuDocOutputConfig();
  const feishuDoc = completed
    ? (shouldCreateFeishuDocForTask(task)
        ? await createFeishuDocForTask(task, resultMdPath, summary)
        : { enabled: cfg.enabled, mode: cfg.mode, status: "not_requested" })
    : { enabled: cfg.enabled, status: "skipped" };

  task.status = completed ? "completed" : "failed";
  task.endedAt = endedAt;
  task.exitCode = execution.code;
  task.resultMdPath = resultMdPath;
  task.feishuDoc = feishuDoc;
  writeJson(taskPath, task);

  const result = {
    status: task.status,
    startedAt,
    endedAt,
    exitCode: execution.code,
    timedOut: execution.timedOut,
    resultMdPath,
    stdout: execution.stdout.slice(-4000),
    stderr: execution.stderr.slice(-4000),
    feishuDoc
  };
  writeJson(resultJsonPath(taskPath), result);

  let replyText;
  if (!completed) {
    replyText = `Codex task failed.\nExit code: ${execution.code}\nLocal result file: ${resultMdPath}\n\n${summary}`;
  } else if (feishuDoc.enabled && feishuDoc.status === "created") {
    replyText = `Codex task completed.\nFeishu doc: ${feishuDoc.url || "created, but no URL was returned"}\nLocal result file: ${resultMdPath}\n\n${summary}`;
  } else if (feishuDoc.enabled && feishuDoc.status === "failed") {
    replyText = `Codex task completed, but Feishu doc creation failed.\nLocal result file: ${resultMdPath}\nReason: ${feishuDoc.error || "unknown error"}\n\n${summary}`;
  } else {
    replyText = `Codex task completed.\nLocal result file: ${resultMdPath}\n\n${summary}`;
  }

  await reply(task.messageId, replyText);
  appendLog(`${task.status} ${taskPath} code=${execution.code} feishuDoc=${feishuDoc.status || "disabled"}`);
}

function handleTaskError(taskPath, error) {
  appendLog(`task error ${taskPath}: ${error.stack || error}`);
  try {
    const task = readJson(taskPath);
    const endedAt = new Date().toISOString();
    task.status = "failed";
    task.endedAt = endedAt;
    task.exitCode = -1;
    task.failureReason = String(error.stack || error);
    writeJson(taskPath, task);
    writeJson(resultJsonPath(taskPath), {
      status: "failed",
      startedAt: task.startedAt || null,
      endedAt,
      exitCode: -1,
      resultMdPath: task.resultMdPath || null,
      stderr: task.failureReason.slice(-4000)
    });
    reply(task.messageId, `Codex task failed.\nReason: ${String(error.message || error).slice(0, 800)}`).catch((replyError) => {
      appendLog(`failure reply error ${replyError.stack || replyError}`);
    });
  } catch (writeError) {
    appendLog(`failed to mark task failed ${taskPath}: ${writeError.stack || writeError}`);
  }
}

function queuedTaskPaths() {
  ensureDir(config.queueFolder);
  return fs
    .readdirSync(config.queueFolder)
    .filter((name) => name.endsWith(".json") && !name.endsWith(".result.json"))
    .map((name) => path.join(config.queueFolder, name))
    .sort();
}

async function scanQueue() {
  if (activeCount >= maxConcurrency) return;
  for (const taskPath of queuedTaskPaths()) {
    if (activeCount >= maxConcurrency) break;
    let task;
    try {
      task = readJson(taskPath);
    } catch {
      continue;
    }
    if (task.status !== "queued") continue;

    activeCount += 1;
    processTask(taskPath)
      .catch((error) => handleTaskError(taskPath, error))
      .finally(() => {
        activeCount -= 1;
        scheduleScan();
      });
    break;
  }
}

function scheduleScan() {
  if (scanScheduled) return;
  scanScheduled = true;
  setTimeout(() => {
    scanScheduled = false;
    scanQueue().catch((error) => appendLog(`scan error ${error.stack || error}`));
  }, 100);
}

function startWatcher() {
  ensureDir(config.queueFolder);
  ensureDir(config.logsFolder);
  appendLog("starting runner");
  scanQueue().catch((error) => appendLog(`initial scan error ${error.stack || error}`));

  fs.watch(config.queueFolder, { persistent: true }, () => {
    scheduleScan();
  });

  setInterval(() => {
    scanQueue().catch((error) => appendLog(`interval scan error ${error.stack || error}`));
  }, scanIntervalMs);
}

startWatcher();
