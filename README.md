# pi-orchestra

A cost-optimized, multi-tier coding system. **Claude Code** acts as the orchestrator, delegates routine code to cheaper models, then verifies and integrates the result itself.

The idea is simple: **judgment is expensive, typing is cheap.** Opus earns its keep by planning, classifying, verifying, and integrating. Mechanical code writing does not deserve that quota — it belongs to a local model or to DeepSeek.

```
                  ORCHESTRATOR
              Claude Code / Opus 5
            (subscription, $0 marginal)
                       │
                 classify difficulty
                       │
      ┌────────────────┼─────────────────┐
      ▼                ▼                 ▼
    SIMPLE           MEDIUM             HARD
      │                │                 │
      ▼                ▼                 ▼
 orchestra simple  orchestra medium  orchestra hard
 Qwen3 8B          DeepSeek          DeepSeek V4.1
 (local, $0)       V4.1 Flash        Flash, thinking:high
      │                │                 │
 typo / small     feature /         architecture /
 bug / test       refactor          complex bug
      │                │                 │
      └────────────────┼─────────────────┘
                       ▼
                  INTEGRATION
              Claude Code / Opus 5
                       │
           git diff → typecheck → lint → test
                       │
                  ┌────┴────┐
                  ▼         ▼
                PASS       FAIL
                  │         │
                 DONE   fix / re-delegate
                            (max 2 rounds)
```

## Why this combination

| Layer | Runs on | Cost | Measured latency |
|---|---|---|---|
| Orchestrator + planner | Claude Code, Opus 5 | **$0 marginal** (subscription) | — |
| SIMPLE | Ollama, Qwen3 8B | **$0** | 60–140 s |
| MEDIUM | DeepSeek V4.1 Flash | ~$0.15 / $0.60 per M | ~20 s |
| HARD | DeepSeek V4.1 Flash, thinking high | ~$0.15 / $0.60 per M | ~40 s |
| Integration + review + fix | Claude Code, Opus 5 | **$0 marginal** (subscription) | — |

The local tier is by far the slowest in wall-clock terms. It is worth it only when the task is genuinely trivial: at SIMPLE scope you are trading a minute of latency for a few cents, and the model needs no reasoning to get it right. Anything larger belongs on DeepSeek, which is both faster and better.

DeepSeek is the only real cash spend. A typical feature (≈200K in / 20K out) costs about **$0.04**.

### Why we do not log into pi with Anthropic

Logging into pi with a Claude Pro/Max account bills usage as **extra usage**, per token, rather than against your plan limits. That is why the Opus layer lives in Claude Code itself rather than inside pi. pi is only an executor for the cheap models.

### The real constraint: quota

The Opus layer costs no money but it does consume **plan quota**. The skill is written with that in mind: routine code writing is delegated, judgment and integration stay with Opus. Track it with `/usage` inside `claude`.

## Install

```bash
git clone git@github.com:muratcankuruoffical/pi-orchestra.git ~/pi-orchestra
cd ~/pi-orchestra && ./install.sh
```

Then connect your DeepSeek key:

```bash
pi          # → /login → DeepSeek → paste the key
```

Verify everything is in place:

```bash
./install.sh --check
```

```
==> Status
  ✓ pi 0.85.1
  ✓ Claude Code 2.1.268 — the orchestrator layer
  ✓ local model ready (qwen3-local, 32K context)
  ✓ DeepSeek key configured
  ✓ orchestra is on PATH
  ✓ Claude Code skill installed
```

`--check` installs nothing; it only inspects. When something breaks later, start here.

### Make it actually fire

A Claude Code skill is model-invoked: its description is a suggestion, and when a task arrives with clear intent the model often just starts working. In practice the skill will not fire reliably on its own.

The installer therefore copies `ORCHESTRA.md` into `~/.claude/` and adds `@ORCHESTRA.md` to your global `CLAUDE.md`. `CLAUDE.md` is always in context, so the directive holds. Verified: with the directive in place, a "fix this typo" request invoked the skill first and classified the tier before touching any file; without it, the same request was handled directly.

It also allowlists two low-risk commands so they do not prompt every time:

```json
{ "permissions": { "allow": ["Bash(orchestra simple *)", "Bash(orchestra init)", "Bash(orchestra init *)"] } }
```

`orchestra simple` runs the local model, which has no `bash` tool and can only edit files. `medium` and `hard` give the remote model shell access, so they keep prompting — approve those yourself.

The installer is idempotent and does not overwrite your existing settings. It:

