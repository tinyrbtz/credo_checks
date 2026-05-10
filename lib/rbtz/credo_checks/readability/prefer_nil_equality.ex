defmodule Rbtz.CredoChecks.Readability.PreferNilEquality do
  use Credo.Check,
    id: "RBTZ0051",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Prefers `x == nil` and `x != nil` over `is_nil(x)` and `not is_nil(x)`
      in conditional and assertion positions, for consistency with other
      equality checks at the same call site.

      The check fires only inside the boolean expression of `if`, `unless`,
      `cond` clause heads, the `case` scrutinee, and the first argument of
      `assert` / `refute`. It descends through boolean operators (`and`,
      `or`, `&&`, `||`, `not`, `!`) but does not descend into arbitrary
      function arguments — `foo(is_nil(x))` is not flagged because the
      condition being tested is `foo(...)`, not `is_nil/1` itself.

      `is_nil/1` remains the right (and required) choice in `when` guards
      and in Ecto query DSL, so those uses are unaffected.

      # Bad

          if is_nil(user), do: redirect()
          unless not is_nil(token), do: raise "no token"
          cond do
            is_nil(x) -> :missing
            true -> x
          end
          assert is_nil(result)
          refute not is_nil(result)

      # Good

          if user == nil, do: redirect()
          unless token != nil, do: raise "no token"
          cond do
            x == nil -> :missing
            true -> x
          end
          assert result == nil
          refute result != nil

          # Guards: keep is_nil
          def fetch(x) when is_nil(x), do: :missing

          # Ecto: keep is_nil
          from u in User, where: is_nil(u.deleted_at)
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, ctx} = Macro.prewalk(ast, ctx, &visit/2)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp visit({op, _meta, [cond_expr, kw]} = node, ctx)
       when op in [:if, :unless] and is_list(kw) do
    {node, scan_boolean(cond_expr, ctx)}
  end

  defp visit({:cond, _meta, [[do: clauses]]} = node, ctx) when is_list(clauses) do
    ctx =
      Enum.reduce(clauses, ctx, fn {:->, _, [[head], _body]}, ctx ->
        scan_boolean(head, ctx)
      end)

    {node, ctx}
  end

  defp visit({:case, _meta, [scrutinee, [do: _clauses]]} = node, ctx) do
    {node, scan_boolean(scrutinee, ctx)}
  end

  defp visit({op, _meta, [expr | _]} = node, ctx) when op in [:assert, :refute] do
    {node, scan_boolean(expr, ctx)}
  end

  defp visit(node, ctx), do: {node, ctx}

  defp scan_boolean({op, _meta, [left, right]}, ctx) when op in [:and, :or, :&&, :||] do
    ctx = scan_boolean(left, ctx)
    scan_boolean(right, ctx)
  end

  defp scan_boolean({op, _outer_meta, [{:is_nil, meta, [_arg]}]}, ctx)
       when op in [:not, :!] do
    put_issue(ctx, issue_for(ctx, :negated, meta))
  end

  defp scan_boolean({op, _meta, [inner]}, ctx) when op in [:not, :!] do
    scan_boolean(inner, ctx)
  end

  defp scan_boolean({:is_nil, meta, [_arg]}, ctx) do
    put_issue(ctx, issue_for(ctx, :bare, meta))
  end

  defp scan_boolean(_other, ctx), do: ctx

  defp issue_for(ctx, :bare, meta) do
    format_issue(ctx,
      message: "Use `x == nil` instead of `is_nil(x)` in conditionals and assertions.",
      trigger: "is_nil",
      line_no: meta[:line]
    )
  end

  defp issue_for(ctx, :negated, meta) do
    format_issue(ctx,
      message:
        "Use `x != nil` instead of `not is_nil(x)` / `!is_nil(x)` in conditionals and assertions.",
      trigger: "is_nil",
      line_no: meta[:line]
    )
  end
end
