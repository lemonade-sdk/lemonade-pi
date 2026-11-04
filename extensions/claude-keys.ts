/**
 * shift+tab cycles permission modes like Claude Code: default → accept edits → plan → default.
 *
 * Default and accept-edits are pi-ask-permission's "manual" and "edits" modes, set
 * through its `harness:mode` / `harness:mode:set` event contracts. Plan is
 * pi-plan-mode, started and left with its `/plan start` and `/plan exit` commands;
 * whether it is on comes from the `plan-mode-state` entry it saves on every change,
 * so a plan started with /plan or ended by implementing it is seen too.
 * Its other modes (judge, full) stay on alt+m.
 *
 * pi binds shift+tab to the thinking-level cycle; the distro's keybindings.json
 * moves that to alt+t.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type ModeSet = { set(mode: string): void };

/** Whether pi-plan-mode is on, from the latest state it saved on this branch. */
function isPlanning(ctx: ExtensionContext): boolean {
  const entry = ctx.sessionManager
    .getBranch()
    .filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "plan-mode-state")
    .pop() as { data?: { enabled?: unknown } } | undefined;
  return entry?.data?.enabled === true;
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
    description: "Cycle permission mode: default → accept edits → plan",
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

      if (isPlanning(ctx)) {
        runCommand("/plan exit");
        modes.set("manual");
      } else if (ask<string>("harness:mode") === "edits") {
        modes.set("manual");
        runCommand("/plan start");
      } else {
        modes.set("edits");
      }
    },
  });

}
