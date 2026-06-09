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

$bridge = Start-Process `
  -FilePath $nodeExe `
  -ArgumentList @(Join-Path $bridgeRoot "bridge.js") `
  -WorkingDirectory $bridgeRoot `
  -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $bridgeRoot "bridge.stdout.log") `
  -RedirectStandardError (Join-Path $bridgeRoot "bridge.stderr.log") `
  -PassThru

$runner = Start-Process `
  -FilePath $nodeExe `
  -ArgumentList @(Join-Path $bridgeRoot "runner.js") `
  -WorkingDirectory $bridgeRoot `
  -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $bridgeRoot "runner.stdout.log") `
  -RedirectStandardError (Join-Path $bridgeRoot "runner.stderr.log") `
  -PassThru

Set-Content -LiteralPath (Join-Path $bridgeRoot "bridge.pid") -Value $bridge.Id -Encoding ASCII
Set-Content -LiteralPath (Join-Path $bridgeRoot "runner.pid") -Value $runner.Id -Encoding ASCII

"Bridge started: $($bridge.Id)"
"Runner started: $($runner.Id)"

