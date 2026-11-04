# Install lemonade-pi on Windows (macOS/Linux: run install.sh).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1                             # global: ~\.pi\agent
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Dir $HOME\.pi\lemonade-pi-test  # self-contained dir
#
# Installs pi with its official installer when it is missing, then the pinned
# packages in config\packages.txt and this distro. Safe to re-run: existing
# config files are never overwritten. Afterwards start pi with `lemonade launch pi`.
param(
  # Install into a self-contained pi agent directory instead of ~\.pi\agent.
  [string]$Dir
)
$ErrorActionPreference = "Stop"

if ($Dir) {
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  $env:PI_CODING_AGENT_DIR = (Resolve-Path $Dir).Path
}

$here = $PSScriptRoot
$source = if ($env:LEMONADE_PI_SOURCE) { $env:LEMONADE_PI_SOURCE } else { $here }
$agentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HOME ".pi\agent" }

function Say($text) { Write-Host $text -ForegroundColor White }

# Run a pi command and stop on failure; native commands don't throw on their own.
function Invoke-Pi {
  & $script:pi @args | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "pi $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

# The official installer can call `exit`, so it runs in its own PowerShell process.
if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
  Say "pi not found; running the official installer from https://pi.dev"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://pi.dev/install.ps1 | iex"
}

# A fresh install may not be on PATH until the shell restarts.
$found = Get-Command pi.cmd, pi -ErrorAction SilentlyContinue | Select-Object -First 1
$pi = if ($found) { $found.Source } else { Join-Path $agentDir "bin\pi.cmd" }
if (-not (Test-Path $pi)) {
  Write-Error "pi is still not available. Install it from https://pi.dev, open a new terminal, and run this again."
}

$version = (& $pi --version | Select-Object -First 1).Trim()
if ([version]($version -replace '[^0-9.].*$', '') -lt [version]"1.5") {
  Say "Updating pi $version (lemonade-pi needs 1.5 or newer)"
  Invoke-Pi update --self
}

Say "Installing packages into $agentDir"
foreach ($package in Get-Content (Join-Path $here "config\packages.txt")) {
  if ($package -match '^\s*(#|$)') { continue }
  Write-Host "  $package"
  Invoke-Pi install $package
}
Write-Host "  $source"
Invoke-Pi install $source

# Copy a file into the agent directory unless the user already has one.
function Seed($from, $to) {
  if (Test-Path $to) {
    Write-Host "  kept $to"
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
    Copy-Item $from $to
    Write-Host "  wrote $to"
  }
}

# shift+tab cycles permission modes, as in Claude Code, so pi's thinking-level
# cycle moves to alt+t. An existing keybindings.json gets that one entry merged
# in, unless the user already chose a key for it.
function Set-ThinkingCycleKey {
  $file = Join-Path $agentDir "keybindings.json"
  if (-not (Test-Path $file)) {
    Seed (Join-Path $here "config\keybindings.json") $file
    return
  }
  try {
    $bindings = Get-Content $file -Raw | ConvertFrom-Json
  } catch {
    Write-Host "  kept $file (not valid JSON); add `"app.thinking.cycle`": `"alt+t`" so shift+tab can cycle modes"
    return
  }
  if ($bindings.PSObject.Properties.Name -contains "app.thinking.cycle") {
    Write-Host "  kept $file (app.thinking.cycle is already bound)"
  } else {
    $bindings | Add-Member -NotePropertyName "app.thinking.cycle" -NotePropertyValue "alt+t"
    $bindings | ConvertTo-Json -Depth 5 | Set-Content $file -Encoding UTF8
    Write-Host "  updated ${file}: thinking-level cycle on alt+t"
  }
  foreach ($binding in $bindings.PSObject.Properties) {
    if (@($binding.Value) -contains "shift+tab") {
      Write-Host "  warning: $($binding.Name) uses shift+tab, so shift+tab won't cycle permission modes"
    }
  }
}

Say "Seeding configuration"
foreach ($agent in Get-ChildItem (Join-Path $here "agents") -Filter *.md) {
  Seed $agent.FullName (Join-Path $agentDir "agents\$($agent.Name)")
}
Seed (Join-Path $here "config\web-search.json") (Join-Path $agentDir "web-search.json")
Seed (Join-Path $here "config\pi-plan-mode.json") (Join-Path $agentDir "pi-plan-mode.json")
Seed (Join-Path $here "config\pi-harness-settings.json") (Join-Path $agentDir "extensions\pi-harness\settings.json")
Seed (Join-Path $here "config\pi-todo-config.json") (Join-Path $agentDir "pi-todo\config.json")
Set-ThinkingCycleKey

if ($env:PI_CODING_AGENT_DIR) {
  Say "Done. Start pi with:  `$env:PI_CODING_AGENT_DIR = `"$agentDir`"; lemonade launch pi"
} else {
  Say "Done. Start pi with:  lemonade launch pi"
}
Write-Host @"

  shift+tab           cycle mode: default -> accept edits -> plan
  alt+t               cycle thinking level
  /plan, ctrl+alt+p   plan before editing (read-only until you approve)
  /skill:grill-me, /skill:code-review, /skill:simplify, /skill:init

  Web search works without a key. For better results set one of
  SEARXNG_BASE_URL, BRAVE_API_KEY, or TAVILY_API_KEY.
"@
if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "  pi was just installed: open a new terminal so it is on your PATH."
}
