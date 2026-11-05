#!/bin/sh
# Install lemonade-pi on macOS or Linux (Windows: run install.ps1).
#
#   ./install.sh                         # global: ~/.pi/agent (or $PI_CODING_AGENT_DIR)
#   ./install.sh --dir ~/.pi/lemonade-pi-test # self-contained dir, leaves your global setup alone
#   ./install.sh --permissions ask       # start sessions asking first instead of with full access
#   LEMONADE_PI_SOURCE=git:github.com/lemonade-sdk/lemonade-pi ./install.sh
#
# Installs pi with its official installer when it is missing, then the pinned
# packages in config/packages.txt and this distro, then its configuration (see
# scripts/configure.mjs). Safe to re-run. Afterwards start pi with `lemonade launch pi`.
set -eu

usage() {
  echo "Usage: $0 [--dir <path>] [--permissions full|ask]"
  echo "  --dir <path>          install into a self-contained pi agent directory instead of ~/.pi/agent"
  echo "  --permissions full    new sessions run tools without asking (pi's default)"
  echo "  --permissions ask     new sessions ask before edits and commands (Claude Code's default)"
}

own_dir=
mode=
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      [ $# -ge 2 ] || { usage >&2; exit 1; }
      mkdir -p "$2"
      PI_CODING_AGENT_DIR=$(cd "$2" && pwd)
      export PI_CODING_AGENT_DIR
      own_dir=1
      shift 2
      ;;
    --permissions)
      case "${2:-}" in
        full) mode=full ;;
        ask) mode=manual ;;
        *) usage >&2; exit 1 ;;
      esac
      shift 2
      ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

here=$(cd "$(dirname "$0")" && pwd)
source=${LEMONADE_PI_SOURCE:-$here}
agent_dir=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}

say() { printf '\033[1m%s\033[0m\n' "$*"; }

# Ask how new sessions should start, before the slow part. A re-run keeps the
# existing choice unless --permissions is given.
if [ -z "$mode" ] && [ ! -e "$agent_dir/extensions/pi-harness/settings.json" ]; then
  if ( : </dev/tty ) 2>/dev/null; then
    {
      echo "How should new pi sessions handle permissions?"
      echo "  1) Full access: run edits and commands without asking (pi's default)"
      echo "  2) Ask first: approve edits and commands, as in Claude Code"
      echo "You can switch any time with shift+tab or alt+m."
      printf 'Choose [1]: '
    } >/dev/tty
    IFS= read -r answer </dev/tty || answer=
    case "$answer" in
      2*) mode=manual ;;
      *) mode=full ;;
    esac
  else
    mode=full
    echo "No terminal to ask on: sessions start with full access. Re-run with --permissions ask to change that."
  fi
fi

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$1"
  else
    echo "Neither curl nor wget is available to download $1" >&2
    return 1
  fi
}

# The official installer asks its questions on /dev/tty. Its stdout goes
# through cat so it doesn't offer to start pi and take over this script.
if ! command -v pi >/dev/null 2>&1; then
  say "pi not found; running the official installer from https://pi.dev"
  fetch https://pi.dev/install.sh | sh | cat
fi

# A fresh install may not be on PATH until the shell restarts.
pi=$(command -v pi 2>/dev/null || true)
[ -n "$pi" ] || pi="$agent_dir/bin/pi"
if [ ! -x "$pi" ]; then
  echo "pi is still not available. Install it from https://pi.dev, open a new shell, and run this again." >&2
  exit 1
fi

version=$("$pi" --version 2>/dev/null | head -n1)
case "$version" in
  0.* | 1.[0-4] | 1.[0-4].*)
    # `pi update --self` would upgrade the pi on PATH, which --dir promises to leave alone.
    if [ -n "$own_dir" ]; then
      echo "pi $version is too old; lemonade-pi needs 1.5 or newer. Run \`pi update\`, then run this again." >&2
      exit 1
    fi
    say "Updating pi $version (lemonade-pi needs 1.5 or newer)"
    "$pi" update --self
    ;;
esac

say "Installing packages into $agent_dir"
grep -v -e '^#' -e '^[[:space:]]*$' "$here/config/packages.txt" | while IFS= read -r package; do
  echo "  $package"
  "$pi" install "$package" >/dev/null
done
echo "  $source"
"$pi" install "$source" >/dev/null

# Where pi keeps this package: a local source is used in place; git sources are
# cloned to <agent-dir>/git/<host>/<path>, without the ref.
case "$source" in
  git:* | http://* | https://*)
    repo=${source#git:}
    repo=${repo#*://}
    repo=${repo%%@*}
    package_dir="$agent_dir/git/${repo%.git}"
    ;;
  *) package_dir=$(cd "$source" && pwd) ;;
esac

# pi needs Node.js, so one is either on PATH or where pi's installer put it.
node=$(command -v node 2>/dev/null || echo "${XDG_DATA_HOME:-$HOME/.local/share}/pi-node/current/bin/node")
say "Configuring"
"$node" "$here/scripts/configure.mjs" "$agent_dir" "$package_dir" $mode

if [ "$agent_dir" = "$HOME/.pi/agent" ]; then
  say "Done. Start pi with:  lemonade launch pi"
else
  say "Done. Start pi with:  PI_CODING_AGENT_DIR=$agent_dir lemonade launch pi"
fi
cat <<'EOF'

  shift+tab           cycle mode: default -> accept edits -> plan
  alt+m               all permission modes, including full access
  alt+t               cycle thinking level
  /plan, ctrl+alt+p   plan before editing (read-only until you approve)
  /skill:grill-me, /skill:code-review, /skill:simplify, /skill:init

  Web search works without a key. For better results set one of
  SEARXNG_BASE_URL, BRAVE_API_KEY, or TAVILY_API_KEY.
EOF
if ! command -v pi >/dev/null 2>&1; then
  printf '\n  pi was just installed: open a new shell so it is on your PATH.\n'
fi
