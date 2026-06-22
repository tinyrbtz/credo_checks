defmodule Rbtz.CredoChecks.Refactor.PreferWithOverCase do
  use Credo.Check,
    id: "RBTZ0054",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Flags a two-clause `case` whose only non-happy-path clause re-returns an
      error it matched, unchanged. A `with` expresses this more directly: its
      implicit `else` returns the non-matching value as-is, so the pass-through
      clause disappears.

      # Bad

          case File.read(path) do
            {:ok, contents} -> {:ok, String.trim(contents)}
            {:error, reason} -> {:error, reason}
          end

      # Good

          with {:ok, contents} <- File.read(path) do
            {:ok, String.trim(contents)}
          end

      The pass-through clause must re-return an error shape — an `{:error, ...}`
      tuple or the bare `:error` atom — whose body is structurally identical to
      the pattern it matched (`{:error, reason} -> {:error, reason}`,
      `:error -> :error`).

      To keep rewrites safe, only this shape is flagged. These are not flagged:

        * `case` with one clause, or three or more clauses.
        * Both clauses doing real work (no pass-through clause).
        * Both clauses being pass-through clauses (an identity `case`).
        * A pass-through clause that isn't an error shape (e.g. `nil -> nil`,
          `other -> other`).
        * A clause head with a `when` guard.
        * A catch-all happy path (`_` / a bare variable) paired with the error
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

  # Flag iff one clause is an error pass-through (re-returns an `{:error, ...}`
  # tuple or `:error` unchanged) and the other is a work clause — not a
  # catch-all and not itself a pass-through. Requiring a non-catch-all work
  # clause keeps the two patterns mutually exclusive, so clause order can't
  # change semantics under the `with` rewrite.
  defp flaggable?([clause_a, clause_b]) do
    with {:ok, {pat_a, body_a}} <- clause_parts(clause_a),
         {:ok, {pat_b, body_b}} <- clause_parts(clause_b) do
      (error_passthrough?(pat_a, body_a) and work_clause?(pat_b, body_b)) or
        (error_passthrough?(pat_b, body_b) and work_clause?(pat_a, body_a))
    else
      _ -> false
    end
  end

  defp flaggable?(_), do: false

  # Each `case` clause is a `:->` node with a single head pattern. Guarded
  # clauses can't be expressed as a plain `with` pattern, so skip them.
  defp clause_parts({:->, _, [[{:when, _, _}], _body]}), do: :error
  defp clause_parts({:->, _, [[pattern], body]}), do: {:ok, {pattern, body}}

  defp error_passthrough?(pattern, body),
    do: error_shape?(pattern) and passthrough?(pattern, body)

  defp work_clause?(pattern, body),
    do: not catch_all?(pattern) and not passthrough?(pattern, body)

  defp error_shape?({:error, _}), do: true
  defp error_shape?(:error), do: true
  defp error_shape?(_), do: false

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
        "This `case` only passes an error clause through unchanged — rewrite it as a `with` expression.",
      trigger: "case",
      line_no: meta[:line]
    )
  end
end
