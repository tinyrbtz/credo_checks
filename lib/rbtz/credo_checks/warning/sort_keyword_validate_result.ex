defmodule Rbtz.CredoChecks.Warning.SortKeywordValidateResult do
  use Credo.Check,
    id: "RBTZ0031",
    base_priority: :normal,
    category: :warning,
    explanations: [
      check: """
      Requires `Enum.sort/1` between `Keyword.validate!/2` and any binding
      that pattern-matches the result.

      `Keyword.validate!/2` returns the keys in the order they appear in the
      *input* keyword list, not in the order of the defaults. That means
      `[a: a, b: b] = Keyword.validate!(opts, a: 1, b: 2)` only matches when
      the caller happens to pass `[a: ..., b: ...]` — flip the call site to
      `[b: ..., a: ...]` and the pattern crashes at runtime. Sorting the
      result first makes the pattern deterministic regardless of caller
      ordering.

      Bare calls without binding (e.g. `Keyword.validate!(opts, [:foo])`
      used purely for its raise-on-unknown-key side effect) are fine and
      not flagged.

      # Bad

          [foo: foo, bar: bar] = Keyword.validate!(opts, foo: 1, bar: 2)

      # Good

          [bar: bar, foo: foo] = opts |> Keyword.validate!(foo: 1, bar: 2) |> Enum.sort()
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    Enum.reverse(result.issues)
  end

  defp walk({op, _meta, [_pattern, rhs]} = ast, ctx) when op in [:=, :<-] do
    if direct_validate_call?(rhs) do
      {ast, put_issue(ctx, issue_for(ctx, rhs))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp direct_validate_call?({{:., _, [{:__aliases__, _, [:Keyword]}, :validate!]}, _meta, _args}) do
    true
  end

  defp direct_validate_call?(_), do: false

  defp issue_for(ctx, {_, meta, _}) do
    format_issue(ctx,
      message:
        "Pipe `Keyword.validate!/2` through `Enum.sort/1` before pattern-matching its result. " <>
          "Without it, the binding depends on caller key order and crashes at runtime if the order differs.",
      trigger: "Keyword.validate!",
      line_no: meta[:line]
    )
  end
end
