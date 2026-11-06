// Write lemonade-pi's configuration into a pi agent directory. Run by install.sh
// and install.ps1 after the packages are installed:
//
//   node scripts/configure.mjs <agent-dir> <package-dir> [full|manual]
//
// The optional mode is the permission mode new sessions start in: full (no
// prompts, pi's default) or manual (ask first, Claude Code's default). Without
// it a new install gets full and an existing install keeps its mode.
//
// Files are only created where none exist. The few edits to existing files are
// targeted merges that leave the user's other settings alone.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const [agentDir, packageDir, permissionMode] = process.argv.slice(2);
if (!agentDir || !packageDir || (permissionMode && !["full", "manual"].includes(permissionMode))) {
  console.error("usage: node configure.mjs <agent-dir> <package-dir> [full|manual]");
  process.exit(1);
}
const here = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const config = (name) => path.join(here, "config", name);
const target = (...parts) => path.join(agentDir, ...parts);

function readJson(file) {
  try {
    return { value: JSON.parse(fs.readFileSync(file, "utf8")) };
  } catch (error) {
    return { missing: error.code === "ENOENT", invalid: error.code !== "ENOENT" };
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

/** Copy a file into the agent directory unless the user already has one. */
function seed(from, to) {
  if (fs.existsSync(to)) {
    console.log(`  kept ${to}`);
    return false;
  }
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
  console.log(`  wrote ${to}`);
  return true;
}

for (const agent of fs.readdirSync(path.join(here, "agents")).filter((f) => f.endsWith(".md"))) {
  seed(path.join(here, "agents", agent), target("agents", agent));
}
seed(config("web-search.json"), target("web-search.json"));
seed(config("pi-plan-mode.json"), target("pi-plan-mode.json"));
seed(config("pi-todo-config.json"), target("pi-todo", "config.json"));
configurePermissions();
removeOldInstalls();
allowSkillReads();
bindThinkingCycle();
checkPackageOrder();

// Sets the mode new sessions start in: the one chosen at install, else full for a
// new install, else whatever the user has. pi-ask-permission stays installed
// either way, so shift+tab, alt+m, and its settings screen can switch later.
//
// Earlier releases allowed `subagent` without a prompt, so delegated agents,
// which run in full mode, could act unapproved. A file still holding exactly
// that old default list is moved to the new one; any other list is the user's.
function configurePermissions() {
  const file = target("extensions", "pi-harness", "settings.json");
  if (!fs.existsSync(file)) {
    const settings = readJson(config("pi-harness-settings.json")).value;
    settings.permission.mode = permissionMode ?? "full";
    writeJson(file, settings);
    console.log(`  wrote ${file}: new sessions start in ${describeMode(settings.permission.mode)}`);
    return;
  }
  const current = readJson(file).value;
  if (!current?.permission) {
    console.log(`  kept ${file}`);
    return;
  }
  const changes = [];
  const allow = current.permission.allow;
  const oldDefault = ["read", "grep", "find", "ls", "subagent", "web_search", "fetch_content", "todo",
    "plan_mode_question", "plan_mode_complete"];
  if (Array.isArray(allow) && allow.length === oldDefault.length && oldDefault.every((t, i) => allow[i] === t)) {
    current.permission.allow = allow.filter((t) => t !== "subagent");
    changes.push("delegating to a subagent now asks first");
  }
  if (permissionMode && current.permission.mode !== permissionMode) {
    current.permission.mode = permissionMode;
    changes.push(`new sessions start in ${describeMode(permissionMode)}`);
  }
  if (changes.length > 0) {
    writeJson(file, current);
    console.log(`  updated ${file}: ${changes.join("; ")}`);
  } else {
    console.log(`  kept ${file}`);
  }
}

function describeMode(mode) {
  return mode === "full" ? "full access (no permission prompts)" : `${mode} mode (asks first)`;
}

// Earlier releases loaded lemonade-pi from the clone the installer ran in, and
// --dev still does. Any other copy pi still lists would load every extension
// twice, or point at a folder that's gone, so it's dropped from settings.json.
function removeOldInstalls() {
  const file = target("settings.json");
  const settings = readJson(file).value;
  if (!Array.isArray(settings?.packages)) return;
  const packages = settings.packages.filter((p) => {
    const source = typeof p === "string" ? p : p?.source;
    if (typeof source !== "string" || !isLocal(source) || !isOldInstall(path.resolve(agentDir, source))) return true;
    console.log(`  updated ${file}: removed ${source}, an earlier install of lemonade-pi`);
    return false;
  });
  if (packages.length !== settings.packages.length) writeJson(file, { ...settings, packages });
}

function isLocal(source) {
  return !/^(npm:|git:|[a-z]+:\/\/)/i.test(source);
}

/** A lemonade-pi folder other than this install's, or a missing one by that name. */
function isOldInstall(dir) {
  if (samePath(dir, packageDir)) return false;
  const name = readJson(path.join(dir, "package.json")).value?.name;
  return name === "lemonade-pi" || (!fs.existsSync(dir) && path.basename(dir) === "lemonade-pi");
}

// The model reads skills from this package's folder, which is outside any
// workspace, so pi-ask-permission would ask before every skill it loads.
// Folders of earlier installs are dropped.
function allowSkillReads() {
  const file = target("extensions", "pi-ask-permission", "folders.json");
  const { value, invalid } = readJson(file);
  if (invalid) {
    console.log(`  kept ${file} (not valid JSON); skills will ask before they're read`);
    return;
  }
  const folders = value ?? { read: [], write: [] };
  const resolve = (dir) => path.resolve(dir.replace(/^~(?=$|[\\/])/, home()));
  const before = Array.isArray(folders.read) ? folders.read : [];
  const read = before.filter((dir) => !isOldInstall(resolve(dir)));
  const removed = before.length - read.length;
  const found = read.some((dir) => samePath(resolve(dir), packageDir));
  if (found && removed === 0) {
    console.log(`  kept ${file}`);
    return;
  }
  folders.read = found ? read : [...read, packageDir];
  writeJson(file, folders);
  console.log(`  ${value ? "updated" : "wrote"} ${file}: skills can be read without asking`);
}

// shift+tab cycles permission modes, as in Claude Code, so pi's thinking-level
// cycle moves to alt+t. An existing keybindings.json gets that one entry merged
// in, unless the user already chose a key for it.
function bindThinkingCycle() {
  const file = target("keybindings.json");
  const { value, missing } = readJson(file);
  if (missing) {
    seed(config("keybindings.json"), file);
    return;
  }
  if (!value || typeof value !== "object") {
    console.log(`  kept ${file} (not valid JSON); add "app.thinking.cycle": "alt+t" so shift+tab can cycle modes`);
    return;
  }
  if ("app.thinking.cycle" in value) {
    console.log(`  kept ${file} (app.thinking.cycle is already bound)`);
  } else {
    value["app.thinking.cycle"] = "alt+t";
    writeJson(file, value);
    console.log(`  updated ${file}: thinking-level cycle on alt+t`);
  }
  for (const [action, keys] of Object.entries(value)) {
    if ((Array.isArray(keys) ? keys : [keys]).includes("shift+tab")) {
      console.log(`  warning: ${action} uses shift+tab, so shift+tab won't cycle permission modes`);
    }
  }
}

// pi runs tool_call hooks in package order, and `pi install` keeps an existing
// package where it is. Plan mode must come first, or the permission prompt asks
// about edits that plan mode is about to block.
function checkPackageOrder() {
  const packages = readJson(target("settings.json")).value?.packages ?? [];
  const position = (name) =>
    packages.findIndex((p) => (typeof p === "string" ? p : p?.source ?? "").includes(name));
  const plan = position("pi-plan-mode");
  const permission = position("pi-ask-permission");
  if (plan > permission && permission >= 0) {
    console.log(
      `  warning: ${target("settings.json")} lists pi-ask-permission before pi-plan-mode;` +
        " move pi-plan-mode above it so plan mode blocks edits before you're asked about them",
    );
  }
}

function samePath(a, b) {
  const [x, y] = [path.resolve(a), path.resolve(b)];
  return process.platform === "win32" ? x.toLowerCase() === y.toLowerCase() : x === y;
}

function home() {
  return process.env.HOME ?? process.env.USERPROFILE ?? "";
}
