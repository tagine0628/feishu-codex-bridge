$ErrorActionPreference = "Stop"
$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
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
Set-Location $bridgeRoot
node .\bridge.js

