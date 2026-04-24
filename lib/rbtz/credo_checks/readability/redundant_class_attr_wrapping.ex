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
    |> find_class_interps()
    |> Enum.reduce(ctx, fn {offset, content}, ctx ->
      case classify(content) do
        :ok -> ctx
        kind -> put_issue(ctx, issue_for(ctx, kind, line_fn.(offset)))
      end
    end)
  end

  defp find_class_interps(heex) do
    heex
    |> :binary.matches("class={")
    |> Enum.flat_map(fn {start, _len} ->
      open_pos = start + byte_size("class={")
      rest = binary_part(heex, open_pos, byte_size(heex) - open_pos)

      case HeexSource.capture_interpolation(rest) do
        {:ok, content} ->
          offset = heex |> binary_part(0, start) |> HeexSource.count_newlines()
          [{offset, content}]

        :unterminated ->
          []
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
      top_level_comma?(inner, init_state()) -> :ok
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

  # Top-level comma scanner — same contract as the one in ClassAttrFormatting.
  # Tracks brace / bracket / paren depth and in-string state so commas inside
  # `if(@x, do: "foo")`, `Map.get(...)`, charlist literals, etc. don't count.
  defp init_state, do: %{bd: 0, bracd: 0, pard: 0, str: nil}

  defp top_level_comma?(<<>>, _s), do: false

  defp top_level_comma?(<<?\\, _c, rest::binary>>, %{str: str} = s) when str != nil do
    top_level_comma?(rest, s)
  end

  defp top_level_comma?(<<c, rest::binary>>, %{str: str} = s) when str != nil and c == str do
    top_level_comma?(rest, %{s | str: nil})
  end

  defp top_level_comma?(<<_c, rest::binary>>, %{str: str} = s) when str != nil do
    top_level_comma?(rest, s)
  end

  defp top_level_comma?(<<?", rest::binary>>, s), do: top_level_comma?(rest, %{s | str: ?"})
  defp top_level_comma?(<<?', rest::binary>>, s), do: top_level_comma?(rest, %{s | str: ?'})

  defp top_level_comma?(<<?{, rest::binary>>, %{bd: bd} = s) do
    top_level_comma?(rest, %{s | bd: bd + 1})
  end

  defp top_level_comma?(<<?}, rest::binary>>, %{bd: bd} = s) do
    top_level_comma?(rest, %{s | bd: bd - 1})
  end

  defp top_level_comma?(<<?[, rest::binary>>, %{bracd: bracd} = s) do
    top_level_comma?(rest, %{s | bracd: bracd + 1})
  end

  defp top_level_comma?(<<?], rest::binary>>, %{bracd: bracd} = s) do
    top_level_comma?(rest, %{s | bracd: bracd - 1})
  end

  defp top_level_comma?(<<?(, rest::binary>>, %{pard: pard} = s) do
    top_level_comma?(rest, %{s | pard: pard + 1})
  end

  defp top_level_comma?(<<?), rest::binary>>, %{pard: pard} = s) do
    top_level_comma?(rest, %{s | pard: pard - 1})
  end

  defp top_level_comma?(<<?,, _rest::binary>>, %{bd: 0, bracd: 0, pard: 0, str: nil}), do: true
  defp top_level_comma?(<<_c, rest::binary>>, s), do: top_level_comma?(rest, s)

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
