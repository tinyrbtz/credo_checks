defmodule Rbtz.CredoChecks.Refactor.PreferWithOverCase do
  use Credo.Check,
    id: "RBTZ0054",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Flags a two-clause `case` whose only non-happy-path clause re-returns the
      value it matched, unchanged. A `with` expresses this more directly: its
      implicit `else` returns the non-matching value as-is, so the pass-through
      clause disappears.

      # Bad

          case File.read(path) do
            {:ok, contents} -> {:ok, String.trim(contents)}
            {:error, reason} -> {:error, reason}
          end

          case File.read(path) do
            {:ok, contents} -> String.upcase(contents)
            other -> other
          end

      # Good

          with {:ok, contents} <- File.read(path) do
            {:ok, String.trim(contents)}
          end

          with {:ok, contents} <- File.read(path) do
            String.upcase(contents)
          end

      A clause is a pass-through when its body is structurally identical to the
      pattern it matched (`{:error, reason} -> {:error, reason}`, `other ->
      other`).

      To keep rewrites safe, only this shape is flagged. These are not flagged:

        * `case` with one clause, or three or more clauses.
        * Both clauses doing real work (no pass-through clause).
        * Both clauses being pass-throughs (an identity `case`).
        * A clause head with a `when` guard.
        * A catch-all happy path (`_` / a bare variable) paired with a specific
          pass-through — the rewrite would depend on clause order.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_, ctx} = Macro.prewalk(ast, ctx, &walk/2)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  # A `case` is `{:case, meta, [subject, [do: clauses]]}` where each clause is a
  # `{:->, _, [[pattern], body]}` node.
  defp walk({:case, meta, [_subject, [do: clauses]]} = ast, ctx) when is_list(clauses) do
    if flaggable?(clauses), do: {ast, put_issue(ctx, issue_for(ctx, meta))}, else: {ast, ctx}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  # Flag iff exactly one of the two clauses is a pass-through and the other
  # (happy-path) clause's pattern is not a catch-all — so the two patterns are
  # mutually exclusive and clause order can't change semantics.
  defp flaggable?([clause_a, clause_b]) do
    with {:ok, {pat_a, body_a}} <- clause_parts(clause_a),
         {:ok, {pat_b, body_b}} <- clause_parts(clause_b) do
      case {passthrough?(pat_a, body_a), passthrough?(pat_b, body_b)} do
        {true, false} -> not catch_all?(pat_b)
        {false, true} -> not catch_all?(pat_a)
        _ -> false
      end
    else
      _ -> false
    end
  end

  defp flaggable?(_), do: false

  # Guarded clauses don't map cleanly to a guardless `with`, so skip them.
  defp clause_parts({:->, _, [[{:when, _, _}], _body]}), do: :error
  defp clause_parts({:->, _, [[pattern], body]}), do: {:ok, {pattern, body}}
  defp clause_parts(_), do: :error

  defp passthrough?(pattern, body), do: strip_meta(pattern) == strip_meta(body)

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      other -> other
    end)
  end

  # Matches `_` and bare variables; `{:ok, v}`, `foo()`, `%S{}`, `^x` are not
  # catch-alls (their third element is a list, not nil/an atom context).
  defp catch_all?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp catch_all?(_), do: false

  defp issue_for(ctx, meta) do
    format_issue(ctx,
      message:
        "This `case` only passes a clause through unchanged — rewrite it as a `with` expression.",
      trigger: "case",
      line_no: meta[:line]
    )
  end
end
