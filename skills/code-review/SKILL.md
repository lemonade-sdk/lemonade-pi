---
name: code-review
description: Review code changes for correctness bugs, regressions, and security issues. Use when the user asks to review a diff, branch, PR, or files.
---

# Code review

1. Find the change. Default to `git diff HEAD` (staged and unstaged); for a branch use `git diff <base>...HEAD`. If the user named files or a PR, review those.
2. Read enough surrounding code to understand each change: callers, types, and tests.
3. Look for real defects only:
   - logic errors, off-by-one, wrong conditions, unhandled null or empty cases
   - behavior changes callers don't expect; broken error handling
   - concurrency, resource leaks, injection and other security issues
   - missing or wrong tests for changed behavior
4. Verify each suspected defect against the code before reporting it. Drop anything you can't back with a concrete scenario.

For a large diff, run one `reviewer` subagent per area and verify what they return.

Report findings most-severe first. For each, give:
- `path:line`
- the problem in one sentence
- a concrete input or state that triggers it
- the fix

If nothing significant turns up, say so in one line. Don't pad the review with style nits.
