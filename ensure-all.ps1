$ErrorActionPreference = "Stop"

$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodePath = if ($env:FEISHU_CODEX_NODE_PATH) { $env:FEISHU_CODEX_NODE_PATH } else { "node" }
$nodeExe = if ($nodePath -ne "node" -and (Test-Path -LiteralPath $nodePath)) { $nodePath } else { "node" }

function Get-ProcessFromPidFile {
  param(
    [Parameter(Mandatory = $true)][string]$PidFile,
    [Parameter(Mandatory = $true)][string]$ScriptName
  )

  if (Test-Path -LiteralPath $PidFile) {
    $rawPid = (Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($rawPid -match '^\d+$') {
      $process = Get-Process -Id ([int]$rawPid) -ErrorAction SilentlyContinue
      if ($process) {
        return $process
      }
    }
  }

  $matched = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine -like "*feishu-codex-bridge*" -and
      $_.CommandLine -like "*$ScriptName*"
    } |
    Select-Object -First 1

  if ($matched) {
    Set-Content -LiteralPath $PidFile -Value $matched.ProcessId -Encoding ASCII
  }
  return $matched
}

function Set-BridgeEnvironment {
  $currentPath = [Environment]::GetEnvironmentVariable("Path", "Process")
  if (-not $currentPath) {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
  }
  Remove-Item "Env:Path" -ErrorAction SilentlyContinue
  Remove-Item "Env:PATH" -ErrorAction SilentlyContinue
  if ($env:FEISHU_CODEX_NPM_GLOBAL) { $currentPath = "$currentPath;$env:FEISHU_CODEX_NPM_GLOBAL" }; [Environment]::SetEnvironmentVariable("Path", $currentPath, "Process")
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
}

function Ensure-NodeScript {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ScriptName,
    [Parameter(Mandatory = $true)][string]$PidFile,
    [Parameter(Mandatory = $true)][string]$StdoutLog,
    [Parameter(Mandatory = $true)][string]$StderrLog
  )

  $existing = Get-ProcessFromPidFile -PidFile $PidFile -ScriptName $ScriptName
  if ($existing) {
    $id = if ($existing.PSObject.Properties.Name -contains "ProcessId") { $existing.ProcessId } else { $existing.Id }
    "$Name already running: $id"
    return
  }

  Set-BridgeEnvironment
  $process = Start-Process `
    -FilePath $nodeExe `
    -ArgumentList @(Join-Path $bridgeRoot $ScriptName) `
    -WorkingDirectory $bridgeRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $bridgeRoot $StdoutLog) `
    -RedirectStandardError (Join-Path $bridgeRoot $StderrLog) `
    -PassThru

  Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII
  "$Name started: $($process.Id)"
}

Ensure-NodeScript `
  -Name "Bridge" `
  -ScriptName "bridge.js" `
  -PidFile (Join-Path $bridgeRoot "bridge.pid") `
  -StdoutLog "bridge.stdout.log" `
  -StderrLog "bridge.stderr.log"

Ensure-NodeScript `
  -Name "Runner" `
  -ScriptName "runner.js" `
  -PidFile (Join-Path $bridgeRoot "runner.pid") `
  -StdoutLog "runner.stdout.log" `
  -StderrLog "runner.stderr.log"

