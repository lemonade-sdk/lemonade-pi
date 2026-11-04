# Install lemonade-pi on Windows (macOS/Linux: run install.sh).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1                             # global: ~\.pi\agent
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Dir $HOME\.pi\lemonade-pi-test  # self-contained dir
#
# Installs pi with its official installer when it is missing, then the pinned
# packages in config\packages.txt and this distro, then its configuration (see
# scripts\configure.mjs). Safe to re-run. Afterwards start pi with `lemonade launch pi`.
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
  # `pi update --self` would upgrade the pi on PATH, which -Dir promises to leave alone.
  if ($Dir) {
    Write-Error "pi $version is too old; lemonade-pi needs 1.5 or newer. Run ``pi update``, then run this again."
  }
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

# Where pi keeps this package: a local source is used in place; git sources are
# cloned to <agent-dir>\git\<host>\<path>, without the ref.
if ($source -match '^(git:|https?://)') {
  $repo = ($source -replace '^git:', '' -replace '^[a-z]+://', '' -replace '@.*$', '' -replace '\.git$', '')
  $packageDir = Join-Path $agentDir "git\$repo"
} else {
  $packageDir = (Resolve-Path $source).Path
}

# pi needs Node.js, so one is either on PATH or where pi's installer put it.
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$node = if ($nodeCommand) { $nodeCommand.Source } else { Join-Path $env:LOCALAPPDATA "pi-node\current\node.exe" }
Say "Configuring"
& $node (Join-Path $here "scripts\configure.mjs") $agentDir $packageDir
if ($LASTEXITCODE -ne 0) { throw "configure.mjs failed with exit code $LASTEXITCODE" }

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
