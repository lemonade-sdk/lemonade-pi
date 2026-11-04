/**
 * Thinking-level control for Qwen3-family models served by Lemonade.
 *
 * `lemonade launch pi` writes the Lemonade provider into models.json without
 * `reasoning`, so pi treats every model as non-thinking and the thinking level
 * does nothing. This re-registers the provider with `reasoning: true` for
 * Qwen3-family models, sending llama.cpp's controls through Lemonade:
 * - `chat_template_kwargs.enable_thinking`: off vs. on
 * - `thinking_budget_tokens`: the budget of each level (pi's `thinkingBudgets` setting)
 *
 * Launch rewrites models.json on every run, so this can't live there. Once
 * Lemonade writes `reasoning` itself, this extension steps aside.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";

const PROVIDER = "Lemonade";
const THINKING_MODEL = /qwen3|qwq/i;

interface ModelEntry {
  id: string;
  name?: string;
  reasoning?: boolean;
  input?: ("text" | "image")[];
  contextWindow?: number;
  maxTokens?: number;
  compat?: Record<string, unknown>;
}

interface ProviderEntry {
  baseUrl?: string;
  apiKey?: string;
  api?: string;
  compat?: Record<string, unknown>;
  models?: ModelEntry[];
}

function readProvider(): ProviderEntry | undefined {
  try {
    const config = JSON.parse(fs.readFileSync(path.join(getAgentDir(), "models.json"), "utf-8"));
    return config?.providers?.[PROVIDER];
  } catch {
    return undefined;
  }
}

export default function (pi: ExtensionAPI) {
  const provider = readProvider();
  const models = provider?.models ?? [];
  if (!provider?.baseUrl || !models.some((m) => THINKING_MODEL.test(m.id))) return;
  // Lemonade already says which models think: leave its configuration alone.
  if (models.some((m) => m.reasoning !== undefined)) return;

  pi.registerProvider(PROVIDER, {
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    api: (provider.api ?? "openai-completions") as "openai-completions",
    models: models.map((m) => {
      const thinks = THINKING_MODEL.test(m.id);
      return {
        id: m.id,
        name: m.name ?? m.id,
        reasoning: thinks,
        input: m.input ?? ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        // pi's defaults for models.json entries without these fields.
        contextWindow: m.contextWindow ?? 128000,
        maxTokens: m.maxTokens ?? 16384,
        compat: {
          ...provider.compat,
          ...m.compat,
          ...(thinks && {
            thinkingFormat: "qwen-chat-template",
            thinkingTokenBudgetField: "thinking_budget_tokens",
          }),
        },
      };
    }),
  });
}
