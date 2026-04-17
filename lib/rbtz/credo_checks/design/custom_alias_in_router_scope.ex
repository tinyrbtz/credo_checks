defmodule Rbtz.CredoChecks.Design.CustomAliasInRouterScope do
  use Credo.Check,
    id: "RBTZ0018",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Forbids manual `alias` statements inside Phoenix `scope` blocks in
      router files.

      `scope/2` and `scope/3` already prefix every controller and LiveView
      reference with the scope's alias argument. Layering an explicit `alias`
      on top defeats that prefixing, makes route lookup harder for tools, and
      diverges from the rest of the project's router conventions.

      The check fires only on files matching `*_router.ex` or `**/router.ex`.

      # Bad

          scope "/admin", MyAppWeb.Admin do
            alias MyAppWeb.Admin.Users
            get "/users", Users.IndexController, :index
          end

      # Good

          scope "/admin", MyAppWeb.Admin do
            get "/users", Users.IndexController, :index
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if router_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)

      case Credo.Code.ast(source_file) do
        {:ok, ast} ->
          {_ast, ctx} = Macro.prewalk(ast, ctx, &walk/2)
          ctx.issues

        _ ->
          []
      end
    else
      []
    end
  end

  defp router_file?(filename) when is_binary(filename) do
    base = Path.basename(filename)
    base == "router.ex" or String.ends_with?(base, "_router.ex")
  end

  defp router_file?(_), do: false

  defp walk({:scope, _meta, args} = ast, ctx) when is_list(args) do
    if kw = Enum.find(args, &Keyword.keyword?/1) do
      body = Keyword.get(kw, :do)
      ctx = scan_scope_body(body, ctx)
      {ast, ctx}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp scan_scope_body(nil, ctx), do: ctx

  defp scan_scope_body({:__block__, _meta, stmts}, ctx) do
    Enum.reduce(stmts, ctx, &flag_if_alias/2)
  end

  defp scan_scope_body(stmt, ctx), do: flag_if_alias(stmt, ctx)

  defp flag_if_alias({:alias, meta, _args}, ctx) do
    put_issue(ctx, issue_for(ctx, meta))
  end

  defp flag_if_alias(_stmt, ctx), do: ctx

  defp issue_for(ctx, meta) do
    format_issue(ctx,
      message:
        "Do not declare `alias` inside a router `scope` block. " <>
          "The scope's second argument already prefixes every controller and LiveView reference.",
      trigger: "alias",
      line_no: meta[:line]
    )
  end
end
