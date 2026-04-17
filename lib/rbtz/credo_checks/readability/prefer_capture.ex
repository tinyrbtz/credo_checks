defmodule Rbtz.CredoChecks.Readability.PreferCapture do
  use Credo.Check,
    id: "RBTZ0046",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Encourages the capture syntax `&` for anonymous functions that just
      pass their arguments through to another function or apply a simple
      operator to them.

      When an `fn` forwards its arguments (in the same order) to a function
      call, or applies a single operator to a single argument, the capture
      form says the same thing with less ceremony and keeps the surrounding
      pipeline easy to scan.

      # Bad

          Enum.map(list, fn x -> String.upcase(x) end)
          Enum.map(list, fn x -> x * 2 end)
          Enum.map(list, fn x -> Map.get(x, :key) end)

      # Good

          Enum.map(list, &String.upcase/1)
          Enum.map(list, &(&1 * 2))
          Enum.map(list, &Map.get(&1, :key))

      The check flags three bands:

        1. **Pass-through** — `fn x -> foo(x) end` → `&foo/1`, including
           multi-arg calls in the same order and remote calls.
        2. **Simple expressions** — `fn x -> x * 2 end` → `&(&1 * 2)` for
           operator bodies.
        3. **Partial application** — `fn x -> Map.get(x, :key) end` →
           `&Map.get(&1, :key)` where only some arguments are captured.

      The check is intentionally conservative — the following are **not**
      flagged:

        * Anonymous functions with multiple clauses.
        * Pattern-matched arguments (`fn {a, b} -> ... end`).
        * Guards (`fn x when x > 0 -> ... end`).
        * Arguments used zero or more than once in the body.
        * Multi-arg fns where the arguments appear in a different order
          than declared (`fn x, y -> f(y, x) end`).
        * Multi-statement bodies, or `case` / `cond` / `if` / `with` / `try`
          bodies.
        * Pipe-chain bodies (`fn x -> x |> a() |> b() end`).
        * Bodies containing a nested `fn` or `&` capture.
        * Bodies containing `assert` / `refute` (and relatives) — ExUnit
          assertion macros can't be captured.
        * Zero-arity anonymous functions and the identity `fn x -> x end`.
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

  # Forms that block flagging if they appear anywhere in the body — either
  # syntactically disallowed inside a capture (`fn`, `&`), semantically ugly
  # (`|>`, control flow), breaking our "each arg used exactly once" invariant,
  # or macros that rewrite their argument shape (ExUnit assertions, `dbg`)
  # and so can't be captured.
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

  # Forms that appear as an atom node head but aren't function calls — data
  # constructors and special forms. These are rejected as a top-level body
  # shape so we don't suggest capturing a `%{...}` / `<<...>>` / `{...}`.
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

  # Valid identifier for the RHS of `&name/arity` form.
  @identifier_regex ~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/

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

  # Single-clause fn — classify and maybe flag.
  defp walk({:fn, meta, [{:->, _, [args, body]}]} = ast, ctx) do
    case classify(args, body) do
      {:flag, suggestion} ->
        {ast, put_issue(ctx, issue_for(ctx, suggestion, meta))}

      :skip ->
        {ast, ctx}
    end
  end

  # Multi-clause fn, or anything else — Macro.prewalk descends automatically.
  defp walk(ast, ctx), do: {ast, ctx}

  defp classify(args, body) do
    with {:ok, arg_names} <- extract_plain_args(args),
         false <- body_has_disallowed?(body),
         true <- shape_ok?(body),
         {:ok, occurrences} <- find_arg_refs(arg_names, body),
         :ok <- each_used_once(arg_names, occurrences),
         :ok <- in_declaration_order(arg_names, occurrences) do
      {:flag, render_suggestion(arg_names, body)}
    else
      _ -> :skip
    end
  end

  defp extract_plain_args([]), do: :error

  defp extract_plain_args(args) do
    case Enum.reduce_while(args, [], &collect_plain_arg/2) do
      :error -> :error
      names -> finalise_arg_names(names)
    end
  end

  defp collect_plain_arg({name, _, ctx}, acc)
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    if underscore_prefixed?(name), do: {:halt, :error}, else: {:cont, [name | acc]}
  end

  defp collect_plain_arg(_arg, _acc), do: {:halt, :error}

  defp underscore_prefixed?(name) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp finalise_arg_names(names) do
    names = Enum.reverse(names)
    if length(Enum.uniq(names)) == length(names), do: {:ok, names}, else: :error
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

  # Allowed top-level body shapes: binary op, unary op, remote call, local call.
  defp shape_ok?({op, _, [_, _]}) when op in @binary_ops, do: true
  defp shape_ok?({op, _, [_]}) when op in @unary_ops, do: true
  defp shape_ok?({{:., _, _}, _, args}) when is_list(args), do: true

  defp shape_ok?({fname, _, args})
       when is_atom(fname) and is_list(args) and
              fname not in @disallowed_in_body and
              fname not in @non_callable_top_level do
    true
  end

  defp shape_ok?(_), do: false

  defp find_arg_refs(arg_names, body) do
    arg_set = MapSet.new(arg_names)

    {_, acc} =
      Macro.prewalk(body, [], fn
        {name, meta, ctx} = node, acc
        when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
          if MapSet.member?(arg_set, name) do
            {node, [{name, meta[:line] || 0, meta[:column] || 0} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    {:ok, Enum.reverse(acc)}
  end

  defp each_used_once(arg_names, occurrences) do
    counts = Enum.frequencies_by(occurrences, fn {name, _, _} -> name end)

    if map_size(counts) == length(arg_names) and
         Enum.all?(arg_names, &(Map.get(counts, &1) == 1)) do
      :ok
    else
      :error
    end
  end

  defp in_declaration_order(arg_names, occurrences) do
    ordered_names =
      occurrences
      |> Enum.sort_by(fn {_, line, col} -> {line, col} end)
      |> Enum.map(fn {name, _, _} -> name end)

    if ordered_names == arg_names, do: :ok, else: :error
  end

  defp render_suggestion(arg_names, body) do
    case band_a(arg_names, body) do
      {:ok, capture} -> capture
      :skip -> render_rewrite(arg_names, body)
    end
  end

  # Local call pass-through: `fn x, y -> foo(x, y) end` → `&foo/2`.
  # Operator bodies (`fn x -> not x end`, `fn x, y -> x + y end`) fall through
  # to the rewrite path so they render as `&(not &1)` / `&(&1 + &2)` rather
  # than the terse-but-unusual `&not/1` / `&+/2` forms.
  defp band_a(arg_names, {fname, _, call_args})
       when is_atom(fname) and is_list(call_args) and
              fname not in @disallowed_in_body and
              fname not in @non_callable_top_level and
              fname not in @binary_ops and
              fname not in @unary_ops do
    if call_args_match_exactly?(call_args, arg_names) and
         Regex.match?(@identifier_regex, Atom.to_string(fname)) do
      {:ok, "&#{fname}/#{length(arg_names)}"}
    else
      :skip
    end
  end

  # Remote call pass-through: `fn x -> Mod.foo(x) end` → `&Mod.foo/1`.
  defp band_a(arg_names, {{:., _, [mod, fname]}, _, call_args})
       when is_atom(fname) and is_list(call_args) do
    with true <- call_args_match_exactly?(call_args, arg_names),
         true <- Regex.match?(@identifier_regex, Atom.to_string(fname)),
         {:ok, mod_str} <- render_module(mod) do
      {:ok, "&#{mod_str}.#{fname}/#{length(arg_names)}"}
    else
      _ -> :skip
    end
  end

  defp band_a(_, _), do: :skip

  defp call_args_match_exactly?(call_args, arg_names) do
    if length(call_args) == length(arg_names) do
      call_args
      |> Enum.zip(arg_names)
      |> Enum.all?(&pair_matches?/1)
    else
      false
    end
  end

  defp pair_matches?({{name, _, ctx}, expected})
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    name == expected
  end

  defp pair_matches?(_), do: false

  # Only standard `Alias.Foo.Bar` modules get the compact `&Mod.fun/arity`
  # capture form. Bare-atom modules (`:erlang.foo/1`) and variable modules
  # (`mod.foo(x)`) fall through to the expression-rewrite path, which
  # produces a still-valid capture like `&:erlang.foo(&1)`.
  defp render_module({:__aliases__, _, parts}) when is_list(parts) do
    {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
  end

  defp render_module(_), do: :error

  defp render_rewrite(arg_names, body) do
    name_to_idx = arg_names |> Enum.with_index(1) |> Map.new()

    rewritten =
      Macro.prewalk(body, fn
        {name, meta, ctx} = node
        when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
          case Map.fetch(name_to_idx, name) do
            {:ok, idx} -> {:&, meta, [idx]}
            :error -> node
          end

        node ->
          node
      end)

    body_str = Macro.to_string(rewritten)

    case body do
      {op, _, _} when op in @binary_ops or op in @unary_ops ->
        "&(#{body_str})"

      _ ->
        "&#{body_str}"
    end
  end

  defp issue_for(ctx, suggestion, meta) do
    format_issue(ctx,
      message: "Anonymous function can be rewritten as a capture: `#{suggestion}`.",
      trigger: "fn",
      line_no: meta[:line]
    )
  end
end
