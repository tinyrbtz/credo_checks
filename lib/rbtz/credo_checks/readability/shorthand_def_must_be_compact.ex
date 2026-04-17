defmodule Rbtz.CredoChecks.Readability.ShorthandDefMustBeCompact do
  use Credo.Check,
    id: "RBTZ0044",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Forbids the shorthand `def name(args), do: body` form whose body spans
      more than one line. Once the body has to wrap, switch to the explicit
      `do...end` block form.

      The shorthand exists to keep tiny bodies visually compact. Once the
      body has to wrap across multiple lines, the `, do:` punctuation becomes
      harder to spot than a plain `do` block — and the resulting layout
      encourages awkward mid-expression line breaks.

      A multi-line head (e.g. from nested pattern matching) is fine as long
      as the body still fits on a single line.

      # Bad

          def something(x),
            do:
              one_very_long_method_call(x) || one_very_long_method_call(x) ||
                one_very_long_method_call(x)

      # Good

          def something(x) do
            one_very_long_method_call(x) || one_very_long_method_call(x) ||
              one_very_long_method_call(x)
          end

          # still fine — body is a single line
          def short(x),
            do: x + 1

          # still fine — only the head wraps; body fits on one line
          defp put_id(map, %{
                 outer: %{inner: %{id: id}}
               }),
               do: Map.put(map, :id, id)

      The check inspects every `def`, `defp`, `defmacro`, and `defmacrop`
      that uses the shorthand keyword form. Block-form (`do...end`)
      definitions are not considered.
      """
    ]

  @def_ops [:def, :defp, :defmacro, :defmacrop]

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

  defp walk({op, meta, [_head, [{:do, body}]]} = ast, ctx) when op in @def_ops do
    if shorthand?(meta) do
      {ast, maybe_flag(op, meta, body, ctx)}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp shorthand?(meta), do: not Keyword.has_key?(meta, :do)

  defp maybe_flag(op, meta, body, ctx) do
    case body_line_span(body) do
      {min_line, max_line} when max_line > min_line ->
        put_issue(ctx, issue_for(ctx, op, meta[:line]))

      _ ->
        ctx
    end
  end

  defp body_line_span(body) do
    {_ast, lines} =
      Macro.prewalk(body, [], fn
        {_, meta, _} = node, acc when is_list(meta) ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    case Enum.reject(lines, &is_nil/1) do
      [] -> :no_lines
      ls -> {Enum.min(ls), Enum.max(ls)}
    end
  end

  defp issue_for(ctx, op, line_no) do
    format_issue(ctx,
      message:
        "Shorthand `#{op} ..., do: ...` body must fit on a single line. " <>
          "Switch to `#{op} ... do ... end` block form when the body needs to wrap.",
      trigger: to_string(op),
      line_no: line_no
    )
  end
end
