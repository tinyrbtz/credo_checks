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

        2. **Long single-line class attrs must be broken across multiple
           lines.** When the line containing a `class={...}` or
           `class="..."` exceeds `:max_line_length` characters as displayed
           by the editor (default `98`, matching the Elixir formatter
           convention), the class attr should be converted to a multi-line
           list with one logical group per line. Long horizontal class
           lists are very hard to read and review.

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
    |> Enum.reduce(ctx, fn {kind, offset, content}, ctx ->
      line_no = line_fn.(offset)
      line_text = Enum.at(lines, offset, "")
      single_line? = not String.contains?(content, "\n")

      cond do
        kind == :interp and needs_brackets?(content) ->
          put_issue(ctx, issue_for(ctx, :no_brackets, line_no))

        single_line? and String.length(line_text) > max_line_length ->
          put_issue(ctx, issue_for(ctx, {:too_long, kind}, line_no, max_line_length))

        true ->
          ctx
      end
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

  defp issue_for(ctx, {:too_long, kind}, line_no, max_line_length) do
    {trigger, hint} =
      case kind do
        :interp ->
          {"class={", "split the existing list across multiple lines."}

        :literal ->
          {~s(class="),
           ~s(convert to `class={[ ... ]}` and split the strings across multiple lines.)}
      end

    format_issue(ctx,
      message:
        "Line containing `#{trigger}...` exceeds #{max_line_length} characters. " <>
          "To stay readable, " <> hint,
      trigger: trigger,
      line_no: line_no
    )
  end
end
