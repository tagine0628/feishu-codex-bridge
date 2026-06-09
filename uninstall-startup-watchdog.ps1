$ErrorActionPreference = "Continue"

$startup = [Environment]::GetFolderPath("Startup")
$cmdPath = Join-Path $startup "FeishuCodexBridgeWatchdog.cmd"

if (Test-Path -LiteralPath $cmdPath) {
  Remove-Item -LiteralPath $cmdPath -Force
}

$bridgeProcesses = Get-CimInstance Win32_Process -Filter "Name = 'node.exe' OR Name = 'lark-cli.exe' OR Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $_.CommandLine -like "*feishu-codex-bridge*" -or
    $_.CommandLine -like "*run-bridge-watchdog-loop.ps1*" -or
    $_.CommandLine -like "*event consume im.message.receive_v1*" -or
    $_.CommandLine -like "*runner.js*"
  }

foreach ($process in $bridgeProcesses) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
}

"Removed startup watchdog and stopped bridge-related processes."
