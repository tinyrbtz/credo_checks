defmodule Rbtz.CredoChecks.Warning.ReqTestWithoutVerifyOnExit do
  use Credo.Check,
    id: "RBTZ0039",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires test modules that mock HTTP with `Req.Test.stub/2` or
      `Req.Test.expect/3` to call `Req.Test.verify_on_exit!/0` in a
      `setup`/`setup_all` block.

      Without `verify_on_exit!`, an `expect/3` whose stub is never invoked
      will silently pass the test instead of raising at the end — masking
      code paths that skipped the HTTP call entirely. Calling it once in
      `setup` wires up the on-exit hook for every test in the module.

      The check runs only on test files (`test/**/*_test.exs`). If the
      module calls `Req.Test.stub` or `Req.Test.expect` anywhere, there
      must be a `Req.Test.verify_on_exit!()` (or bare
      `verify_on_exit!()`) inside a `setup` / `setup_all` block. A
      top-level call outside of setup does not count — it must run per
      test.

      # Bad

          defmodule MyTest do
            use MyApp.DataCase, async: true

            test "fetches data" do
              Req.Test.expect(MyApp.HTTP, fn conn -> ... end)
              # ...
            end
          end

      # Good

          defmodule MyTest do
            use MyApp.DataCase, async: true

            setup :verify_on_exit!

            test "fetches data" do
              Req.Test.expect(MyApp.HTTP, fn conn -> ... end)
              # ...
            end
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    with true <- test_file?(source_file.filename),
         {:ok, ast} <- Credo.Code.ast(source_file),
         line_no when is_integer(line_no) <- find_req_test_usage(ast),
         false <- has_verify_on_exit_in_setup?(ast) do
      ctx = Context.build(source_file, params, __MODULE__)
      ctx |> put_issue(issue_for(ctx, line_no)) |> Map.fetch!(:issues)
    else
      _ -> []
    end
  end

  defp test_file?(filename) do
    expanded = Path.expand(filename)
    String.ends_with?(filename, "_test.exs") or String.contains?(expanded, "/test/")
  end

  # Returns the line number of the first Req.Test.stub/expect call, or nil.
  defp find_req_test_usage(ast) do
    {_ast, line} =
      Macro.prewalk(ast, nil, fn
        node, acc when is_integer(acc) ->
          {node, acc}

        {{:., _, [{:__aliases__, _, [:Req, :Test]}, fun]}, meta, _args} = node, _acc
        when fun in [:stub, :expect] ->
          {node, meta[:line]}

        node, acc ->
          {node, acc}
      end)

    line
  end

  defp has_verify_on_exit_in_setup?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        node, true ->
          {node, true}

        {op, _meta, args} = node, _acc when op in [:setup, :setup_all] ->
          {node, setup_args_have_verify?(args)}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  # Handles: setup :verify_on_exit!, setup [:verify_on_exit!, ...],
  # setup do ... end, setup %{...} do ... end
  defp setup_args_have_verify?(args) when is_list(args) do
    Enum.any?(args, &arg_has_verify?/1)
  end

  defp setup_args_have_verify?(_), do: false

  defp arg_has_verify?(:verify_on_exit!), do: true
  defp arg_has_verify?({:verify_on_exit!, _, ctx}) when is_atom(ctx), do: true

  defp arg_has_verify?(list) when is_list(list) do
    if body = Keyword.get(list, :do) do
      body_calls_verify?(body)
    else
      Enum.any?(list, &arg_has_verify?/1)
    end
  end

  defp arg_has_verify?(_), do: false

  defp body_calls_verify?(body) do
    {_ast, found?} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        {{:., _, [{:__aliases__, _, [:Req, :Test]}, :verify_on_exit!]}, _, _} = node, _acc ->
          {node, true}

        {:verify_on_exit!, _, _} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "Test module uses `Req.Test.stub`/`expect` but has no " <>
          "`Req.Test.verify_on_exit!()` in `setup`/`setup_all`. Without it, unmet " <>
          "expectations silently pass.",
      trigger: "Req.Test",
      line_no: line_no
    )
  end
end
