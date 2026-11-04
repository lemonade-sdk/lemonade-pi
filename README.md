# lemonade-pi 🍋

**Lemonade flavored pi**: an opinionated [pi](https://pi.dev) distro for local models.

One install gives you a Claude-Code-like setup tuned for models such as Qwen3.8 27B on [Lemonade](https://lemonade-server.ai): web search, subagents, plan mode, permission modes, questions, a todo list, thinking-level control, and a few skills. It keeps the prompt small, about 3.5k tokens of system prompt and tools in total.

## Install

```sh
git clone https://github.com/lemonade-sdk/lemonade-pi && cd lemonade-pi
./install.sh                                          # macOS, Linux
powershell -ExecutionPolicy Bypass -File install.ps1  # Windows
lemonade launch pi
```

To try it without touching your global `~/.pi/agent`, install into a self-contained directory and launch with it:

```sh
./install.sh --dir ~/.pi/lemonade-pi-test                  # Windows: install.ps1 -Dir $HOME\.pi\lemonade-pi-test
PI_CODING_AGENT_DIR=~/.pi/lemonade-pi-test lemonade launch pi
```

If pi isn't installed, the installer runs pi's official installer first. It then runs `pi install` for each package below, pinned to tested versions. It writes config files only where none exist, with three small edits to files you already have:

- **`keybindings.json`:** adds `"app.thinking.cycle": "alt+t"`, which frees shift+tab for the mode cycle, unless you've already bound that action.
- **pi-ask-permission's `folders.json`:** gets this package's folder as read-only, so loading a skill doesn't prompt.
- **Permission allow list:** if it still matches an earlier lemonade-pi default, it's updated to the current one.

It leaves `models.json`, `mcp.json`, and your default model (which `lemonade launch pi` manages) alone.

## What you get

| Feature | Provided by | Use |
|---|---|---|
| Plan mode | [@narumitw/pi-plan-mode](https://www.npmjs.com/package/@narumitw/pi-plan-mode) | `shift+tab`, `/plan`, `ctrl+alt+p` |
| Permission prompts, ask-user questions | [@adeildo/pi-ask-permission](https://www.npmjs.com/package/@adeildo/pi-ask-permission) | `shift+tab`; `alt+m` for all modes |
| Subagents | [pi-lite-subagent](https://www.npmjs.com/package/pi-lite-subagent) | agents: explore, plan, general-purpose, reviewer |
| Web search and fetch | [pi-web-access](https://www.npmjs.com/package/pi-web-access) | works without a key |
| Todo list | [pi-todo-lite](https://www.npmjs.com/package/pi-todo-lite) | `ctrl+alt+t`, `/todos` |
| Thinking levels for Qwen3 on Lemonade | `extensions/lemonade-thinking.ts` | `alt+t` cycles off → high |
| Lean system prompt | `extensions/lean-prompt.ts` | always on |
| Skills | `skills/` | `/skill:grill-me`, `code-review`, `simplify`, `init` |

All extensions come from their upstream authors, unmodified. This repository adds only glue:

- **`lean-prompt.ts`** replaces pi's default prompt with a short behavioral one, mentions only tools that are active, and lists your subagents.
- **`claude-keys.ts`** makes `shift+tab` cycle modes like Claude Code: default → accept edits → plan. The thinking-level cycle moves to `alt+t` (in `keybindings.json`) and the todo toggle to `ctrl+alt+t`.
- **`lemonade-thinking.ts`** marks Qwen3-family Lemonade models as reasoning models. pi then sends `enable_thinking` and llama.cpp's `thinking_budget_tokens`, so `off` disables thinking and each level caps it (budgets come from pi's `thinkingBudgets` setting). It steps aside once Lemonade writes `reasoning` into models.json itself.
- **`subagent-permissions.ts`** runs headless subagent children in `full` permission mode. Delegating isn't on the allow list, so in default and accept-edits modes you approve each delegation, seeing the agent and its task, in the parent. Agents are still limited by their `tools:`.
- **Config defaults in `config/`:**
  - read-only tools, web search, todos, and plan mode's own tools are allowed without prompting
  - plan mode may use read-only bash and web tools
  - web search is routed SearXNG → Brave → Tavily → Exa (free) → DuckDuckGo

## Configuration

- **Better search:** set `SEARXNG_BASE_URL`, `BRAVE_API_KEY`, or `TAVILY_API_KEY`. Unconfigured providers are skipped.
- **Agents:** edit or add Markdown agents in `~/.pi/agent/agents/`. Leave out `model:` so they use the model you launched.
- **Permissions:** `~/.pi/agent/extensions/pi-harness/settings.json`, or the settings screen.
- **Plan mode:** `~/.pi/agent/pi-plan-mode.json`, or `/plan settings`.

## Known gaps

- **Subagent concurrency is fixed at 4** in pi-lite-subagent 0.2.2, the most tasks of one `parallel` call that run at once. That suits discrete GPUs serving several slots. Lemonade starts llama.cpp with one slot (`--parallel 1`), though, so on a single GPU such as Strix Halo the extra requests just queue on the server and evict each other's prompt cache. A setting for this is planned upstream.
- **No subagents in plan mode.** pi-lite-subagent can't restrict which agent runs, so plan mode leaves `subagent` out to stay read-only.
- **Two question tools.** Plan mode's `plan_mode_question` is declared in every request next to `ask_questions`, about 340 extra tokens; it only works while a plan is active. Plan mode keeps its tool list fixed on purpose, because changing tools mid-session would make llama.cpp reprocess the whole prompt.
