defmodule Rbtz.CredoChecks.Readability.PreferBlockFormForMultilineIf do
  use Credo.Check,
    id: "RBTZ0052",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Forbids the keyword form `if cond, do: x, else: y` (and the
      `unless` equivalent) when the expression spans more than one line.
      Switch to the explicit `do ... else ... end` block form.

      The keyword form is great for tiny one-line conditionals. Once the
      expression has to wrap across multiple lines, the `, do:` /
      `, else:` punctuation is harder to spot than a plain `do` block
      and encourages awkward mid-expression line breaks.

      # Bad

          if Enum.any?(list, &is_integer/1),
            do: List.first(list),
            else: List.last(list)

          unless map_size(m) == 0,
            do: Map.values(m),
            else: []

          # do-only, still multiline — flagged
          if cond,
            do: some_very_long_function_call(arg1, arg2)

      # Good

          if Enum.any?(list, &is_integer/1) do
            List.first(list)
          else
            List.last(list)
          end

          # single-line keyword form — fine
          if cond, do: x, else: y
          unless cond, do: x

          # block form — never flagged
          if cond do
            x
          else
            y
          end

      The check inspects every `if` and `unless` that uses the shorthand
      keyword form (i.e. `, do:` rather than `do ... end`). Block-form
      conditionals are not considered.
      """
    ]

  @ops [:if, :unless]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, ctx} = Macro.prewalk(ast, ctx, &walk/2)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp walk({op, meta, [cond_ast, kw]} = ast, ctx)
       when op in @ops and is_list(kw) do
    if keyword_form?(meta) and Keyword.has_key?(kw, :do) and
         multiline?(cond_ast, kw) do
      {ast, put_issue(ctx, issue_for(ctx, op, meta[:line]))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  # The `do ... end` block form sets `meta[:do]`; the `, do:` keyword
  # form does not.
  defp keyword_form?(meta), do: not Keyword.has_key?(meta, :do)

  defp multiline?(cond_ast, kw) do
    case collect_lines([cond_ast | Keyword.values(kw)]) do
      [] -> false
      lines -> Enum.max(lines) > Enum.min(lines)
    end
  end

  defp collect_lines(nodes) do
    Enum.flat_map(nodes, fn node ->
      {_node, lines} =
        Macro.prewalk(node, [], fn
          {_, meta, _} = n, acc when is_list(meta) ->
            {n, [meta[:line] | acc]}

          n, acc ->
            {n, acc}
        end)

      Enum.reject(lines, &is_nil/1)
    end)
  end

  defp issue_for(ctx, op, line_no) do
    format_issue(ctx,
      message:
        "Multiline `#{op} ..., do: ..., else: ...` is hard to read. " <>
          "Switch to the `#{op} ... do ... else ... end` block form when the expression wraps.",
      trigger: to_string(op),
      line_no: line_no
    )
  end
end
