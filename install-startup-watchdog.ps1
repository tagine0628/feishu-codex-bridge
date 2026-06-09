$ErrorActionPreference = "Stop"

$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$loopScript = Join-Path $bridgeRoot "run-bridge-watchdog-loop.ps1"
$startup = [Environment]::GetFolderPath("Startup")
$cmdPath = Join-Path $startup "FeishuCodexBridgeWatchdog.cmd"

$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& `"$loopScript`""))

$content = @(
  "@echo off",
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encodedCommand"
) -join [Environment]::NewLine

Set-Content -LiteralPath $cmdPath -Value ($content + [Environment]::NewLine) -Encoding ASCII

$existingLoop = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like "*run-bridge-watchdog-loop.ps1*" }

if (-not $existingLoop) {
  Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $loopScript) `
    -WindowStyle Hidden
}

"Installed startup watchdog: $cmdPath"
