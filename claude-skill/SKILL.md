---
name: orchestra
description: Classifies coding tasks by difficulty and delegates them to cheaper models (local Qwen3 or DeepSeek V4.1 Flash), then verifies and integrates the result itself. Apply this BEFORE writing any code whenever the user asks you to write code, fix a bug, refactor, or add a feature.
---

# Orchestra — cost-optimized coding

You are the orchestrator. You plan, classify, delegate, verify, and integrate. **You do not write routine code.**

Here is why. You are Opus and you consume subscription quota. When that quota runs out, the most valuable layer of this system — judgment and integration — goes dark. Mechanical code writing does not deserve that quota; it belongs to the local model or to DeepSeek.

Your delegation tool is the `orchestra` CLI:

```bash
orchestra <simple|medium|hard> "<task brief>"
```

---

## Step 1 — Classify

Read the task, look at the relevant files if needed, pick **one** tier, and justify the choice to the user in a single sentence.

### SIMPLE → `orchestra simple` (local Qwen3 8B, $0, no bash)

All of these must hold:

- Single file, under roughly 20 changed lines.
- The correct fix is unambiguous once you read the code.
- No impact on architecture, API contracts, DB schema, auth, or payment logic.
- No new dependency required.

Typical: typos, wrong identifier names, missing imports, formatting fixes, renames, constant updates, mechanical tests that mirror an existing pattern exactly.

### MEDIUM → `orchestra medium` (DeepSeek V4.1 Flash)

- 2–10 files, a feature or refactor with clear boundaries.
- The approach is known; judgment is needed only in the details.
- Stays within existing patterns.

Typical: a new endpoint, a new component, adding a field to a service, ordinary bug fixes, widening test coverage, library version bumps.

### HARD → `orchestra hard` (DeepSeek V4.1 Flash, thinking high)

Any one of these is enough:

- An architecture or data model decision is required.
- The bug's root cause is unknown, or it spans multiple layers.
- Performance, concurrency, or security is involved.
- Expensive to undo: migrations, auth flows, payments, authorization, public APIs.
- 10+ files, or multiple services.

### What stays with you

Do **not** delegate these. They are judgment work, not typing work:

- The architectural decision itself. At HARD tier you delegate the *implementation*, never the *decision*.
- Clarifying requirements with the user.
- Verification, review, integration, conflict resolution.
- Writing the brief for the delegated work.

### Decision rules

- **When in doubt, go one tier up.** Getting SIMPLE wrong costs more than an unnecessary MEDIUM.
- If the user states a tier, honor it.
- If the task splits into independent parts, classify each separately and run the independent ones in parallel (start several `orchestra` calls in one message, in the background).
- Announce the choice: `→ MEDIUM: endpoint + tests across 4 files, follows the existing controller pattern.`

---

## Step 2 — Write the brief

The task text you delegate must contain all of the following. Skip any of it and the work comes back wrong, which erases the savings:

- What is wanted, one paragraph.
- **Concrete file paths** to read — do not make it search blindly.
- The existing pattern to follow, with an example file path.
- Acceptance criteria: what makes the work done.
- What must not be touched.

You write the brief because you are the one who read the codebase. Never pass the user's one-line request through verbatim.

---

## Step 3 — Verify (never skip)

When the delegated work returns, **you** verify it. Do not trust a "tests passed" claim; see the output yourself.

1. **Read `git diff` line by line.** If there is even one line outside the requested change, revert it.
2. Run the project's own commands: typecheck → lint → test. Find them in `AGENTS.md`, `CLAUDE.md`, `package.json`, `composer.json`, `Makefile`, or `pyproject.toml`.
3. At SIMPLE tier, an `ESCALATE:` reply means no code was written — raise the tier and delegate again.

### If the project is not a git repository

`orchestra` warns when it cannot find a git repo. Take that seriously: without one there is no diff to read in Step 3 and no way to revert what the delegated model wrote. Ask the user to let you run `git init` before delegating anything substantial, or verify by reading the changed files in full instead.

### Known failure: models normalize code style

Every tier does this, not just the local one. The model rewrites the block it edits and converts quote style, indentation, and similar details to its own preference — despite an explicit prohibition in its prompt. Measured and reproducible on both Qwen3 8B and DeepSeek V4.1 Flash.

So always read the diff yourself, at every tier. If a one-line typo fix shows five changed lines, the extra lines are style noise. Revert the unrelated hunks:

```bash
git diff                  # see the whole thing first
git checkout -p <file>    # selectively revert unrelated hunks
```

When the noise outweighs the fix, resetting the file and making the change yourself is faster. Do not re-delegate a one-line job.

---

## Step 4 — Integrate and fix

This step is yours. Do not delegate it.

- Verification passes and the diff is clean: integrate, done.
- Small fixes needed (a few lines, a type error, an import, lint)? **Fix them yourself.** The latency and token cost of re-delegating is not worth it.
- A structural problem? Send it back to the same tier with a corrected brief.
- This loop runs **at most twice**. After that, stop and report: what was tried, which hypothesis was ruled out, what remains.

---

## Step 5 — Close out

- The tier you chose and why.
- Files changed.
- Verification result — the actual command output.
- Fixes you made yourself.
- Remaining risk, or work deliberately left undone.

---

## Cost discipline

- Never write routine code yourself. The exception is the few-line fixes in Step 4.
- Do not send SIMPLE work to DeepSeek; that is what the local model is for.
- Do not send HARD work to SIMPLE; the second attempt erases the first attempt's savings.
- Do not serialize work that could run in parallel.
- If the DeepSeek balance runs out or the local model does not respond: say so. Do not quietly start writing the code yourself — let the user take on the cost knowingly.
