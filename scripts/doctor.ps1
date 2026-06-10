$ErrorActionPreference = "Continue"
$script:Failures = 0
$script:Warnings = 0

function Pass {
  param([string]$Message)
  Write-Host "PASS $Message" -ForegroundColor Green
}

function Warn {
  param([string]$Message)
  $script:Warnings += 1
  Write-Host "WARN $Message" -ForegroundColor Yellow
}

function Fail {
  param([string]$Message)
  $script:Failures += 1
  Write-Host "FAIL $Message" -ForegroundColor Red
}

function Info {
  param([string]$Message)
  Write-Host "INFO $Message" -ForegroundColor Cyan
}

function Test-PlaceholderPath {
  param([string]$Path)
  if (-not $Path) { return $false }
  return $Path -match '<.*>' -or
    $Path -match 'your_workspace' -or
    $Path -match 'another_allowed_workspace' -or
    $Path -match 'optional_allowed_workspace' -or
    $Path -match 'path\\to'
}

function Test-FileExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) { Pass "$Path exists" } else { Fail "$Path is missing" }
}

function Resolve-ExecutableCandidate {
  param(
    [string]$Name,
    [string]$ConfiguredPath
  )

  if ($ConfiguredPath -and $ConfiguredPath.Trim().Length -gt 0 -and -not (Test-PlaceholderPath $ConfiguredPath)) {
    return $ConfiguredPath
  }
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $Name }
  return $null
}

function Test-ExecutableVersion {
  param(
    [string]$Name,
    [string]$ConfiguredPath
  )

  $candidate = Resolve-ExecutableCandidate -Name $Name -ConfiguredPath $ConfiguredPath
  if (-not $candidate) {
    Fail "$Name is not on PATH and no configured path was provided."
    return
  }

  if ($candidate -ne $Name -and -not (Test-Path -LiteralPath $candidate)) {
    Fail "$Name configured path does not exist: $candidate"
    return
  }

  try {
    $output = & $candidate --version 2>&1 | Select-Object -First 1
    Pass "$Name version check succeeded: $output"
  } catch {
    Fail "$Name failed to run from '$candidate': $($_.Exception.Message)"
  }
}

function Test-FeishuDocOutput {
  param($Config)

  if (-not $Config.feishuDocOutput -or $Config.feishuDocOutput.enabled -ne $true) {
    Info "feishuDocOutput is disabled; skipping Feishu/Lark Docs checks."
    return
  }

  Info "feishuDocOutput is enabled; checking Docs prerequisites without creating a document."

  $mode = if ($Config.feishuDocOutput.mode) { [string]$Config.feishuDocOutput.mode } else { "on_demand" }
  $validModes = @("off", "always", "on_demand")
  if ($validModes -contains $mode) {
    Pass "feishuDocOutput.mode is valid: $mode"
  } else {
    Fail "feishuDocOutput.mode must be one of: off, always, on_demand. Got: '$mode'"
  }

  if ($mode -eq "on_demand") {
    $keywords = $Config.feishuDocOutput.triggerKeywords
    if ($keywords -and $keywords.Count -gt 0) {
      Pass "feishuDocOutput.triggerKeywords is non-empty: $($keywords -join ', ')"
    } else {
      Warn "feishuDocOutput.triggerKeywords is empty; on_demand mode will use built-in defaults (飞书文档, 云文档, 生成文档, 创建文档, 上传飞书, doc, docs)"
    }
    Info "on_demand mode: a Feishu/Lark document will only be created when the user instruction contains one of the trigger keywords."
  }

  if ($mode -eq "off") {
    Info "feishuDocOutput.mode is 'off'; no Feishu/Lark document will ever be created even though feishuDocOutput.enabled = true."
  }

  $as = if ($Config.feishuDocOutput.as) { [string]$Config.feishuDocOutput.as } else { "user" }
  if ($as -ne "user" -and $as -ne "bot") {
    Fail "feishuDocOutput.as must be 'user' or 'bot'."
  } else {
    Pass "feishuDocOutput.as is valid: $as"
  }

  if ($as -eq "user") {
    Info "user mode requires you to complete: lark-cli auth login"
  } else {
    Info "bot mode requires the Feishu/Lark app to have Docs create/edit permissions and user authorization if required."
  }

  $candidate = Resolve-ExecutableCandidate -Name "lark-cli" -ConfiguredPath $Config.larkCliPath
  if (-not $candidate) {
    Fail "lark-cli is required when feishuDocOutput.enabled = true."
    return
  }
  if ($candidate -ne "lark-cli" -and -not (Test-Path -LiteralPath $candidate)) {
    Fail "lark-cli configured path does not exist: $candidate"
    return
  }

  try {
    $help = & $candidate docs +create --help 2>&1 | Select-Object -First 5
    if ($LASTEXITCODE -eq 0 -or $help) {
      Pass "lark-cli docs +create --help is available"
    } else {
      Fail "lark-cli docs +create --help did not return help output"
    }
  } catch {
    Fail "lark-cli docs +create --help failed: $($_.Exception.Message)"
  }
}

function Get-OpenIdState {
  param($Values)
  if (-not $Values -or $Values.Count -eq 0) { return "empty" }
  $allPlaceholder = $true
  foreach ($value in $Values) {
    if ([string]$value -ne "ou_xxx_replace_with_allowed_user_open_id") { $allPlaceholder = $false }
  }
  if ($allPlaceholder) { return "placeholder" }
  return "configured"
}

