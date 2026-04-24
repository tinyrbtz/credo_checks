defmodule Rbtz.CredoChecks.Readability.ClassAttrFormatting do
  use Credo.Check,
    id: "RBTZ0029",
    base_priority: :normal,
    category: :readability,
    param_defaults: [max_line_length: 98],
    explanations: [
      check: ~s"""
      Enforces two layout rules for HEEx `class` attributes:

        1. **Interpolated attrs with multiple values must use list syntax.**
           Comma-separated content inside `class={}` without surrounding
           brackets either fails to compile or is silently parsed as a
           tuple/keyword list. Wrap them in `[...]`. The most common shape
           this catches in practice is an unparenthesized `if` whose
           keyword-list commas leak to the top level of the attribute
           expression.

        2. **No class-attribute line may exceed the max line length.**
           Whether the attribute is on one line or broken across many,
           every source line spanned by a `class={...}` or `class="..."`
           attribute must stay within `:max_line_length` characters as
           displayed by the editor (default `98`, matching the Elixir
           formatter convention). Long lines — whether a flat single-line
           attribute or one long string literal buried inside a multi-line
           list — should be split into shorter logical groups.

      The check inspects every `~H` sigil and every `.heex` template
      referenced via `embed_templates`. Both rules can be violated by the
      same attribute; you'll get one issue per attribute. Line length is
      measured against the full source line (`String.length/1` of the line
      text, i.e. the column position the editor shows).

      Configure via `:max_line_length` (default `98`).

      # Bad — comma-separated without brackets

          <a class={if @cond, do: "x", else: "y"}>...</a>

      # Bad — single-line class attr exceeds the line limit

          <a class={["px-2 text-white", "py-5 bg-blue-600", "rounded-md border border-transparent"]}>x</a>
          <a class="px-2 text-white py-5 bg-blue-600 rounded-md border border-transparent hover:underline">x</a>

      # Bad — a single string inside a multi-line class attr exceeds the limit

          <a class={[
            "px-2 py-1 text-white bg-blue-600 rounded-md border border-transparent hover:underline focus:ring-2",
            @extra
          ]}>x</a>

      # Good

          <a class={if(@cond, do: "x", else: "y")}>...</a>

          <a class={[
            "px-2 text-white",
            "py-5 bg-blue-600",
            "rounded-md border border-transparent",
            "hover:underline"
          ]}>x</a>
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    max_line_length = Params.get(params, :max_line_length, __MODULE__)
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template(&1, &2, max_line_length))
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx, max_line_length) do
    lines = String.split(heex, "\n")

    heex
    |> find_class_attrs()
    |> Enum.reduce(ctx, &check_attr(&1, &2, lines, line_fn, max_line_length))
  end

  defp check_attr({:interp, offset, content} = attr, ctx, lines, line_fn, max_line_length) do
    if needs_brackets?(content) do
      put_issue(ctx, issue_for(ctx, :no_brackets, line_fn.(offset)))
    else
      check_length(attr, ctx, lines, line_fn, max_line_length)
    end
  end

  defp check_attr({:literal, _, _} = attr, ctx, lines, line_fn, max_line_length) do
    check_length(attr, ctx, lines, line_fn, max_line_length)
  end

  defp check_length({kind, offset, content}, ctx, lines, line_fn, max_line_length) do
    case find_too_long_line(lines, offset, content, max_line_length) do
      nil ->
        ctx

      {bad_idx, bad_text} ->
        put_issue(
          ctx,
          issue_for(ctx, {:too_long, kind}, line_fn.(bad_idx), bad_text, max_line_length)
        )
    end
  end

  defp find_too_long_line(lines, offset, content, max_line_length) do
    newlines = content |> :binary.matches("\n") |> length()

    offset..(offset + newlines)
    |> Enum.find_value(fn i ->
      line = Enum.at(lines, i, "")
      if String.length(line) > max_line_length, do: {i, line}, else: nil
    end)
  end

  defp find_class_attrs(heex) do
    find_attrs(heex, "class={", :interp, &HeexSource.capture_interpolation/1) ++
      find_attrs(heex, ~s(class="), :literal, &HeexSource.capture_string/1)
  end

  defp find_attrs(heex, prefix, kind, capture_fn) do
    heex
    |> :binary.matches(prefix)
    |> Enum.flat_map(fn {start, _len} ->
      open_pos = start + byte_size(prefix)
      rest = binary_part(heex, open_pos, byte_size(heex) - open_pos)

      case capture_fn.(rest) do
        {:ok, content} ->
          offset = heex |> binary_part(0, start) |> HeexSource.count_newlines()
          [{kind, offset, content}]

        :unterminated ->
          []
      end
    end)
  end

  defp needs_brackets?(content) do
    trimmed = String.trim_leading(content)

    not String.starts_with?(trimmed, "[") and
      top_level_comma?(content, %{bd: 0, bracd: 0, pard: 0, str: nil})
  end

  # Top-level comma scan over the captured content.
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

  defp issue_for(ctx, :no_brackets, line_no) do
    format_issue(ctx,
      message:
        ~s(Wrap multiple `class={...}` values in a list: `class={["a", "b"]}` instead of ) <>
          ~s(comma-separated values without brackets. Bare commas at the top level are invalid HEEx.),
      trigger: "class={",
      line_no: line_no
    )
  end

  defp issue_for(ctx, {:too_long, kind}, line_no, bad_text, max_line_length) do
    hint =
      case kind do
        :interp ->
          "split the list across multiple lines and break long strings into shorter groups."

        :literal ->
          ~s(convert to `class={[ ... ]}` and split the strings across multiple lines.)
      end

    format_issue(ctx,
      message:
        "HEEx `class` attribute has a line exceeding #{max_line_length} characters. " <>
          "To stay readable, " <> hint,
      trigger: bad_text |> String.trim_leading() |> String.slice(0, 40),
      line_no: line_no
    )
  end
end
