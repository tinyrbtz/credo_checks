defmodule Rbtz.CredoChecks.Readability.PreferVerifiedRoutes do
  use Credo.Check,
    id: "RBTZ0064",
    base_priority: :normal,
    category: :readability,
    param_defaults: [ignore_tags: []],
    explanations: [
      check: """
      Requires the `~p` sigil for in-app paths.

      `~p"/users/\#{user}"` is checked against the router at compile time, so
      a renamed or removed route fails the build instead of producing a dead
      link or a test that requests a path that no longer exists. A raw
      `"/path"` string is only for external URLs.

      The check fires on a string literal starting with `/` (not `//`) in:

        * `push_navigate(socket, to: "/...")`, `push_patch(socket, to: ...)`,
          and `redirect(conn_or_socket, to: ...)`
        * `<.link navigate="/...">` and `<.link patch="/...">` in HEEx
        * in test files: `live(conn, "/...")`, the `Phoenix.ConnTest`
          request helpers (`get`, `post`, `put`, `patch`, `delete`, `head`,
          `options`), and `assert_redirect` / `assert_patch`

      `router.ex` files are skipped (the `Redirect` plug and route
      definitions take raw paths). Tests that deliberately request a path
      `~p` can't express — e.g. a bare path on a different host — can be
      exempted by tag: with `ignore_tags: [:with_api_host]`, any test
      tagged `@tag :with_api_host` (or under a matching `@describetag` /
      `@moduletag`) is skipped.

      # Bad

          push_navigate(socket, to: "/settings")
          conn |> get("/users/\#{user.id}")

      # Good

          push_navigate(socket, to: ~p"/settings")
          conn |> get(~p"/users/\#{user}")
      """,
      params: [
        ignore_tags:
          "Test tags whose tests may use raw paths (`@tag`, `@describetag`, or `@moduletag`)."
      ]
    ]

  alias Rbtz.CredoChecks.{HeexSource, TestSource}

  @navigation_calls [:push_navigate, :push_patch, :redirect]
  @test_path_calls [:live, :get, :post, :put, :patch, :delete, :head, :options]
  @test_assert_calls [:assert_redirect, :assert_patch]
  @heex_path_attr ~r/(?<![\w-])(navigate|patch)="(\/(?!\/)[^"]*)"/

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if Path.basename(source_file.filename) == "router.ex" do
      []
    else
      ctx = Context.build(source_file, params, __MODULE__)

      scope = %{
        test_file?: TestSource.test_file?(source_file.filename),
        ignore_tags: Params.get(params, :ignore_tags, __MODULE__),
        tags: []
      }

      {_scope, ctx} = Credo.Code.prewalk(source_file, &walk/2, {scope, ctx})

      source_file
      |> HeexSource.templates()
      |> Enum.reduce(ctx, &scan_template/2)
      |> Map.fetch!(:issues)
    end
  end

  defp walk({:__block__, _, exprs}, {scope, ctx}) do
    {_tags, _pending, ctx} =
      Enum.reduce(exprs, {scope.tags, [], ctx}, &walk_statement(&1, &2, scope))

    {nil, {scope, ctx}}
  end

  defp walk({:|>, _, [lhs, {callee, meta, args}]}, {scope, ctx}) when is_list(args) do
    call = {callee, meta, [lhs | args]}
    {call, {scope, check_call(call, scope.test_file?, ctx)}}
  end

  defp walk(ast, {scope, ctx}), do: {ast, {scope, check_call(ast, scope.test_file?, ctx)}}

  defp walk_statement({:@, _, [{attr, _, [tags]}]}, {scope_tags, pending, ctx}, _scope)
       when attr in [:moduletag, :describetag],
       do: {scope_tags ++ tag_names(tags), pending, ctx}

  defp walk_statement({:@, _, [{:tag, _, [tags]}]}, {scope_tags, pending, ctx}, _scope),
    do: {scope_tags, pending ++ tag_names(tags), ctx}

  defp walk_statement({:test, _, _} = test, {scope_tags, pending, ctx}, scope) do
    if Enum.any?(scope_tags ++ pending, &(&1 in scope.ignore_tags)) do
      {scope_tags, [], ctx}
    else
      {scope_tags, [], walk_nested(test, %{scope | tags: scope_tags}, ctx)}
    end
  end

  defp walk_statement(expr, {scope_tags, pending, ctx}, scope),
    do: {scope_tags, pending, walk_nested(expr, %{scope | tags: scope_tags}, ctx)}

  defp walk_nested(ast, scope, ctx) do
    {_ast, {_scope, ctx}} = Macro.prewalk(ast, {scope, ctx}, &walk/2)
    ctx
  end

  defp tag_names(tags) when is_list(tags), do: Enum.map(tags, fn {tag, _value} -> tag end)
  defp tag_names(tag), do: [tag]

  defp check_call({name, meta, [_, opts | _]}, _test_file?, ctx)
       when name in @navigation_calls and is_list(opts) do
    case Keyword.get(opts, :to) do
      path when is_binary(path) -> maybe_put_issue(ctx, path, meta[:line])
      _ -> ctx
    end
  end

  defp check_call({name, meta, [_, path | _]}, true, ctx)
       when name in @test_path_calls or name in @test_assert_calls,
       do: maybe_put_issue(ctx, path, meta[:line])

  defp check_call(_ast, _test_file?, ctx), do: ctx

  defp scan_template({heex, line_fn}, ctx) do
    heex
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce(ctx, fn {line, offset}, ctx ->
      @heex_path_attr
      |> Regex.scan(line, capture: :all_but_first)
      |> Enum.reduce(ctx, fn [_attr, path], ctx -> put_path_issue(ctx, path, line_fn.(offset)) end)
    end)
  end

  defp maybe_put_issue(ctx, "/" <> rest = path, line_no) do
    if String.starts_with?(rest, "/"), do: ctx, else: put_path_issue(ctx, path, line_no)
  end

  defp maybe_put_issue(ctx, _path, _line_no), do: ctx

  defp put_path_issue(ctx, path, line_no) do
    issue =
      format_issue(ctx,
        message:
          ~s(Use `~p"#{path}"` for in-app paths — it's verified against the router at compile time.),
        trigger: path,
        line_no: line_no
      )

    put_issue(ctx, issue)
  end
end