Write-Host "Feishu Codex Bridge doctor" -ForegroundColor Cyan
Write-Host "Repository: $(Get-Location)"
Write-Host ""

Test-FileExists ".\bridge.js"
Test-FileExists ".\runner.js"
Test-FileExists ".\bridge.config.json"
Test-FileExists ".\bridge.config.example.json"

$config = $null
if (Test-Path -LiteralPath ".\bridge.config.json") {
  try {
    $config = Get-Content -LiteralPath ".\bridge.config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Pass "bridge.config.json parses as JSON"
  } catch {
    Fail "bridge.config.json is not valid JSON: $($_.Exception.Message)"
  }
}

if ($config) {
  if ($config.triggerPrefixes -and $config.triggerPrefixes.Count -gt 0) { Pass "triggerPrefixes is non-empty" } else { Fail "triggerPrefixes is empty" }

  $senderState = Get-OpenIdState $config.allowedSenderOpenIds
  if ($senderState -eq "configured") { Pass "allowedSenderOpenIds is configured" }
  elseif ($senderState -eq "placeholder") { Fail "allowedSenderOpenIds still contains only placeholder values" }
  else { Fail "allowedSenderOpenIds is empty" }

  if ($config.defaultWorkspace) {
    if (Test-PlaceholderPath $config.defaultWorkspace) {
      Fail "defaultWorkspace still looks like a placeholder"
    } elseif (Test-Path -LiteralPath $config.defaultWorkspace) {
      Pass "defaultWorkspace exists"
    } else {
      Warn "defaultWorkspace does not exist yet: $($config.defaultWorkspace)"
    }
  } else {
    Fail "defaultWorkspace is missing"
  }

  if ($config.allowedWorkspaces -and $config.allowedWorkspaces.Count -gt 0) { Pass "allowedWorkspaces is non-empty" } else { Fail "allowedWorkspaces is empty" }

  foreach ($folderName in @("queueFolder", "logsFolder")) {
    $folder = $config.$folderName
    if (-not $folder) {
      Fail "$folderName is missing"
      continue
    }
    if (Test-PlaceholderPath $folder) {
      Fail "$folderName still looks like a placeholder"
      continue
    }
    if (-not (Test-Path -LiteralPath $folder)) {
      try {
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        Pass "$folderName created: $folder"
      } catch {
        Fail "$folderName could not be created: $folder ($($_.Exception.Message))"
      }
    } else {
      Pass "$folderName exists: $folder"
    }
  }

  if ($config.eventKey) { Pass "eventKey is set" } else { Fail "eventKey is missing" }

  Test-ExecutableVersion -Name "lark-cli" -ConfiguredPath $config.larkCliPath
  Test-ExecutableVersion -Name "codex" -ConfiguredPath $config.codexCliPath
  Test-FeishuDocOutput -Config $config
}

Write-Host ""
Write-Host "Checking JavaScript syntax" -ForegroundColor Cyan
try {
  & node --check .\bridge.js 2>&1 | Out-Host
  if ($LASTEXITCODE -eq 0) { Pass "bridge.js syntax ok" } else { Fail "bridge.js syntax check failed" }
} catch {
  Fail "node --check bridge.js failed: $($_.Exception.Message)"
}
try {
  & node --check .\runner.js 2>&1 | Out-Host
  if ($LASTEXITCODE -eq 0) { Pass "runner.js syntax ok" } else { Fail "runner.js syntax check failed" }
} catch {
  Fail "node --check runner.js failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Checking processes" -ForegroundColor Cyan
$nodeProcesses = Get-Process -Name node -ErrorAction SilentlyContinue
if ($nodeProcesses) {
  Pass "node.exe process count: $($nodeProcesses.Count)"
} else {
  Warn "No node.exe processes are currently running. This is OK before startup."
}

try {
  $repoRoot = [regex]::Escape((Get-Location).Path)
  $bridgeProcesses = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction Stop |
    Where-Object { $_.CommandLine -match $repoRoot -and ($_.CommandLine -like "*bridge.js*" -or $_.CommandLine -like "*runner.js*") }
  if ($bridgeProcesses) {
    foreach ($process in $bridgeProcesses) {
      $role = if ($process.CommandLine -like "*runner.js*") { "runner" } elseif ($process.CommandLine -like "*bridge.js*") { "bridge" } else { "node" }
      Pass "Detected $role process pid=$($process.ProcessId)"
    }
  } else {
    Warn "No bridge.js or runner.js node process detected for this repository. Run .\start-all.ps1 after configuration passes."
  }
} catch {
  Warn "Could not inspect process command lines: $($_.Exception.Message)"
}

Write-Host ""
if ($script:Failures -gt 0) {
  Write-Host "RESULT: FAIL ($script:Failures failure(s), $script:Warnings warning(s))" -ForegroundColor Red
  Write-Host "Next: fix FAIL items, then rerun .\scripts\doctor.ps1"
  exit 1
}
if ($script:Warnings -gt 0) {
  Write-Host "RESULT: WARN (0 failures, $script:Warnings warning(s))" -ForegroundColor Yellow
  Write-Host "Next: review WARN items. Start bridge + runner only after paths and authentication are correct."
  exit 0
}
Write-Host "RESULT: PASS" -ForegroundColor Green
Write-Host "Next: run .\start-all.ps1 and send a Feishu test message."
