/**
 * shift+tab cycles permission modes like Claude Code: ask first → accept edits → plan,
 * plus full access when that's the mode sessions start in (as Claude Code adds
 * bypass mode when it was launched with it).
 *
 * Ask-first, accept-edits and full are pi-ask-permission's "manual", "edits" and
 * "full" modes, set through its `harness:mode` / `harness:mode:set` event
 * contracts. Plan is pi-plan-mode, started and left with its `/plan start` and
 * `/plan exit` commands; whether it is on comes from the `plan-mode-state` entry
 * it saves on every change, so a plan started with /plan or ended by
 * implementing it is seen too. Planning runs in the starting mode, so finishing
 * a plan returns there. Judge mode stays on alt+m.
 *
 * pi binds shift+tab to the thinking-level cycle; the distro's keybindings.json
 * moves that to alt+t.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { CONFIG_DIR_NAME, type ExtensionAPI, type ExtensionContext, getAgentDir } from "@earendil-works/pi-coding-agent";

type ModeSet = { set(mode: string): void };

/** Whether pi-plan-mode is on, from the latest state it saved on this branch. */
function isPlanning(ctx: ExtensionContext): boolean {
  const entry = ctx.sessionManager
    .getBranch()
    .filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "plan-mode-state")
    .pop() as { data?: { enabled?: unknown } } | undefined;
  return entry?.data?.enabled === true;
}

/** The mode pi-ask-permission starts sessions in; project settings override personal ones. */
function startingMode(cwd: string): string {
  let mode = "manual";
  for (const dir of [getAgentDir(), path.join(cwd, CONFIG_DIR_NAME)]) {
    try {
      const settings = JSON.parse(fs.readFileSync(path.join(dir, "extensions", "pi-harness", "settings.json"), "utf8"));
      if (typeof settings?.permission?.mode === "string") mode = settings.permission.mode;
    } catch {
      // No settings here, or unreadable: keep what we have.
    }
  }
  return mode;
}

export default function (pi: ExtensionAPI) {
  /** Ask a pi-ask-permission contract; undefined when it isn't installed. */
  function ask<T>(channel: string): T | undefined {
    const question: { answered?: boolean; value?: T } = {};
    pi.events.emit(channel, question);
    return question.answered ? question.value : undefined;
  }

  function runCommand(command: string): void {
    pi.sendUserMessage(command, { expandPromptTemplates: true });
  }

  pi.registerShortcut("shift+tab", {
    description: "Cycle permission mode: ask first → accept edits → plan (→ full access)",
    handler: async (ctx: ExtensionContext) => {
      const modes = ask<ModeSet>("harness:mode:set");
      if (!modes) {
        ctx.ui.notify("Permission modes need pi-ask-permission.", "warning");
        return;
      }
      if (!ctx.isIdle()) {
        ctx.ui.notify("Wait for the current turn to finish before changing modes.", "warning");
        return;
      }

      const start = startingMode(ctx.cwd);
      const cycle = ["manual", "edits", "plan", ...(start === "full" ? ["full"] : [])];
      const current = isPlanning(ctx) ? "plan" : (ask<string>("harness:mode") ?? "manual");
      // A mode outside the cycle, such as judge, moves to its start.
      const next = cycle[(cycle.indexOf(current) + 1) % cycle.length];

      if (current === "plan") runCommand("/plan exit");
      if (next === "plan") {
        modes.set(start === "full" ? "full" : "manual");
        runCommand("/plan start");
      } else {
        modes.set(next);
      }
    },
  });
}
