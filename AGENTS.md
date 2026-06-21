# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A published Hex package (`rbtz_credo_checks`) of **highly opinionated** custom [Credo](https://hexdocs.pm/credo/) checks encoding Tiny Robots' Elixir / Phoenix / LiveView house style. There is no application runtime — the entire codebase is Credo check modules plus a thin discovery/config API. Elixir 1.19 / OTP 28 (see `.tool-versions`).

## Commands

- `mix verify` — the full gate, and exactly what CI runs. In order: `compile --force --warnings-as-errors`, `format --check-formatted`, `cspell` (spell-check via `npx cspell`), `test --cover --raise --warnings-as-errors`, `credo`. Run this before considering work done.
- `mix test` — run tests. Single file: `mix test test/rbtz/credo_checks/<category>/<name>_test.exs`. Single test: append `:LINE`.
- `mix credo` / `mix credo --strict` — the project dogfoods its own checks (see `.credo.exs`).
- `mix format` — apply formatting (`verify` only _checks_ it).
- `mix setup` — `deps.get` + `deps.compile`.

## Conventions

- **Always use Elixir standard-library functions in tests and examples** — in test cases, `# Bad` / `# Good` docstring examples, and any illustrative snippet. Even when a user describes the pattern with their own app-specific code, do not reproduce that snippet verbatim or reference internal/domain modules: re-express the same pattern using stdlib functions (e.g. `File.read/1`, `Map.fetch/2`, `Enum.map/2`). These checks are published publicly, so a reader with no knowledge of our codebase must be able to follow the reasoning. Treat any example a user provides as a _description_ of the pattern to detect, then rewrite it with stdlib equivalents.
- **Record every new check in `CHANGELOG.md`** under the `## Unreleased` heading (add that heading if it isn't there yet), following the existing `**New check** \`Rbtz.CredoChecks...\` — …` style.
