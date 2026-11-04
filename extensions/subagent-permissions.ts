/**
 * Let subagent children act without a permission dialog.
 *
 * Children run headless (pi-lite-subagent spawns `pi -p`), so pi-ask-permission
 * would refuse every call it needs to ask about. Instead the delegation itself is
 * gated: `subagent` is deliberately not in the default allow list, so in the
 * default and accept-edits modes the user approves each delegation, seeing the
 * agent and its task, in the parent. Children then switch to "full" mode through
 * pi-ask-permission's `harness:mode:set` event contract. Agents are still limited
 * by the `tools:` list in their definition.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  if (!process.env.PI_SUBAGENT_DEPTH) return;

  pi.on("session_start", () => {
    const question: { answered?: boolean; value?: { set?: (mode: string) => void } } = {};
    pi.events.emit("harness:mode:set", question);
    if (question.answered) question.value?.set?.("full");
  });
}
