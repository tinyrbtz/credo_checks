# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- **New check** `Rbtz.CredoChecks.Readability.FunctionSpacing` — requires
  consistent blank-line spacing around function definitions. Header blocks
  (`@doc`, `@impl`, `@spec`, `@dialyzer`, `@deprecated`, `@since`, `@decorate`
  / `@decorate_all`, plus full-line comments attached above/below those attrs)
  must be preceded by a blank line (unless the line above is the `defmodule` /
  `defprotocol` / `defimpl` opener) and sit flush against the first clause —
  never a blank line under the header. Header attributes may stack without
  blanks between them. Multi-clause functions (same name + arity; `def` /
  `defp` / `defmacro` / `defmacrop`) are compact when every clause is
  single-line, and separated (blank lines between clauses) when any clause is
  multi-line.

## 0.8.0

- **New check** `Rbtz.CredoChecks.Refactor.PreferWithOverCase` — flags a
  two-clause `case` whose only non-happy-path clause re-returns an error shape
  unchanged: an `{:error, ...}` tuple or the bare `:error` atom (e.g.
  `{:error, reason} -> {:error, reason}`). A `with` expresses this more
  directly, since its implicit `else` passes the non-matching value through.
  Non-error pass-through clauses (`nil -> nil`, `other -> other`), guarded
  clauses, a catch-all happy path paired with the error pass-through,
  identity cases, and `case`s with one or three-plus clauses are left alone.

## 0.7.1

- **`AtomHttpStatusCodes`**: now also flags integer status codes passed to the
  `Phoenix.ConnTest` assertion helpers `response/2`, `json_response/2`,
  `html_response/2`, and `redirected_to/2` (e.g. `json_response(conn, 200)` →
  `json_response(conn, :ok)`).

## 0.7.0

- **New** `Rbtz.CredoChecks.all/0` — returns every check in this library as a
  `{module, opts}` tuple, ready to append to the `enabled:` list in `.credo.exs`.
  The list is auto-discovered, so it stays in sync as checks are added. This is now
  the recommended way to enable the checks (see the README).
- **New** `Rbtz.CredoChecks.all_replacing/1` — like `all/0`, but takes `{module, opts}`
  replacements to customise a check's options, or `{module, false}` to disable it; an
  unknown module raises `ArgumentError`.

## 0.6.0

- **New check** `Rbtz.CredoChecks.Readability.ModuleAttrCollectionFormatting` —
  flags multi-line collections assigned to module attributes (word sigils,
  lists, maps/structs, and tuples) that put more than one item on a line. Each
  item should sit on its own line so the collection is easy to scan, diff, and
  update. Single-line collections are unaffected, however many items they hold.

## 0.5.0

- **New check** `Rbtz.CredoChecks.Readability.PreferBlockFormForMultilineIf` —
  forbids the keyword form `if cond, do: x, else: y` (and the `unless`
  equivalent) when the expression spans more than one line. Switch to the
  `do ... else ... end` block form. Single-line keyword form and block form
  are unaffected.

## 0.4.0

- **New check** `Rbtz.CredoChecks.Readability.PreferNilEquality` — prefers
  `x == nil` / `x != nil` over `is_nil(x)` / `not is_nil(x)` / `!is_nil(x)` in
  `if` / `unless` / `cond` / `case` conditions and `assert` / `refute`
  arguments. Walks through `and` / `or` / `&&` / `||` / `not` / `!`. Guards
  (`when ...`) and Ecto query DSL are unaffected.

## 0.3.0

- **`AwkwardPipe`**: new sub-rule (Rule 10) flags single-step pipes wrapped in
  parentheses just to dot-access their result — e.g. `(x |> URI.parse()).host`
  should be `URI.parse(x).host`.

## 0.2.0

- **New check** `Rbtz.CredoChecks.Readability.RedundantClassAttrWrapping` — flags HEEx
  `class={...}` attributes whose wrapping is unnecessary (`class={"foo"}` /
  `class={["foo"]}` → `class="foo"`; `class={[expr]}` → `class={expr}`).
- **`ClassAttrFormatting`**: the max-line-length rule now scans every source line a
  `class={...}` / `class="..."` attribute spans, not just the opening line. Long
  string literals buried inside a multi-line list are now flagged, and the issue is
  reported on the offending inner line.
- **Fix**: `HeexSource` now reports line numbers correctly for `~H""" ... """`
  heredoc sigils. Previously every issue was off by one because the AST's
  `line:` metadata points at the opening `~H"""` while content starts on the
  next line. Affects every HEEx-scanning check.

## 0.1.0

Initial release — 39 Credo checks (6 Design, 11 Readability, 6 Refactor, 16 Warning)
extracted from internal Tiny Robots use. See the [README](README.md) for the full list.
