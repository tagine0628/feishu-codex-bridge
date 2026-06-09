$ErrorActionPreference = "Stop"

$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodePath = if ($env:FEISHU_CODEX_NODE_PATH) { $env:FEISHU_CODEX_NODE_PATH } else { "node" }
$bridgeScript = Join-Path $bridgeRoot "bridge.js"
$stdoutLog = Join-Path $bridgeRoot "bridge.stdout.log"
$stderrLog = Join-Path $bridgeRoot "bridge.stderr.log"
$pidFile = Join-Path $bridgeRoot "bridge.pid"

function Get-BridgeProcess {
  $byPid = $null
  if (Test-Path -LiteralPath $pidFile) {
    $rawPid = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($rawPid -match '^\d+$') {
      $byPid = Get-Process -Id ([int]$rawPid) -ErrorAction SilentlyContinue
    }
  }

  if ($byPid) {
    return $byPid
  }

  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine -like "*bridge.js*" -and
      $_.CommandLine -like "*feishu-codex-bridge*"
    }
}

$existing = Get-BridgeProcess
if ($existing) {
  $ids = @($existing | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains "ProcessId") {
      $_.ProcessId
    } else {
      $_.Id
    }
  })
  "Bridge already running: $($ids -join ', ')"
  exit 0
}

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

$nodeExe = if ($nodePath -ne "node" -and (Test-Path -LiteralPath $nodePath)) { $nodePath } else { "node" }

$process = Start-Process `
  -FilePath $nodeExe `
  -ArgumentList @($bridgeScript) `
  -WorkingDirectory $bridgeRoot `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdoutLog `
  -RedirectStandardError $stderrLog `
  -PassThru

Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ASCII
"Bridge started: $($process.Id)"

