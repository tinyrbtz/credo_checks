defmodule Rbtz.CredoChecks.Readability.ModuleAttrCollectionFormatting do
  use Credo.Check,
    id: "RBTZ0053",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Encourages multi-line collections assigned to module attributes to list
      one item per line, so the collection stays easy to scan, diff, and update.

      Once a list / word sigil / map / tuple assigned to a `@module_attribute`
      is broken across multiple lines, cramming several items onto one line
      makes it hard to see what changed in a diff and easy to mis-edit. Putting
      each item on its own line keeps every addition or removal to a single
      line.

      Only module-attribute values are inspected, and only when the collection
      already spans more than one line. A single-line collection is always fine,
      no matter how many items it holds.

      Covered forms: word sigils (`~w[...]` / `~W[...]`), list literals
      (`[...]`, including keyword lists), maps and structs (`%{...}` /
      `%Mod{...}`), and tuples (`{...}`). Interpolated `~w` sigils are not
      inspected.

      # Bad — multi-line with more than one item on a line

          @allowed_extensions ~w[
            .png .jpg .jpeg
            .gif .webp
          ]

          @supported_locales [
            "en-US", "en-GB",
            "fr-FR", "de-DE"
          ]

          @retry_backoff {
            1_000, 2_000,
            5_000
          }

      # Good — one item per line

          @allowed_extensions ~w[
            .png
            .jpg
            .jpeg
            .gif
            .webp
          ]

          @supported_locales [
            "en-US",
            "en-GB",
            "fr-FR",
            "de-DE"
          ]

      # Good — a single line is fine, however many items

          @allowed_extensions ~w[.png .jpg .jpeg .gif .webp]
          @supported_locales ["en-US", "en-GB", "fr-FR", "de-DE"]
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    source = SourceFile.source(source_file)
    lines = String.split(source, "\n")

    source
    |> Credo.Code.to_tokens()
    |> walk(lines, ctx)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  # A module-attribute definition is `@name <value>`. Inspect the value.
  defp walk([{:at_op, _, :@}, {:identifier, _, _} | rest], lines, ctx) do
    {rest_after, ctx} = check_value(rest, lines, ctx)
    walk(rest_after, lines, ctx)
  end

  defp walk([_ | rest], lines, ctx), do: walk(rest, lines, ctx)
  defp walk([], _lines, ctx), do: ctx

  # Word sigils carry their content verbatim — analyse whitespace-separated
  # words per line. Interpolated `~w` has a multi-part body and is skipped.
  defp check_value([{:sigil, {sl, _, _}, name, parts, _, _, _} | rest], lines, ctx)
       when name in [:sigil_w, :sigil_W] do
    {rest, check_sigil(parts, sl, lines, ctx)}
  end

  # List literal (also covers bracketed keyword lists).
  defp check_value([{:"[", {ol, _, _}} | rest], lines, ctx) do
    scan_and_flag(rest, ol, lines, ctx)
  end

  # Tuple literal.
  defp check_value([{:"{", {ol, _, _}} | rest], lines, ctx) do
    scan_and_flag(rest, ol, lines, ctx)
  end

  # Map literal — `%{` tokenises as a `:%{}` marker followed by `{`.
  defp check_value([{:%{}, _}, {:"{", {ol, _, _}} | rest], lines, ctx) do
    scan_and_flag(rest, ol, lines, ctx)
  end

  # Struct literal — `%Mod{` / `%Mod.Sub{`: skip the alias path to the brace.
  defp check_value([{:%, _} | rest], lines, ctx) do
    case skip_to_brace(rest) do
      {ol, rest_after_brace} -> scan_and_flag(rest_after_brace, ol, lines, ctx)
      :none -> {rest, ctx}
    end
  end

  # Anything else (`@x 5`, `@x "s"`, `@moduledoc "..."`, ...) is not a
  # collection we format.
  defp check_value(rest, _lines, ctx), do: {rest, ctx}

  defp skip_to_brace([{:"{", {ol, _, _}} | rest]), do: {ol, rest}
  defp skip_to_brace([_ | rest]), do: skip_to_brace(rest)
  defp skip_to_brace([]), do: :none

  defp scan_and_flag(tokens, open_line, lines, ctx) do
    {offending, rest, close_line} = scan_collection(tokens, 1, nil, nil)

    if offending != nil and open_line != close_line do
      {rest, put_issue(ctx, issue_for(ctx, offending, lines))}
    else
      {rest, ctx}
    end
  end

  # Walks the collection body (depth starts at 1, just inside the opener),
  # tracking the line of a pending top-level comma. A top-level comma followed,
  # on the same line, by the next element means two items share that line.
  defp scan_collection([{op, {line, _, _}} | rest], depth, pending, off)
       when op in [:"[", :"(", :"{", :"<<"] do
    {pending, off} = maybe_offend(depth, line, pending, off)
    scan_collection(rest, depth + 1, pending, off)
  end

  defp scan_collection([{cl, {line, _, _}} | rest], depth, pending, off)
       when cl in [:"]", :")", :"}", :">>"] do
    if depth == 1 do
      {off, rest, line}
    else
      scan_collection(rest, depth - 1, pending, off)
    end
  end

  defp scan_collection([{:",", {line, _, _}} | rest], 1, _pending, off) do
    scan_collection(rest, 1, line, off)
  end

  defp scan_collection([{:",", _} | rest], depth, pending, off) do
    scan_collection(rest, depth, pending, off)
  end

  defp scan_collection([{:eol, _} | rest], depth, pending, off) do
    scan_collection(rest, depth, pending, off)
  end

  defp scan_collection([token | rest], depth, pending, off) do
    {pending, off} = maybe_offend(depth, token_line(token), pending, off)
    scan_collection(rest, depth, pending, off)
  end

  # A top-level element starting on the same line as the pending comma is the
  # second item on that line. Clear the pending comma either way.
  defp maybe_offend(1, line, line, off), do: {nil, off || line}
  defp maybe_offend(1, _line, _pending, off), do: {nil, off}
  defp maybe_offend(_depth, _line, pending, off), do: {pending, off}

  defp token_line(token) do
    {line, _, _} = elem(token, 1)
    line
  end

  defp check_sigil([content], sl, lines, ctx) when is_binary(content) do
    if String.contains?(content, "\n") do
      case first_multi_word_line(String.split(content, "\n"), 0) do
        nil -> ctx
        i -> put_issue(ctx, issue_for(ctx, sl + i, lines))
      end
    else
      ctx
    end
  end

  defp check_sigil(_parts, _sl, _lines, ctx), do: ctx

  defp first_multi_word_line([line | rest], i) do
    if line |> String.split() |> length() >= 2 do
      i
    else
      first_multi_word_line(rest, i + 1)
    end
  end

  defp first_multi_word_line([], _i), do: nil

  defp issue_for(ctx, line_no, lines) do
    text = lines |> Enum.at(line_no - 1, "") |> String.trim() |> String.slice(0, 40)

    format_issue(ctx,
      message:
        "Multi-line module-attribute collections should list one item per line " <>
          "so they're easy to scan, diff, and update — put each item on its own line.",
      trigger: text,
      line_no: line_no
    )
  end
end
