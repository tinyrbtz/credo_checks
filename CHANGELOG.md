# Changelog

All notable changes to this project will be documented in this file.

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
