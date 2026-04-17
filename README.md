# Tiny Robots Credo Checks

[![CI](https://github.com/tinyrbtz/credo_checks/actions/workflows/ci.yml/badge.svg)](https://github.com/tinyrbtz/credo_checks/actions/workflows/ci.yml)
[![Hex version](https://img.shields.io/hexpm/v/rbtz_credo_checks.svg "Hex version")](https://hex.pm/packages/rbtz_credo_checks)
[![Hex downloads](https://img.shields.io/hexpm/dt/rbtz_credo_checks.svg "Hex downloads")](https://hex.pm/packages/rbtz_credo_checks)
[![License](http://img.shields.io/:license-mit-blue.svg)](http://doge.mit-license.org)

**Highly opinionated** [Credo](https://hexdocs.pm/credo/) checks used by [Tiny Robots](https://github.com/tinyrbtz). They encode the Elixir / Phoenix / LiveView conventions we rely on across our apps.

These checks are **opinionated by design** — they enforce the Tiny Robots house style and may not be suitable (or desired) for contribution upstream to mainline Credo. They're published here so our projects can share them, but anyone sharing our conventions is welcome to use them.

## Available checks

See the individual modules for full descriptions and examples.

### Design

- `Rbtz.CredoChecks.Design.BareScriptInHeex`: Forbids raw `<script>` tags in HEEx templates — use a `phx-hook`, the root layout, or import through the asset bundler.
- `Rbtz.CredoChecks.Design.CnInClassList`: Enforces correct use of the `cn(...)` class-merging helper in HEEx `class={...}` attributes — flags `cn([...])` with no `@assign` (wasted), bare lists mixing literal classes with any caller-provided assign (unwrapped, so TwMerge can't dedupe), and `cn(...)` calls where assigns aren't listed last (TwMerge keeps the last value, so assigns before literals lose their override). Configurable via `:helper_name` (default `"cn"`).
- `Rbtz.CredoChecks.Design.CustomAliasInRouterScope`: Forbids manual `alias` statements inside Phoenix `scope` blocks.
- `Rbtz.CredoChecks.Design.PreferLogsterInLib`: Forbids the standard `Logger` module in application code under `lib/` — use [Logster](https://hex.pm/packages/logster) instead.
- `Rbtz.CredoChecks.Design.RawHtmlElementsInHeex`: Forbids raw `<button>`, `<input>`, `<select>`, `<textarea>`, and `<a>` in HEEx — use the app's components instead.
- `Rbtz.CredoChecks.Design.RawSvgInHeex`: Forbids raw `<svg>` tags in HEEx templates.

### Readability

- `Rbtz.CredoChecks.Readability.AtomHttpStatusCodes`: Forbids passing integer HTTP status codes to `Plug.Conn` / Phoenix — use atoms like `:not_found`.
- `Rbtz.CredoChecks.Readability.AwkwardPipe`: Flags pipe usages that hurt readability without giving chaining benefit — pipe on either side of `&&` / `||` / `++` / `<>` / `in` / `and` / `or`, pipes into any `Kernel.` operator form (e.g. `Kernel.&&` / `Kernel.||` / `Kernel.+` / `Kernel.-` / `Kernel.==` / `Kernel.<` / `Kernel.in`), single-step pipes in tuple literals / string interpolation / non-first arg positions / single-line lambdas, any pipe joined in an `if` / `unless` / `cond` condition, and single-step pipes on the RHS of `<-` inside HEEx `:for=` / `for` comprehensions.
- `Rbtz.CredoChecks.Readability.ClassAttrFormatting`: Enforces HEEx `class={...}` attributes use list syntax for multiple values, and breaks long single-line `class={...}` / `class="..."` attrs across multiple lines (configurable `:max_line_length`, default 98).
- `Rbtz.CredoChecks.Readability.LiveViewCallbackOrder`: Enforces the canonical callback order in `Phoenix.LiveView` modules: `mount` → `handle_params` → `handle_event` → `handle_info` → `handle_async` → helpers → `render`.
- `Rbtz.CredoChecks.Readability.PreferBooleanDataAttrShorthand`: Forbids `data-[name]:` bracket-variant syntax for boolean data attributes — use `data-name:` instead, reserving brackets for value matching (`data-[state=open]:`).
- `Rbtz.CredoChecks.Readability.PreferCapture`: Encourages the capture syntax (`&foo/1`, `&Mod.foo/2`, `&(&1 * 2)`) over `fn x -> ... end` when the anonymous function just forwards its arguments to another call in the same order, applies a single operator, or partially applies a call.
- `Rbtz.CredoChecks.Readability.PreferSigilSForEscapedQuotes`: Encourages the `~s` sigil for strings that would otherwise need `\"` escapes.
- `Rbtz.CredoChecks.Readability.PreferToTimeout`: Encourages `to_timeout(minute: 15)` (Elixir 1.17+) over Erlang's `:timer.seconds/1`, `:timer.minutes/1`, `:timer.hours/1`, and `:timer.hms/3`.
- `Rbtz.CredoChecks.Readability.ShorthandDefMustBeCompact`: Forbids the shorthand `def name(args), do: body` form whose body spans more than one line — switch to a `do...end` block when the body has to wrap. Multi-line heads (e.g. nested pattern matches) are fine as long as the body stays on a single line.
- `Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering`: Encourages numbered variables to use a separating underscore: `user_1`, `user_2` (not `user1`, `user2`). Configurable via `:exclude`.
- `Rbtz.CredoChecks.Readability.TopLevelAliasImportRequire`: Ensures `alias`, `import`, and `require` statements appear only at the top level of a module.

### Refactor

- `Rbtz.CredoChecks.Refactor.PreferEctoMigrationHelper`: Discourages raw SQL `execute("...")` in Ecto migrations when an equivalent migration helper exists (e.g. `CREATE TABLE`, `ALTER TABLE`, `CREATE INDEX`). Raw SQL for `CREATE EXTENSION`, data backfills, etc. is allowed.
- `Rbtz.CredoChecks.Refactor.PreferForAttrOverForBlock`: Prefers `:for={item <- @collection}` directly on an element over a `<%= for ... do %>` EEx block when the block wraps a single element.
- `Rbtz.CredoChecks.Refactor.PreferTextColumns`: Ensures Ecto migrations use `:text` rather than `:string` for column types.
- `Rbtz.CredoChecks.Refactor.PreferToFormInTemplates`: Forbids passing a raw `@changeset` to a `<form>` / `<.form>` in HEEx — wrap with `to_form/2` and pass `@form` instead.
- `Rbtz.CredoChecks.Refactor.RawHtmlMatchInLiveViewTests`: Forbids `=~` matches against string literals in LiveView test files.
- `Rbtz.CredoChecks.Refactor.RedundantThen`: Flags unnecessary uses of `Kernel.then/2` — when the function passed to `then/2` is a simple pass-through or partial application where the piped value already lands at the first-arg position, `then/2` is pure indirection and can be removed.

### Warning

- `Rbtz.CredoChecks.Warning.AssertNonEmptyBeforeIterate`: Requires tests that iterate a collection with `assert`/`refute` inside to first assert the collection is non-empty.
- `Rbtz.CredoChecks.Warning.BooleanDataAttrCoalescesNil`: Requires boolean `data-*` attributes in HEEx to coalesce with `nil` (e.g. `data-disabled={@disabled || nil}`) so the attribute is omitted when falsy.
- `Rbtz.CredoChecks.Warning.DisableMigrationLock`: Forbids `@disable_migration_lock true` in Ecto migration files.
- `Rbtz.CredoChecks.Warning.EnumEachInHeex`: Forbids `<% Enum.each %>` and other side-effecting EEx constructs in HEEx templates.
- `Rbtz.CredoChecks.Warning.LiveViewFormCanBeRehydrated`: Ensures LiveView forms (with `phx-submit`) also carry `id` and `phx-change` so state survives deploys and reconnects.
- `Rbtz.CredoChecks.Warning.PhxClickAwayWithoutId`: Requires every element with `phx-click-away` to also carry an `id` attribute.
- `Rbtz.CredoChecks.Warning.PhxHookComponentWithoutStableId`: Requires function components whose template uses `phx-hook` to bind the hook target to a stable DOM `id` — either a literal (`id="foo"`) or `id={@name}` bound to an attr declared with `required: true` or a binary `default:`.
- `Rbtz.CredoChecks.Warning.PhxHookWithoutId`: Requires every element with `phx-hook` to also carry an `id` attribute.
- `Rbtz.CredoChecks.Warning.PhxUpdateStreamWithoutId`: Requires every element with `phx-update="stream"` to also carry an `id` attribute.
- `Rbtz.CredoChecks.Warning.PreferGetFieldOnChangeset`: Requires `Ecto.Changeset.get_field/2` over `changeset.field` or `changeset[:field]` — direct access returns the original field, not the changeset's current (potentially changed) value, which is a frequent source of subtle bugs.
- `Rbtz.CredoChecks.Warning.PushEventSocketBinding`: Requires the result of `push_event/3` to be reassigned to `socket`.
- `Rbtz.CredoChecks.Warning.ReqTestWithoutVerifyOnExit`: Requires test modules that mock HTTP with `Req.Test.stub`/`expect` to call `Req.Test.verify_on_exit!/0` in a `setup`/`setup_all` block.
- `Rbtz.CredoChecks.Warning.SetMimicGlobal`: Forbids enabling Mimic in global mode (`set_mimic_global`) inside test files.
- `Rbtz.CredoChecks.Warning.SortKeywordValidateResult`: Requires `Enum.sort/1` between `Keyword.validate!/2` and any binding that pattern-matches the result — unsorted results can silently break pattern matches on keyword list order.
- `Rbtz.CredoChecks.Warning.StringInterpolationInClassAttr`: Forbids string interpolation inside HEEx `class=` attributes — Tailwind's static class extractor can't see interpolated classes, so they silently don't ship in the compiled CSS.
- `Rbtz.CredoChecks.Warning.UnnamedOtpProcess`: Requires `DynamicSupervisor` and `Registry` child specs to declare a `:name`.

## Installation and configuration

1. Add `rbtz_credo_checks` to your `mix.exs` dependencies:

   ```elixir
   def deps do
     [
       {:rbtz_credo_checks, "~> 0.1", only: [:dev, :test], runtime: false}
     ]
   end
   ```

2. Run `mix deps.get`.

3. Add the desired checks to your `.credo.exs`:

   ```elixir
   %{
     configs: [
       %{
         checks: %{
           enabled: [
             {Rbtz.CredoChecks.Design.BareScriptInHeex, []},
             {Rbtz.CredoChecks.Design.CnInClassList, []},
             {Rbtz.CredoChecks.Design.CustomAliasInRouterScope, []},
             {Rbtz.CredoChecks.Design.PreferLogsterInLib, []},
             {Rbtz.CredoChecks.Design.RawHtmlElementsInHeex, []},
             {Rbtz.CredoChecks.Design.RawSvgInHeex, []},
             {Rbtz.CredoChecks.Readability.AtomHttpStatusCodes, []},
             {Rbtz.CredoChecks.Readability.AwkwardPipe, []},
             {Rbtz.CredoChecks.Readability.ClassAttrFormatting, []},
             {Rbtz.CredoChecks.Readability.LiveViewCallbackOrder, []},
             {Rbtz.CredoChecks.Readability.PreferBooleanDataAttrShorthand, []},
             {Rbtz.CredoChecks.Readability.PreferCapture, []},
             {Rbtz.CredoChecks.Readability.PreferSigilSForEscapedQuotes, []},
             {Rbtz.CredoChecks.Readability.PreferToTimeout, []},
             {Rbtz.CredoChecks.Readability.ShorthandDefMustBeCompact, []},
             {Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering, []},
             {Rbtz.CredoChecks.Readability.TopLevelAliasImportRequire, []},
             {Rbtz.CredoChecks.Refactor.PreferEctoMigrationHelper, []},
             {Rbtz.CredoChecks.Refactor.PreferForAttrOverForBlock, []},
             {Rbtz.CredoChecks.Refactor.PreferTextColumns, []},
             {Rbtz.CredoChecks.Refactor.PreferToFormInTemplates, []},
             {Rbtz.CredoChecks.Refactor.RawHtmlMatchInLiveViewTests, []},
             {Rbtz.CredoChecks.Refactor.RedundantThen, []},
             {Rbtz.CredoChecks.Warning.AssertNonEmptyBeforeIterate, []},
             {Rbtz.CredoChecks.Warning.BooleanDataAttrCoalescesNil, []},
             {Rbtz.CredoChecks.Warning.DisableMigrationLock, []},
             {Rbtz.CredoChecks.Warning.EnumEachInHeex, []},
             {Rbtz.CredoChecks.Warning.LiveViewFormCanBeRehydrated, []},
             {Rbtz.CredoChecks.Warning.PhxClickAwayWithoutId, []},
             {Rbtz.CredoChecks.Warning.PhxHookComponentWithoutStableId, []},
             {Rbtz.CredoChecks.Warning.PhxHookWithoutId, []},
             {Rbtz.CredoChecks.Warning.PhxUpdateStreamWithoutId, []},
             {Rbtz.CredoChecks.Warning.PreferGetFieldOnChangeset, []},
             {Rbtz.CredoChecks.Warning.PushEventSocketBinding, []},
             {Rbtz.CredoChecks.Warning.ReqTestWithoutVerifyOnExit, []},
             {Rbtz.CredoChecks.Warning.SetMimicGlobal, []},
             {Rbtz.CredoChecks.Warning.SortKeywordValidateResult, []},
             {Rbtz.CredoChecks.Warning.StringInterpolationInClassAttr, []},
             {Rbtz.CredoChecks.Warning.UnnamedOtpProcess, []}
           ]
         }
       }
     ]
   }
   ```

## License

MIT. See [LICENSE](LICENSE).
