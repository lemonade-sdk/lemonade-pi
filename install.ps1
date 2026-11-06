# Install lemonade-pi on Windows (macOS/Linux: run install.sh).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1                             # global: ~\.pi\agent
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Dir $HOME\.pi\lemonade-pi-test  # self-contained dir
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Permissions ask  # start sessions asking first
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Dev              # load extensions and skills from this clone
#
# Installs pi with its official installer when it is missing, then the pinned
# packages in config\packages.txt and this distro, then its configuration (see
# scripts\configure.mjs). The distro is copied into the agent directory, so this
# clone can be deleted afterwards. Safe to re-run. Afterwards start pi with
# `lemonade launch pi`.
param(
  # Install into a self-contained pi agent directory instead of ~\.pi\agent.
  [string]$Dir,
  # How new sessions handle permissions: full (no prompts, pi's default) or ask (Claude Code's default).
  [ValidateSet("full", "ask")]
  [string]$Permissions,
  # Load extensions and skills from this clone instead of a copy, for working on them.
  [switch]$Dev
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

# Ask how new sessions should start, before the slow part. A re-run keeps the
# existing choice unless -Permissions is given.
$mode = switch ($Permissions) { "full" { "full" } "ask" { "manual" } default { "" } }
if (-not $mode -and -not (Test-Path (Join-Path $agentDir "extensions\pi-harness\settings.json"))) {
  if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    Write-Host "How should new pi sessions handle permissions?"
    Write-Host "  1) Full access: run edits and commands without asking (pi's default)"
    Write-Host "  2) Ask first: approve edits and commands, as in Claude Code"
    Write-Host "You can switch any time with shift+tab or alt+m."
    $answer = Read-Host "Choose [1]"
    $mode = if ($answer -like "2*") { "manual" } else { "full" }
  } else {
    $mode = "full"
    Write-Host "No terminal to ask on: sessions start with full access. Re-run with -Permissions ask to change that."
  }
}

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

# Where pi keeps this package. git sources are cloned to
# <agent-dir>\git\<host>\<path>, without the ref. pi loads a local source in
# place, so it's copied into the agent directory first, unless -Dev asks for
# the source itself.
$copyDir = Join-Path $agentDir "lemonade-pi"
if ($source -match '^(git:|https?://)') {
  $repo = ($source -replace '^git:', '' -replace '^[a-z]+://', '' -replace '@.*$', '' -replace '\.git$', '')
  $packageDir = Join-Path $agentDir "git\$repo"
} else {
  $packageDir = (Resolve-Path $source).Path
  if (-not $Dev -and $packageDir -ne $copyDir) {
    if (Test-Path $copyDir) { Remove-Item -Recurse -Force $copyDir }
    New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
    foreach ($file in "package.json", "extensions", "skills", "LICENSE", "THIRD_PARTY_NOTICES.md") {
      Copy-Item -Recurse (Join-Path $packageDir $file) $copyDir
    }
    $packageDir = $copyDir
  }
  $source = $packageDir
}

# -Dev leaves the copy unused. configure.mjs drops it, and any other earlier
# install of this distro, from pi's settings.
if ($Dev -and $packageDir -ne $copyDir -and (Test-Path $copyDir)) { Remove-Item -Recurse -Force $copyDir }

Write-Host "  $source"
Invoke-Pi install $source

# pi needs Node.js, so one is either on PATH or where pi's installer put it.
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$node = if ($nodeCommand) { $nodeCommand.Source } else { Join-Path $env:LOCALAPPDATA "pi-node\current\node.exe" }
Say "Configuring"
$configureArgs = @((Join-Path $here "scripts\configure.mjs"), $agentDir, $packageDir)
if ($mode) { $configureArgs += $mode }
& $node @configureArgs
if ($LASTEXITCODE -ne 0) { throw "configure.mjs failed with exit code $LASTEXITCODE" }

if ($env:PI_CODING_AGENT_DIR) {
  Say "Done. Start pi with:  `$env:PI_CODING_AGENT_DIR = `"$agentDir`"; lemonade launch pi"
} else {
  Say "Done. Start pi with:  lemonade launch pi"
}
Write-Host @"

  shift+tab           cycle mode: ask first -> accept edits -> plan (-> full access)
  alt+m               all permission modes, including full access
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
