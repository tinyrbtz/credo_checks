defmodule Rbtz.CredoChecks.Readability.TopLevelAliasImportRequire do
  use Credo.Check,
    id: "RBTZ0002",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Ensures that `alias`, `import`, and `require` statements appear at the
      top level of a module rather than inside individual functions or test
      blocks.

      Module-level directives are easier to discover when scanning a file: a
      reader can see every external dependency at a glance, and the cost of an
      `import` is paid once for the whole module rather than re-stated in each
      function.

      # Bad

          defmodule MyModule do
            def query do
              import Ecto.Query

              from u in User, where: u.active == true
            end
          end

      # Good

          defmodule MyModule do
            import Ecto.Query

            def query do
              from u in User, where: u.active == true
            end
          end

      The check looks inside `def`, `defp`, `defmacro`, `describe`, `test`,
      `setup`, and `setup_all` blocks. `quote` blocks are skipped because
      `alias`/`import`/`require` are routinely emitted by macros.
      """
    ]

  @def_ops [:def, :defp, :defmacro, :defmacrop, :describe, :test, :setup, :setup_all]
  @directives [:alias, :import, :require]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, ctx} = Macro.prewalk(ast, ctx, &walk_module/2)
        ctx.issues

      _ ->
        []
    end
  end

  defp walk_module({:defmodule, _meta, [_alias, [do: body]]} = ast, ctx) do
    ctx = traverse_module_body(body, ctx)
    {ast, ctx}
  end

  defp walk_module(ast, ctx), do: {ast, ctx}

  defp traverse_module_body({:__block__, _meta, stmts}, ctx) do
    Enum.reduce(stmts, ctx, &check_top_level_stmt/2)
  end

  defp traverse_module_body(stmt, ctx) do
    check_top_level_stmt(stmt, ctx)
  end

  defp check_top_level_stmt({op, _meta, args}, ctx) when op in @def_ops and is_list(args) do
    case List.last(args) do
      [{:do, body} | _] -> find_issues_in_body(body, ctx)
      _ -> ctx
    end
  end

  defp check_top_level_stmt(_stmt, ctx), do: ctx

  defp find_issues_in_body(body, ctx) do
    {_ast, ctx} =
      Macro.prewalk(body, ctx, fn
        {:quote, _meta, _args}, ctx ->
          {{:__skip__, [], nil}, ctx}

        {:defmodule, _meta, _args}, ctx ->
          {{:__skip__, [], nil}, ctx}

        {kw, meta, [_ | _]} = ast, ctx when kw in @directives ->
          {ast, put_issue(ctx, issue_for(ctx, kw, meta))}

        ast, ctx ->
          {ast, ctx}
      end)

    ctx
  end

  defp issue_for(ctx, kw, meta) do
    format_issue(ctx,
      message:
        "`#{kw}` should appear at the top level of the module, not inside a function or test block.",
      trigger: to_string(kw),
      line_no: meta[:line]
    )
  end
end