- installs `pi` and `pi-lens` (bypassing npm's `minimumReleaseAge` gate)
- installs Ollama, downloads `qwen3:8b`, creates the 32K-context `qwen3-local` alias
- adds the `ollama` provider and the `deepseek-flash` model to `~/.pi/agent/models.json`
- links `bin/orchestra` into `~/.local/bin/` and the skill into `~/.claude/skills/orchestra`
- installs `ORCHESTRA.md` and wires it into your global `CLAUDE.md`
- allowlists `orchestra simple` and `orchestra init`

### Requirements

- **Claude Code** — installed and logged in (this is the orchestrator)
- Node **≥ 22.19** (pi's requirement)
- `jq`, Homebrew
- ~6 GB disk, ≥16 GB RAM (for the local model)

## Usage

Run `claude` in any project directory and talk to it normally:

```
add rate limiting to the auth middleware
```

The `orchestra` skill takes over: Claude picks the tier, delegates, verifies, integrates, and reports what it did.

You can also force a tier: *"do this locally"*, *"this one is hard"*.

### What a session looks like

```
> add rate limiting to the auth middleware

→ MEDIUM: 3 files (middleware, config, test), follows the existing middleware pattern.
  [orchestra] ds-worker → deepseek/deepseek-flash (thinking=off)

  Changed: app/Http/Middleware/RateLimit.php (new), config/auth.php, tests/Feature/RateLimitTest.php
  Verified: php artisan test --filter=RateLimit → 4 passed
  Integration: renamed the config key to match the existing convention.
  Remaining risk: assumes a Redis store; with a file cache the limit becomes per-process.
```

Opus classified, DeepSeek wrote, Opus verified and integrated. The only cash spend was a few cents on the DeepSeek side.

### What goes where

| You say | What happens |
|---|---|
| "this variable name is wrong, fix it" | SIMPLE → local model, $0 |
| "add filtering to this endpoint" | MEDIUM → DeepSeek |
| "there's a race condition in the payment flow" | HARD → DeepSeek + thinking high, Opus makes the call |
| "how should we structure this?" | Not delegated — pure judgment, stays with Opus |
| "run the tests" | Not delegated — Opus runs them itself |

### Using the CLI directly

```bash
orchestra simple "Fix the typo in formatDate in src/utils/date.ts"
orchestra medium "Add a POST /api/invoices endpoint following app/Http/Controllers/OrderController.php"
orchestra hard   "The order list issues N+1 queries; find the root cause and fix it"

orchestra simple --dry-run "..."     # see which model would run, without running it
orchestra medium --cwd ~/project "..."
```

When the working directory is a git repository, `orchestra` prints the resulting diff automatically.

## Tracking quota and cost

```bash
# Claude subscription quota — consumed by the orchestrator and integration layers
claude    # then: /usage

# DeepSeek spend
open https://platform.deepseek.com/usage
```

Past 80% quota, do not push MEDIUM work down to the local model — instead postpone HARD work and batch up SIMPLE tasks locally. The orchestrator itself is Opus, so every session carries a baseline cost.

## Classification rubric

Full rules live in `claude-skill/SKILL.md`. In short:

**SIMPLE** — all must hold: single file, under ~20 lines, the correct fix is unambiguous, no impact on architecture/API/schema/auth/payments, no new dependency.

**MEDIUM** — 2–10 files, a feature or refactor with clear boundaries, within existing patterns.

**HARD** — any one suffices: an architecture decision, an unclear root cause, performance/concurrency/security, expensive to undo (migrations, auth, payments, public API), 10+ files.

Rule of thumb: **when in doubt, go one tier up.**

What stays with the orchestrator and is never delegated: the architectural decision itself, requirement clarification, verification, review, integration, and writing the brief.

## Per-project context

Run this once per project:

```bash
cd ~/projects/my-app
orchestra init
```

```
Project: /Users/me/projects/my-app
  ✓ CLAUDE.md found — inherited automatically
  ✓ bridged 5 skill(s) from .claude/skills via .pi/settings.json
```

Two different mechanisms are at work, and only one needs setup:

**`CLAUDE.md` / `AGENTS.md` — automatic.** pi discovers and loads them itself, so every delegated model starts with your architecture rules, naming conventions and constraints. Nothing to configure. Verified on a 523-line `CLAUDE.md`: the delegated model answered questions about the project's global scopes and traits without reading a single file.

**`.claude/skills` — needs the bridge.** pi looks for skills under `.pi/skills` and never sees Claude Code's directory. `orchestra init` writes a three-line `.pi/settings.json` pointing at it:

```json
{ "skills": ["../.claude/skills"] }
```

Skills load on demand: their name and description go into the system prompt, and the model reads the `SKILL.md` body itself when the task calls for it. Commit `.pi/settings.json` so your team shares it.

If a project has no `CLAUDE.md`, write one — or start from `examples/AGENTS.example.md`. Recording the verification commands, the pattern files worth imitating, and the "touching this means HARD tier" areas measurably improves classification quality.

## Layout

```
claude-skill/SKILL.md   Claude Code orchestrator skill (rubric + protocol)
bin/orchestra           delegation CLI — tier → model + system prompt
agents/
  local-coder.md        SIMPLE → ollama/qwen3-local, no bash, ESCALATE protocol
  ds-worker.md          MEDIUM → deepseek/deepseek-flash, thinking off
  ds-architect.md       HARD   → deepseek/deepseek-flash, thinking high
config/models.json      ollama provider + deepseek-flash definition
examples/               AGENTS.md and project settings templates
install.sh
```

## Design decisions

**The local model is Qwen3 8B, not Qwen2.5-Coder.** Qwen2.5-Coder 7B writes better code (88% HumanEval) but **cannot call tools**: although Ollama's template asks for `<tool_call>` tags, the model emits bare JSON, so no file edit ever happens. Verified by hitting the Ollama API directly — neither the base model nor a num_ctx alias returns `tool_calls`. Qwen3 emits them natively. In an agentic loop, being able to call tools comes before code quality.

**The local model has no `bash`.** A small model plus shell access is a combination worth avoiding. When the work exceeds its scope, `local-coder` returns `ESCALATE: <reason>` instead of writing code, and the orchestrator raises the tier.

**Verification always belongs to the orchestrator.** Trusting a "tests passed" claim is the easiest way for this architecture to break. Opus runs the command and reads the output itself.

**`orchestra` prints the diff itself.** Models normalize code style (quote characters, indentation) beyond the requested change, and no amount of prompting stopped it — one even reported that it had changed nothing else. This happens at every tier, not just the local one. So the defense is mechanical rather than a matter of trusting the model: the diff always lands in front of the orchestrator.

**Delegated runs disable pi extensions (`-ne`).** `pi-lens` indexes the whole project at startup, which is fine on a small repo and unusable on a large one: on a 5,200-file Laravel project the same task finished in 7 seconds with extensions off and had not finished after five minutes with them on. Delegation has to be predictable, so extensions stay off.

**The fix loop is capped at 2 rounds.** After that the system stops and reports, rather than burning quota and money in a loop.

**Small fixes are not delegated.** Re-delegating a three-line type or import fix costs more in latency than it saves; the orchestrator does it itself.

## Troubleshooting

Always start with `./install.sh --check`.

**`Cannot find module '.../pi-ai/dist/index.js/compat'`**

If npm has `minimumReleaseAge` configured, `npm install -g @earendil-works/pi-coding-agent` installs an older pi that is incompatible with its extensions.

```bash
npm install -g --min-release-age=0 @earendil-works/pi-coding-agent pi-lens
```

**`pi list` is empty / packages not found**

pi looks under whichever node version is active. If you switched versions with nvm, reinstall the packages under that version. `install.sh` runs `nvm use default` at startup.

**`Agent definition not found: .../agents/local-coder.md`**

`orchestra` resolves the repo root through its symlink. If you moved the repo, re-run `./install.sh` to refresh the links.

**The local model download stalls**

Ollama downloads in parts and resumes where it left off. If progress stops, switch networks and run:

```bash
ollama pull qwen3:8b
```

Track progress with `du -k ~/.ollama/models/blobs/*-partial` — the file is preallocated, so `ls -lh` shows a constant size; real progress is in the allocated block count.

**DeepSeek `Insufficient Balance` (HTTP 402)**

The key is valid but the balance is empty; top up at `platform.deepseek.com`. Note that an invalid model id returns 404, not 402 — do not confuse the two.

**The skill never fires / no `[orchestra]` line appears**

Claude wrote the code itself instead of delegating. Check that `~/.claude/CLAUDE.md` contains `@ORCHESTRA.md` and that `~/.claude/ORCHESTRA.md` exists. Skills alone are not enough; the directive in `CLAUDE.md` is what makes it reliable. Skills and `CLAUDE.md` load at session start, so restart `claude` after installing.

**Ollama is not running**

```bash
open -a Ollama          # or: ollama serve
ollama list             # if this answers, it is ready
```

## License

MIT
