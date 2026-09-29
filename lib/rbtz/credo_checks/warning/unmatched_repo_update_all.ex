defmodule Rbtz.CredoChecks.Warning.UnmatchedRepoUpdateAll do
  use Credo.Check,
    id: "RBTZ0063",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires pattern-matching the result of `Repo.update_all` in
      application code.

      `update_all` returns `{count, returned}` and never fails when no rows
      match, so a wrong id or an already-deleted row is a silent no-op.
      Matching `{1, nil} = ...` turns "exactly one row" into an assertion;
      `{_, nil} = ...` at minimum documents the shape.

      The check fires under `lib/` when an `update_all` call on a module
      named `Repo` (`Repo`, `MyApp.Repo`) is a statement whose value is
      dropped — any statement in a block except the last — or is matched
      against `_` / `_name`. A call whose value is returned from the
      function, assigned, or matched against a pattern is fine.

      # Bad

          def archive(post_id) do
            Post
            |> where(id: ^post_id)
            |> Repo.update_all(set: [archived: true])

            :ok
          end

      # Good

          def archive(post_id) do
            {1, nil} =
              Post
              |> where(id: ^post_id)
              |> Repo.update_all(set: [archived: true])

            :ok
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if lib_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp lib_file?(filename), do: filename |> Path.expand() |> Path.split() |> Enum.member?("lib")

  defp walk({:__block__, _, [_ | _] = exprs} = ast, ctx) do
    ctx =
      exprs
      |> Enum.drop(-1)
      |> Enum.reduce(ctx, &check_dropped/2)

    {ast, ctx}
  end

  defp walk({:=, _, [{name, _, context}, value]} = ast, ctx)
       when is_atom(name) and is_atom(context) do
    if name |> Atom.to_string() |> String.starts_with?("_") do
      {ast, check_dropped(value, ctx)}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp check_dropped(expr, ctx) do
    case update_all_meta(expr) do
      nil -> ctx
      meta -> put_issue(ctx, issue_for(ctx, meta))
    end
  end

  defp update_all_meta({:|>, _, [_, rhs]}), do: update_all_meta(rhs)

  defp update_all_meta({{:., _, [{:__aliases__, _, parts}, :update_all]}, meta, _}) do
    if List.last(parts) == :Repo, do: meta
  end

  defp update_all_meta(_expr), do: nil

  defp issue_for(ctx, meta) do
    format_issue(ctx,
      message:
        "Pattern-match the `Repo.update_all` result — `{1, nil} = ...` when exactly one row " <>
          "should change, at minimum `{_, nil} = ...` — so a no-op isn't silent.",
      trigger: "Repo.update_all",
      line_no: meta[:line]
    )
  end
end
