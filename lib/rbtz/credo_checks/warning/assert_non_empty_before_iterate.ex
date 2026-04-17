defmodule Rbtz.CredoChecks.Warning.AssertNonEmptyBeforeIterate do
  use Credo.Check,
    id: "RBTZ0041",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires that when a test iterates a collection with `assert` /
      `refute` inside the iteration, the test also asserts the collection
      is non-empty earlier in the same test body.

      Otherwise an empty collection silently makes every per-item
      assertion vacuously pass — the test reports green even though
      nothing was checked.

      Accepted non-empty guards (on the same variable):

        * `refute Enum.empty?(list)`
        * `assert Enum.empty?(list) == false`
        * `assert list != []`
        * `refute list == []`
        * `assert length(list) > 0`

      The check runs only on test files (`test/**/*_test.exs`). It walks
      each `test "..." do ... end` block and flags `Enum.each/map/all?/
      any?/filter/reject/flat_map/reduce` calls whose function body
      contains an `assert` or `refute`, when no matching guard has been
      seen earlier in the test.

      # Bad

          test "each user has an email" do
            users = fetch_users()

            Enum.each(users, fn user ->
              assert user.email =~ "@"
            end)
          end

      # Good

          test "each user has an email" do
            users = fetch_users()

            refute Enum.empty?(users)

            Enum.each(users, fn user ->
              assert user.email =~ "@"
            end)
          end
      """
    ]

  @iter_funs [:each, :map, :filter, :reject, :all?, :any?, :flat_map, :reduce]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if test_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk_top/2, ctx)
      Enum.reverse(result.issues)
    else
      []
    end
  end

  defp test_file?(filename) do
    expanded = Path.expand(filename)
    String.ends_with?(filename, "_test.exs") or String.contains?(expanded, "/test/")
  end

  # Find `test "..." do ... end` blocks.
  defp walk_top({:test, _meta, args} = ast, ctx) when is_list(args) do
    case List.last(args) do
      [do: body] -> {ast, scan_test_body(body, ctx)}
      _ -> {ast, ctx}
    end
  end

  defp walk_top(ast, ctx), do: {ast, ctx}

  defp scan_test_body(body, ctx) do
    body
    |> body_statements()
    |> Enum.reduce({MapSet.new(), ctx}, fn stmt, {guarded, ctx} ->
      guarded = maybe_add_guard(guarded, stmt)
      ctx = check_iteration(stmt, guarded, ctx)
      # Drop rebound names so a subsequent iteration over a rebound variable
      # re-triggers the guard requirement. The iteration check above already
      # ran against the pre-rebind `guarded`, so assignments of the form
      # `users = Enum.each(users, ...)` still see the prior guard.
      guarded = maybe_drop_rebind(guarded, stmt)
      {guarded, ctx}
    end)
    |> elem(1)
  end

  defp body_statements({:__block__, _meta, stmts}), do: stmts
  defp body_statements(stmt), do: [stmt]

  # Recognize non-empty guards and add the variable name to the set.

  # refute Enum.empty?(x)
  defp maybe_add_guard(
         guarded,
         {:refute, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, [{name, _, ctx}]}]}
       )
       when is_atom(name) and is_atom(ctx) do
    MapSet.put(guarded, name)
  end

  # refute x |> Enum.empty?()
  defp maybe_add_guard(
         guarded,
         {:refute, _,
          [{:|>, _, [{name, _, ctx}, {{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, []}]}]}
       )
       when is_atom(name) and is_atom(ctx) do
    MapSet.put(guarded, name)
  end

  # assert Enum.empty?(x) == false
  defp maybe_add_guard(
         guarded,
         {:assert, _,
          [
            {:==, _,
             [{{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, [{name, _, ctx}]}, false]}
          ]}
       )
       when is_atom(name) and is_atom(ctx) do
    MapSet.put(guarded, name)
  end

  # assert x |> Enum.empty?() == false
  defp maybe_add_guard(
         guarded,
         {:assert, _,
          [
            {:==, _,
             [
               {:|>, _,
                [{name, _, ctx}, {{:., _, [{:__aliases__, _, [:Enum]}, :empty?]}, _, []}]},
               false
             ]}
          ]}
       )
       when is_atom(name) and is_atom(ctx) do
    MapSet.put(guarded, name)
  end

  # assert x != []
  defp maybe_add_guard(guarded, {:assert, _, [{:!=, _, [{name, _, ctx}, []]}]})
       when is_atom(name) and is_atom(ctx), do: MapSet.put(guarded, name)

  # refute x == []
  defp maybe_add_guard(guarded, {:refute, _, [{:==, _, [{name, _, ctx}, []]}]})
       when is_atom(name) and is_atom(ctx), do: MapSet.put(guarded, name)

  # assert length(x) > n  (n >= 0)
  defp maybe_add_guard(guarded, {:assert, _, [{:>, _, [{:length, _, [{name, _, ctx}]}, n]}]})
       when is_atom(name) and is_atom(ctx) and is_integer(n) and n >= 0 do
    MapSet.put(guarded, name)
  end

  # assert length(x) >= n  (n >= 1)
  defp maybe_add_guard(guarded, {:assert, _, [{:>=, _, [{:length, _, [{name, _, ctx}]}, n]}]})
       when is_atom(name) and is_atom(ctx) and is_integer(n) and n >= 1 do
    MapSet.put(guarded, name)
  end

  # assert x |> length() > n  (n >= 0)
  defp maybe_add_guard(
         guarded,
         {:assert, _, [{:>, _, [{:|>, _, [{name, _, ctx}, {:length, _, []}]}, n]}]}
       )
       when is_atom(name) and is_atom(ctx) and is_integer(n) and n >= 0 do
    MapSet.put(guarded, name)
  end

  # assert x |> length() >= n  (n >= 1)
  defp maybe_add_guard(
         guarded,
         {:assert, _, [{:>=, _, [{:|>, _, [{name, _, ctx}, {:length, _, []}]}, n]}]}
       )
       when is_atom(name) and is_atom(ctx) and is_integer(n) and n >= 1 do
    MapSet.put(guarded, name)
  end

  defp maybe_add_guard(guarded, _), do: guarded

  defp maybe_drop_rebind(guarded, {:=, _, [{name, _, ctx}, _rhs]})
       when is_atom(name) and is_atom(ctx) do
    MapSet.delete(guarded, name)
  end

  defp maybe_drop_rebind(guarded, _), do: guarded

  # Recognize iterating calls and flag if the iterated variable isn't
  # in the guarded set and the iteration body contains assert/refute.
  defp check_iteration(stmt, guarded, ctx) do
    case normalize_iteration(stmt) do
      {fun, var, fn_body, line_no} when is_atom(fun) ->
        if contains_assert_or_refute?(fn_body) and not MapSet.member?(guarded, var) do
          put_issue(ctx, issue_for(ctx, line_no, fun, var))
        else
          ctx
        end

      _ ->
        ctx
    end
  end

  # Direct form: Enum.each(list, fn -> ... end)
  defp normalize_iteration(
         {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, meta, [{name, _, ctx} | rest]}
       )
       when fun in @iter_funs and is_atom(name) and is_atom(ctx) do
    case List.last(rest) do
      {:fn, _, _} = fun_ast -> {fun, name, fun_ast, meta[:line]}
      _ -> nil
    end
  end

  # Piped form: list |> Enum.each(fn -> ... end)
  defp normalize_iteration(
         {:|>, meta, [{name, _, ctx}, {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, rest}]}
       )
       when fun in @iter_funs and is_atom(name) and is_atom(ctx) do
    case List.last(rest) do
      {:fn, _, _} = fun_ast -> {fun, name, fun_ast, meta[:line]}
      _ -> nil
    end
  end

  defp normalize_iteration(_), do: nil

  defp contains_assert_or_refute?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        {op, _, _} = node, _acc when op in [:assert, :refute] -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp issue_for(ctx, line_no, fun, var) do
    format_issue(ctx,
      message:
        "Assert `#{var}` is non-empty before iterating with `Enum.#{fun}` — an empty " <>
          "list makes per-item assertions vacuously pass. Try `refute Enum.empty?(#{var})` " <>
          "or `assert #{var} != []` first.",
      trigger: "Enum.#{fun}",
      line_no: line_no
    )
  end
end
