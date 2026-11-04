---
name: simplify
description: Simplify recently changed code without changing its behavior, removing duplication, dead code, and needless complexity. Use when the user asks to simplify, clean up, or tidy changes.
---

# Simplify

Scope: the current change (`git diff HEAD`) unless the user names files.

1. Read each changed hunk and the code around it.
2. Look for:
   - duplication of logic that already exists nearby (reuse the existing helper)
   - dead code, unused variables and imports, leftover debug output
   - needless indirection, deep nesting, or defensive checks that can't fail
   - names that don't say what the thing is
3. Make each simplification with a focused edit. Preserve behavior exactly: same outputs, errors, and side effects. Match the file's existing style.
4. Run the tests or build afterwards. If something breaks, revert that edit.

Don't refactor code outside the change, and don't add features or comments. Finish with a short list of what you simplified, as `path:line: change`.
