defmodule Rbtz.CredoChecks.Refactor.RedundantThen do
  use Credo.Check,
    id: "RBTZ0047",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Flags unnecessary uses of `Kernel.then/2`.

      `then(val, fun)` is semantically `fun.(val)`. When `fun` is a simple
      pass-through or partial application where `val` naturally lands at the
      first argument position, `then/2` adds a layer of indirection that can
      be removed — just call the function directly.

      # Bad

          "hello" |> then(&String.upcase/1)
          "hello" |> then(fn x -> String.upcase(x) end)
          map |> then(&Map.get(&1, :key))
          then(x, &String.upcase/1)

      # Good

          "hello" |> String.upcase()
          map |> Map.get(:key)
          String.upcase(x)

      `then/2` is the right tool when the piped value can't be the first
      argument. These uses are not flagged:

        * `val |> then(&foo(closure, &1))` — val is the second arg.
        * `val |> then(fn v -> foo(closure, v) end)` — same, via `fn`.
        * `val |> then(&(&1 + &1))` — val used more than once.
        * `val |> then(&(&1 * 2))` — operator body; can't be unpiped
          directly.
        * Multi-clause fns, guards, pattern-matched args.
        * Bodies containing `case` / `if` / `|>` / nested `fn` / nested `&`.
      """
    ]

  @binary_ops [
    :==,
    :!=,
    :===,
    :!==,
    :<,
    :>,
    :<=,
    :>=,
    :+,
    :-,
    :*,
    :/,
    :<>,
    :++,
    :--,
    :||,
    :&&,
    :and,
    :or,
    :=~,
    :in
  ]

  @unary_ops [:not, :!]

  # Shared with PreferCapture — forms that block flagging if they appear
  # anywhere in an `fn` body: syntactically disallowed in a capture, or
  # macros that rewrite their argument shape and can't be unpiped cleanly.
  @disallowed_in_body [
    :if,
    :unless,
    :case,
    :cond,
    :with,
    :for,
    :try,
    :receive,
    :fn,
    :&,
    :|>,
    :__block__,
    :assert,
    :refute,
    :assert_raise,
    :assert_receive,
    :assert_received,
    :refute_receive,
    :refute_received,
    :assert_in_delta,
    :catch_error,
    :catch_exit,
    :catch_throw,
    :flunk,
    :dbg
  ]

  # Atom-headed AST forms that aren't function calls — data constructors
  # and special forms. Rejected as a top-level body shape.
  @non_callable_top_level [
    :<<>>,
    :{},
    :%{},
    :%,
    :__aliases__,
    :^,
    :"::",
    :|,
    :=,
    :when,
    :->
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

  # In piped form `x |> then(f)`, the `:then` node has 1 arg (the function).
  # In non-piped form `then(x, f)`, it has 2 args. Any other arity isn't
  # `Kernel.then/2` and so falls through to the default walk clause.
  defp walk({:then, meta, [fn_arg]} = ast, ctx), do: {ast, do_flag(ctx, meta, fn_arg)}

  defp walk({:then, meta, [_val, fn_arg]} = ast, ctx),
    do: {ast, do_flag(ctx, meta, fn_arg)}

  defp walk({{:., _, [_mod, :then]}, meta, [fn_arg]} = ast, ctx),
    do: {ast, do_flag(ctx, meta, fn_arg)}

  defp walk({{:., _, [_mod, :then]}, meta, [_val, fn_arg]} = ast, ctx),
    do: {ast, do_flag(ctx, meta, fn_arg)}

  defp walk(ast, ctx), do: {ast, ctx}

  defp do_flag(ctx, meta, fn_arg) do
    case classify(fn_arg) do
      {:flag, suggestion} -> put_issue(ctx, issue_for(ctx, suggestion, meta))
      :skip -> ctx
    end
  end

  # --- Classification ---

  # Capture form `&...`
  defp classify({:&, _, [body]}), do: classify_capture(body)

  # Anonymous fn `fn x -> ... end`
  defp classify({:fn, _, [{:->, _, [args, body]}]}), do: classify_fn(args, body)

  defp classify(_), do: :skip

  # --- Capture ---

  # `&name/1` — local arity-1 shorthand.
  defp classify_capture({:/, _, [{name, _, ctx}, 1]})
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) and
              name not in @binary_ops and name not in @unary_ops do
    {:flag, Macro.to_string({name, [], []})}
  end

  # `&Mod.name/1` — remote arity-1 shorthand.
  defp classify_capture({:/, _, [{{:., _, [mod, fname]}, _, []}, 1]}) when is_atom(fname) do
    {:flag, Macro.to_string({{:., [], [mod, fname]}, [], []})}
  end

  # Inline capture body like `&foo(&1, ...)` / `&Mod.foo(&1, ...)`.
  defp classify_capture(body) do
    case count_ampersand_refs(body) do
      {1, false} -> classify_partial(body)
      _ -> :skip
    end
  end

  # Local partial-application `&fname(&1, rest...)`.
  defp classify_partial({fname, _, [{:&, _, [1]} | rest]})
       when is_atom(fname) and
              fname not in @binary_ops and fname not in @unary_ops and
              fname not in @disallowed_in_body and fname not in @non_callable_top_level do
    {:flag, Macro.to_string({fname, [], rest})}
  end

  # Remote partial-application `&Mod.fname(&1, rest...)` / `&mod.fname(&1, rest...)`.
  defp classify_partial({{:., m, [mod, fname]}, _, [{:&, _, [1]} | rest]})
       when is_atom(fname) do
    {:flag, Macro.to_string({{:., m, [mod, fname]}, [], rest})}
  end

  defp classify_partial(_), do: :skip

  # Returns `{count_of_&1, any_higher_index?}` so we can require arity-1
  # with exactly one use.
  defp count_ampersand_refs(ast) do
    {_, result} =
      Macro.prewalk(ast, {0, false}, fn
        {:&, _, [1]} = node, {ones, higher?} ->
          {node, {ones + 1, higher?}}

        {:&, _, [n]} = node, {ones, _higher?} when is_integer(n) and n > 1 ->
          {node, {ones, true}}

        node, acc ->
          {node, acc}
      end)

    result
  end

  # --- fn classification ---

  defp classify_fn(args, body) do
    with {:ok, arg_name} <- extract_single_plain_arg(args),
         false <- body_has_disallowed?(body),
         {:ok, rebuilt} <- body_is_first_arg_call(body, arg_name) do
      {:flag, Macro.to_string(rebuilt)}
    else
      _ -> :skip
    end
  end

  defp extract_single_plain_arg([{name, _, ctx}])
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    if underscore_prefixed?(name), do: :error, else: {:ok, name}
  end

  defp extract_single_plain_arg(_), do: :error

  defp underscore_prefixed?(name) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp body_has_disallowed?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {op, _, _} = node, _acc when op in @disallowed_in_body ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Body must be a call whose first arg is `arg_name`, with `arg_name` used
  # exactly once in the whole body.
  defp body_is_first_arg_call(
         {fname, _, [{arg_name, _, ctx} | rest]} = body,
         arg_name
       )
       when is_atom(fname) and (is_nil(ctx) or is_atom(ctx)) and
              fname not in @binary_ops and fname not in @unary_ops and
              fname not in @disallowed_in_body and fname not in @non_callable_top_level do
    if count_var_refs(body, arg_name) == 1 do
      {:ok, {fname, [], rest}}
    else
      :error
    end
  end

  defp body_is_first_arg_call(
         {{:., m, [mod, fname]}, _, [{arg_name, _, ctx} | rest]} = body,
         arg_name
       )
       when is_atom(fname) and (is_nil(ctx) or is_atom(ctx)) do
    if count_var_refs(body, arg_name) == 1 do
      {:ok, {{:., m, [mod, fname]}, [], rest}}
    else
      :error
    end
  end

  defp body_is_first_arg_call(_, _), do: :error

  defp count_var_refs(ast, arg_name) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {name, _, ctx} = node, acc
        when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
          if name == arg_name, do: {node, acc + 1}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    count
  end

  defp issue_for(ctx, suggestion, meta) do
    format_issue(ctx,
      message: "Redundant `then/2` — the function can be called directly: `#{suggestion}`.",
      trigger: "then",
      line_no: meta[:line]
    )
  end
end
