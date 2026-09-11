# Project context

This file is loaded automatically by pi and Claude Code, and passed to every subagent.
Fill it in so the orchestrator can classify work correctly.

## Stack

<!-- e.g. Laravel 11 + Inertia + React 18 + TypeScript, MySQL 8, Redis -->

## Verification commands

<!-- the orchestrator will run these -->
- typecheck: `npm run typecheck`
- lint: `npm run lint`
- test: `npm test`

## Patterns

<!-- files worth imitating when writing new code -->
- Controller example: `app/Http/Controllers/...`
- Service example: `app/Services/...`
- Test example: `tests/Feature/...`

## Off-limits areas

<!-- anything listed here forces HARD tier -->
- `database/migrations/` — any migration is HARD tier
- `app/Http/Middleware/Auth*` — auth flow
- anything payment-related

## Known pitfalls

<!-- recurring mistakes a model could not know about -->
