$ErrorActionPreference = "Stop"

$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodePath = if ($env:FEISHU_CODEX_NODE_PATH) { $env:FEISHU_CODEX_NODE_PATH } else { "node" }
$nodeExe = if ($nodePath -ne "node" -and (Test-Path -LiteralPath $nodePath)) { $nodePath } else { "node" }

if ($env:FEISHU_CODEX_NPM_GLOBAL) { $env:Path = $env:Path + ";" + $env:FEISHU_CODEX_NPM_GLOBAL }
$env:LARK_CLI_NO_PROXY = "1"
$env:LANG = "zh_CN.UTF-8"
$env:LC_ALL = "zh_CN.UTF-8"
$env:PYTHONIOENCODING = "utf-8"
$env:NODE_DISABLE_COLORS = "1"
foreach ($name in @(
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "ALL_PROXY",
  "GIT_HTTP_PROXY",
  "GIT_HTTPS_PROXY",
  "http_proxy",
  "https_proxy",
  "all_proxy"
)) {
  Remove-Item "Env:$name" -ErrorAction SilentlyContinue
}

function Test-NodeScriptRunning {
  param([string]$PidFile, [string]$ScriptName)
  # Check pid file first
  if (Test-Path -LiteralPath $PidFile) {
    $rawPid = (Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($rawPid -match '^\d+$') {
      $proc = Get-Process -Id ([int]$rawPid) -ErrorAction SilentlyContinue
      if ($proc) { return $proc }
    }
  }
  # Fallback: scan command lines
  $found = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*feishu-codex-bridge*" -and $_.CommandLine -like "*$ScriptName*" } |
    Select-Object -First 1
  if ($found) {
    Set-Content -LiteralPath $PidFile -Value $found.ProcessId -Encoding ASCII
  }
  return $found
}

# --- Bridge ---
$bridgePidFile = Join-Path $bridgeRoot "bridge.pid"
$existingBridge = Test-NodeScriptRunning -PidFile $bridgePidFile -ScriptName "bridge.js"
if ($existingBridge) {
  $bid = if ($existingBridge.PSObject.Properties.Name -contains "ProcessId") { $existingBridge.ProcessId } else { $existingBridge.Id }
  "existing bridge found: $bid"
} else {
  $bridge = Start-Process `
    -FilePath $nodeExe `
    -ArgumentList @(Join-Path $bridgeRoot "bridge.js") `
    -WorkingDirectory $bridgeRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $bridgeRoot "bridge.stdout.log") `
    -RedirectStandardError (Join-Path $bridgeRoot "bridge.stderr.log") `
    -PassThru
  Set-Content -LiteralPath $bridgePidFile -Value $bridge.Id -Encoding ASCII
  "starting bridge: $($bridge.Id)"
}

# --- Runner ---
$runnerPidFile = Join-Path $bridgeRoot "runner.pid"
$existingRunner = Test-NodeScriptRunning -PidFile $runnerPidFile -ScriptName "runner.js"
if ($existingRunner) {
  $rid = if ($existingRunner.PSObject.Properties.Name -contains "ProcessId") { $existingRunner.ProcessId } else { $existingRunner.Id }
  "existing runner found: $rid"
} else {
  $runner = Start-Process `
    -FilePath $nodeExe `
    -ArgumentList @(Join-Path $bridgeRoot "runner.js") `
    -WorkingDirectory $bridgeRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $bridgeRoot "runner.stdout.log") `
    -RedirectStandardError (Join-Path $bridgeRoot "runner.stderr.log") `
    -PassThru
  Set-Content -LiteralPath $runnerPidFile -Value $runner.Id -Encoding ASCII
  "starting runner: $($runner.Id)"
}
