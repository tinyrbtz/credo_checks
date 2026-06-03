# Changelog

All notable changes to this project will be documented in this file.

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
