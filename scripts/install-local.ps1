$ErrorActionPreference = "Continue"

function Write-Step {
  param([string]$Message)
  Write-Host "[setup] $Message" -ForegroundColor Cyan
}

function Write-Ok {
  param([string]$Message)
  Write-Host "  OK   $Message" -ForegroundColor Green
}

function Write-WarnLine {
  param([string]$Message)
  Write-Host "  WARN $Message" -ForegroundColor Yellow
}

function Test-RepoRoot {
  $required = @("bridge.js", "runner.js", "bridge.config.example.json")
  $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path (Get-Location) $_)) })
  if ($missing.Count -gt 0) {
    throw "This script must be run from the repository root. Missing: $($missing -join ', ')"
  }
}

function Test-CommandVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string[]]$Args,
    [string]$FallbackMessage
  )

  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    Write-WarnLine "$Name was not found on PATH. $FallbackMessage"
    return
  }

  try {
    $output = & $Name @Args 2>&1 | Select-Object -First 1
    Write-Ok "$Name detected: $output"
  } catch {
    Write-WarnLine "$Name exists but failed to run: $($_.Exception.Message)"
  }
}

Write-Step "Checking repository root"
try {
  Test-RepoRoot
  Write-Ok "Repository root looks correct."
} catch {
  Write-Host "FAIL $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

Write-Step "Checking required tools"
Test-CommandVersion -Name "node" -Args @("--version") -FallbackMessage "Install Node.js before running the bridge."
Test-CommandVersion -Name "git" -Args @("--version") -FallbackMessage "Install Git if you want to clone or version this repository."
Test-CommandVersion -Name "lark-cli" -Args @("--version") -FallbackMessage "You can still set larkCliPath manually in bridge.config.json."
Test-CommandVersion -Name "codex" -Args @("--version") -FallbackMessage "You can still set codexCliPath manually in bridge.config.json."

$configPath = Join-Path (Get-Location) "bridge.config.json"
$examplePath = Join-Path (Get-Location) "bridge.config.example.json"

Write-Step "Preparing local configuration"
if (-not (Test-Path -LiteralPath $configPath)) {
  Copy-Item -LiteralPath $examplePath -Destination $configPath
  Write-Ok "Created bridge.config.json from bridge.config.example.json."
} else {
  Write-Ok "bridge.config.json already exists; leaving it unchanged."
}

Write-Host ""
Write-Host "Edit bridge.config.json before starting the bridge." -ForegroundColor Yellow
Write-Host "You need to fill in:"
Write-Host "  - allowedSenderOpenIds"
Write-Host "  - defaultWorkspace"
Write-Host "  - allowedWorkspaces"
Write-Host "  - queueFolder"
Write-Host "  - logsFolder"
Write-Host "  - larkCliPath"
Write-Host "  - codexCliPath"
Write-Host ""
Write-Host "Do not put Feishu App Secret, GitHub tokens, OpenAI tokens, or any credential in repository files." -ForegroundColor Yellow
Write-Host "Complete authentication yourself with commands such as:"
Write-Host "  lark-cli config init"
Write-Host "  lark-cli auth login"
Write-Host "  codex login"
Write-Host ""
Write-Host "Optional Feishu/Lark Docs output:" -ForegroundColor Cyan
Write-Host "  - To enable on-demand doc creation, set in bridge.config.json:"
Write-Host '    "feishuDocOutput": { "enabled": true, "mode": "on_demand" }'
Write-Host "  - Three modes are supported:"
Write-Host "      off        — never create Feishu/Lark documents, even when enabled = true."
Write-Host "      always     — create a document for every completed task."
Write-Host "      on_demand  — create a document only when the user instruction contains trigger keywords."
Write-Host "  - Default triggerKeywords: 飞书文档, 云文档, 生成文档, 创建文档, 上传飞书, Feishu doc, Feishu docs, doc, docs"
Write-Host "  - The runner creates a Feishu/Lark doc only when the instruction includes keywords like 飞书文档 / 上传飞书 / doc / docs."
Write-Host "  - Example instructions that will trigger doc creation:"
Write-Host "      codex: 帮我整理这个目录，并生成飞书文档"
Write-Host "      codex: summarize this folder and create a Feishu doc"
Write-Host "  - This requires lark-cli auth login for user mode, or Docs creation/edit permissions for bot mode."
Write-Host "  - Do not store App Secret, tokens, or other credentials in this repository."
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit .\bridge.config.json"
Write-Host "  2. Run .\scripts\doctor.ps1"
Write-Host "  3. Run .\start-all.ps1 after doctor passes"
Write-Host "  4. Send a Feishu test message, for example: codex: create a harmless test output under _codex_bridge_outputs"
