---
name: init
description: Create an AGENTS.md contributor guide for this repository so future sessions know its structure, commands, and conventions. Use when the user asks to initialize or set up AGENTS.md.
---

# Write AGENTS.md

If `AGENTS.md` already exists in the working directory, stop and tell the user. Don't overwrite it.

Explore first: the README, the build files (package.json, Makefile, pyproject.toml, Cargo.toml, ...), the directory layout, the CI config, and `git log --oneline -20`.

Then write `AGENTS.md`, titled "Repository Guidelines". Keep it to 200–400 words, specific to this repository, with real commands and paths. Include only the sections that apply:

- Project structure: where source, tests, and assets live
- Build, test, and dev commands, each with a one-line explanation
- Coding style: formatting, linting, naming
- Testing: framework, naming, how to run one test
- Commits and PRs: conventions seen in the git history

Don't invent conventions the repository doesn't show.

Adapted from the OpenAI Codex `/init` prompt (Apache-2.0).
