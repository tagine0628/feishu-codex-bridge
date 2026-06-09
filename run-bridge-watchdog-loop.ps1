$ErrorActionPreference = "Continue"

$bridgeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ensureScript = Join-Path $bridgeRoot "ensure-all.ps1"
$logPath = Join-Path $bridgeRoot "bridge.watchdog.log"

while ($true) {
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  try {
    $result = & $ensureScript 2>&1
    Add-Content -LiteralPath $logPath -Value "[$timestamp] $result"
  } catch {
    Add-Content -LiteralPath $logPath -Value "[$timestamp] ERROR $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 300
}
