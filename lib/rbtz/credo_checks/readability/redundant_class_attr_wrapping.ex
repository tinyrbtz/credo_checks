defmodule Rbtz.CredoChecks.Readability.RedundantClassAttrWrapping do
  use Credo.Check,
    id: "RBTZ0050",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: ~s"""
      Flags HEEx `class={...}` attributes whose wrapping is unnecessary.
      Three shapes are reported, each with a simpler equivalent form:

        1. `class={"foo bar"}` — a static string inside interp braces.
           Use the literal attribute form: `class="foo bar"`.

        2. `class={["foo bar"]}` — a single static string inside a list.
           Drop the list and the interp: `class="foo bar"`.

        3. `class={[@cls]}` / `class={[some_fn()]}` — a single expression
           inside a list. Drop the list wrapper: `class={@cls}` /
           `class={some_fn()}`.

      Deliberately **not** flagged:

        - `class={"foo \#{@x} bar"}` — the interp braces are required once
          the string contains a `\#{...}` expression.

        - `class={["foo", "bar"]}` — multi-element lists. The companion
          `Rbtz.CredoChecks.Readability.ClassAttrFormatting` rule actively
          recommends splitting long class values into list elements, so
          collapsing these would contradict that neighbouring rule.

        - `class={[]}` / `class={""}` / `class={nil}` — empty/nil shapes.
          A different concern (dead attribute) and often intentional.

      # Note on case 3

      HEEx's `class={...}` special-cases lists: nested lists flatten and
      `nil`/`false` entries are filtered. For most expressions (`@cls`,
      `if(@x, do: "foo")`, function calls returning strings or lists),
      `class={[expr]}` and `class={expr}` render identically. If the codebase
      relies on the subtle difference between `class={[nil]}` (empty class
      attribute) and `class={nil}` (attribute omitted), refactor the
      expression to be explicit rather than relying on the list wrapper.

      # Bad

          <a class={"px-2 text-white"}>x</a>
          <a class={["px-2 text-white"]}>x</a>
          <a class={[@extra]}>x</a>

      # Good

          <a class="px-2 text-white">x</a>
          <a class={@extra}>x</a>
          <a class={["px-2 text-white", @extra]}>x</a>
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template/2)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx) do
    heex
    |> HeexSource.find_attr_bodies("class={", &HeexSource.capture_interpolation/1)
    |> Enum.reduce(ctx, fn {offset, content}, ctx ->
      case classify(content) do
        :ok -> ctx
        kind -> put_issue(ctx, issue_for(ctx, kind, line_fn.(offset)))
      end
    end)
  end

  defp classify(content) do
    trimmed = String.trim(content)

    cond do
      trimmed == "" -> :ok
      String.starts_with?(trimmed, "[") -> classify_list(trimmed)
      static_string?(trimmed) -> :bare_string
      true -> :ok
    end
  end

  defp classify_list(list) do
    if String.ends_with?(list, "]") do
      list
      |> binary_part(1, byte_size(list) - 2)
      |> String.trim()
      |> classify_list_inner()
    else
      :ok
    end
  end

  defp classify_list_inner(""), do: :ok

  defp classify_list_inner(inner) do
    cond do
      HeexSource.top_level_comma?(inner) -> :ok
      static_string?(inner) -> :single_string_list
      true -> :single_expr_list
    end
  end

  # A well-formed double-quoted static string: starts with `"`, ends at the
  # terminal `"` exactly at the end of input, contains no unescaped `#{`,
  # and has at least one content byte (so `""` is rejected as "empty").
  # Inner content is any mix of: ordinary chars, backslash-escapes, or a `#`
  # that isn't followed by `{`.
  @static_string_regex ~r/\A"(?:[^"\\#]|\\.|#(?!\{))+"\z/s

  defp static_string?(s) when is_binary(s), do: Regex.match?(@static_string_regex, s)

  defp issue_for(ctx, :bare_string, line_no) do
    format_issue(ctx,
      message:
        ~s(Redundant `class={"..."}` wrapping: a static string with no interpolation ) <>
          ~s(should use the literal form `class="..."`.),
      trigger: "class={",
      line_no: line_no
    )
  end

  defp issue_for(ctx, :single_string_list, line_no) do
    format_issue(ctx,
      message:
        ~s(Redundant `class={["..."]}` wrapping: a single static string inside a list ) <>
          ~s(should drop the list and the interp: `class="..."`.),
      trigger: "class={",
      line_no: line_no
    )
  end

  defp issue_for(ctx, :single_expr_list, line_no) do
    format_issue(ctx,
      message:
        "Redundant `class={[expr]}` wrapping: a single expression inside a list " <>
          "should drop the list wrapper: `class={expr}`. (Note: list wrappers filter " <>
          "nil/false entries — refactor explicitly if that behaviour matters.)",
      trigger: "class={",
      line_no: line_no
    )
  end
end
