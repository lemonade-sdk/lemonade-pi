// Write lemonade-pi's configuration into a pi agent directory. Run by install.sh
// and install.ps1 after the packages are installed:
//
//   node scripts/configure.mjs <agent-dir> <package-dir>
//
// Files are only created where none exist. The few edits to existing files are
// targeted merges that leave the user's other settings alone.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const [agentDir, packageDir] = process.argv.slice(2);
if (!agentDir || !packageDir) {
  console.error("usage: node configure.mjs <agent-dir> <package-dir>");
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
seed(config("pi-harness-settings.json"), target("extensions", "pi-harness", "settings.json"));
bindThinkingCycle();

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
