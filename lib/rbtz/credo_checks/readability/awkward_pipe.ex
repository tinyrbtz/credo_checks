defmodule Rbtz.CredoChecks.Readability.AwkwardPipe do
  use Credo.Check,
    id: "RBTZ0049",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Flags pipe (`|>`) usage patterns that hurt readability without providing
      chaining benefit — either because a single-step pipe is pure visual noise
      in the surrounding context, or because a pipe sits on either side of a
      binary operator and obscures precedence.

      Nine sub-rules are checked:

        1. **Either operand of `&&` / `||` is a pipe.** Operator-precedence
           and visual flow get muddled.

              # Bad
              check?(x) || x |> String.match?(~r/\\d/)

              # Bad (each pipe in a multi-line || chain still flagged)
              check?(x) ||
                x |> String.match?(~r/\\d/) ||
                y |> String.match?(~r/\\d/)

              # Good
              check?(x) || String.match?(x, ~r/\\d/)

        2. **Either operand of `++`, `<>`, `in`, `and`, `or` is a pipe.**

              # Bad
              base_url |> String.trim_trailing("/") <> url
              user |> role() in @admin_roles

              # Good
              String.trim_trailing(base_url, "/") <> url
              role(user) in @admin_roles

        3. **Pipe into the `Kernel.` operator form.** Every Elixir operator
           (`&&`, `||`, `and`, `or`, `!`, `not`, `+`, `-`, `*`, `/`, `++`,
           `--`, `<>`, `==`, `!=`, `===`, `!==`, `=~`, `<`, `<=`, `>`, `>=`,
           `in`) is reachable as `Kernel.<op>/n` as a function — using that
           form to fit an operator into a pipe chain hides it. Rewrite the
           chain and use the operator infix.

              # Bad
              attrs |> Map.get(:items) |> Kernel.||([])
              role |> String.to_atom() |> Kernel.in([:admin, :owner])
              list |> length() |> Kernel.-(1)

              # Good
              Map.get(attrs, :items) || []
              String.to_atom(role) in [:admin, :owner]
              length(list) - 1

        4. **Single-step pipe inside a tuple literal element.**

           ```elixir
           # Bad
           {:ok, socket |> assign(page_title: "Invite")}

           # Good
           {:ok, assign(socket, page_title: "Invite")}
           ```

        5. **Single-step pipe inside `#{} ` string interpolation.**

              # Bad
              "<ol>\#{data |> list_items_html()}</ol>"

              # Good
              "<ol>\#{list_items_html(data)}</ol>"

        6. **Single-step pipe as a non-first argument to a function call.**

              # Bad
              map |> Map.put(:slug, name |> String.downcase())

              # Good
              map |> Map.put(:slug, String.downcase(name))

        7. **`if` / `unless` / `cond` condition joins any pipe via
           `&&` / `||` / `and` / `or`.**

              # Bad
              if x |> something() && other_value do

              # Good
              if something(x) && other_value do

        8. **Single `|>` inside a single-line `fn … -> … end` or `&(…)`.**

              # Bad
              Enum.map(items, fn x -> x |> String.trim() end)
              Enum.any?(items, &(text |> String.contains?(&1)))

              # Good
              Enum.map(items, &String.trim/1)
              Enum.any?(items, &String.contains?(text, &1))

        9. **HEEx-only: single `|>` on the RHS of `<-` in `:for={…}` or
           `<%= for … %>`.**

              # Bad
              :for={{item, idx} <- @items |> Enum.with_index()}

              # Good
              :for={{item, idx} <- Enum.with_index(@items)}

      Multi-step chains (two or more `|>` in the same expression) are exempt
      from rules 4, 5, 6, 8, and 9 — a real chain is doing visible work and is
      preferred over nested calls.

      **Multi-line layout.** Rules 1, 2, 3, and 7 fire regardless of how the
      expression is laid out — a pipe mixed with `||`, `&&`, `and`, `or`,
      `++`, `<>`, `in`, or any `Kernel.` operator form (`Kernel.||`,
      `Kernel.&&`, `Kernel.and`, `Kernel.or`, `Kernel.+`, `Kernel.-`,
      `Kernel.==`, `Kernel.<`, `Kernel.in`, …) is always awkward, so line
      breaks never grant exemption. Rules 4, 5, and 6 fire
      only when the pipe operator itself fits on a single source line — a
      pipe whose LHS is itself multi-line (e.g. a heredoc
      `|> String.downcase()`) is structurally unavoidable and is exempt.
      Rule 8 is intrinsically about single-line anonymous functions. Rule 9
      scans HEEx templates line-by-line.
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  # Every Elixir operator is reachable as `Kernel.<op>/n` as a function —
  # using that function form to fit an operator into a pipe chain hides the
  # operator. Rule 3 flags any pipe whose RHS is `Kernel.<op>(...)`. Ranges
  # (`..`, `..//`) are excluded: the parser treats `Kernel..<x>` as a range
  # with `Kernel` as LHS, so they cannot appear as a pipe's RHS call head.
  @kernel_ops [
    :&&,
    :||,
    :and,
    :or,
    :!,
    :not,
    :+,
    :-,
    :*,
    :/,
    :++,
    :--,
    :<>,
    :==,
    :!=,
    :===,
    :!==,
    :=~,
    :<,
    :<=,
    :>,
    :>=,
    :in
  ]
  @and_or_both [:&&, :||]
  # Rule 2 ops. `<>`, `++`, `in` bind *tighter* than `|>`, so the canonical
  # shape for `a |> f() <> b` is `{:|>, _, [a, {:<>, _, [f_call, b]}]}` — the
  # `<>` hides inside the pipe's RHS. `and`, `or` bind *looser*, so `a |> f()
  # and b` is `{:and, _, [{:|>, ...}, b]}`. Rule 2 is detected in both places.
  @binary_flag_ops [:++, :<>, :in, :and, :or]
  @binary_flag_inside_pipe [:++, :<>, :in]
  @condition_join_ops [:&&, :||, :and, :or]

  # Three-tuple AST forms that look like `{atom, meta, args}` but are not
  # function calls — Rule 6 must not treat their `args` as a call's argument
  # list. Examples: `:->` (clause separator — otherwise multi-clause `fn`
  # bodies containing a single pipe would be flagged as "arg-position pipes";
  # `:<-` (comprehension/for generator — the user explicitly excluded plain
  # `.ex` `for` comprehensions from Rule 9); `:=` (match); `:when` (guard);
  # `:__block__` (sequence of statements); `:|` (cons / map-update). Binary
  # comparison operators (`==`, `!=`, `===`, `!==`, `<`, `<=`, `>`, `>=`,
  # `=~`) are also not calls — pipes on either side are not awkward.
  @non_call_heads [:->, :<-, :=, :when, :__block__, :|] ++
                    [:==, :!=, :===, :!==, :<, :<=, :>, :>=, :=~]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    ast_ctx =
      case Credo.Code.ast(source_file) do
        {:ok, ast} -> walk(ast, ctx)
        _ -> ctx
      end

    final_ctx = scan_heex(source_file, ast_ctx)

    final_ctx.issues
    |> Enum.reverse()
    |> Enum.uniq_by(fn issue -> {issue.line_no, issue.column} end)
  end

  # --- Walker -------------------------------------------------------------

  # Pipe node: check Rule 3 (pipe into any Kernel.<op>) and Rule 2 (pipe then tight
  # binary op — `|> f() <> x`, etc.), then descend. The RHS of a pipe is
  # "piped" — every explicit arg is effectively a non-first arg.
  defp walk({:|>, meta, [lhs, rhs]}, ctx) do
    ctx =
      ctx
      |> maybe_flag_kernel_op(rhs, meta)
      |> maybe_flag_tight_binop_in_pipe(rhs)

    ctx = walk(lhs, ctx)
    walk_piped(rhs, ctx)
  end

  # Rule 1: `&&` / `||` with a pipe on either operand. Flags regardless of
  # layout — pipes mixed with these operators are always awkward.
  defp walk({op, meta, [lhs, rhs]}, ctx) when op in @and_or_both do
    ctx =
      if pipe?(lhs) or pipe?(rhs) do
        put_issue(ctx, rule1_issue(ctx, op, meta))
      else
        ctx
      end

    ctx = walk(lhs, ctx)
    walk(rhs, ctx)
  end

  # Rule 2: `++` / `<>` / `in` / `and` / `or` with a pipe on either operand.
  defp walk({op, meta, [lhs, rhs]}, ctx) when op in @binary_flag_ops do
    ctx =
      if pipe?(lhs) or pipe?(rhs) do
        put_issue(ctx, rule2_issue(ctx, op, meta))
      else
        ctx
      end

    ctx = walk(lhs, ctx)
    walk(rhs, ctx)
  end

  # Rule 7: if / unless condition.
  defp walk({op, meta, [cond_expr | rest]}, ctx) when op in [:if, :unless] do
    ctx = maybe_flag_condition(ctx, cond_expr, op, meta)
    ctx = walk(cond_expr, ctx)
    Enum.reduce(rest, ctx, &walk/2)
  end

  # Rule 7: cond. Each clause is `{:->, _, [[lhs], body]}` — single-pattern
  # on the left is a structural invariant of `cond`.
  defp walk({:cond, _meta, [[{:do, clauses}]]}, ctx) when is_list(clauses) do
    Enum.reduce(clauses, ctx, fn {:->, cmeta, [[lhs], body]}, ctx ->
      ctx = maybe_flag_condition(ctx, lhs, :cond, cmeta)
      ctx = walk(lhs, ctx)
      walk(body, ctx)
    end)
  end

  # Rule 8: fn lambda (single-clause only — multi-clause fns can't fit on one
  # line anyway).
  defp walk({:fn, meta, [{:->, _, [_args, _body]}] = clauses} = node, ctx) do
    ctx = maybe_flag_fn(ctx, node, meta)
    Enum.reduce(clauses, ctx, &walk/2)
  end

  # Rule 8: `&(...)` capture.
  defp walk({:&, meta, [body]} = node, ctx) do
    ctx = maybe_flag_capture(ctx, node, body, meta)
    walk(body, ctx)
  end

  # Rule 5: interpolating binary.
  defp walk({:<<>>, _meta, parts}, ctx) when is_list(parts) do
    ctx = Enum.reduce(parts, ctx, &maybe_flag_interp_part/2)
    Enum.reduce(parts, ctx, &walk/2)
  end

  # Rule 4: 3+-tuple literal.
  defp walk({:{}, meta, elems}, ctx) when is_list(elems) do
    ctx = maybe_flag_tuple_elems(ctx, elems, meta)
    Enum.reduce(elems, ctx, &walk/2)
  end

  # Map literal — entries are `{key, value}` pairs, not tuple literals. Walk
  # values without passing through the 2-tuple arm below.
  defp walk({:%{}, _meta, entries}, ctx) when is_list(entries) do
    Enum.reduce(entries, ctx, &walk_map_entry/2)
  end

  # Struct literal: `{:%, _, [name, map_ast]}`.
  defp walk({:%, _meta, [name, map_ast]}, ctx) do
    ctx = walk(name, ctx)
    walk(map_ast, ctx)
  end

  # Special forms with `{atom, meta, args}` shape but no call semantics —
  # descend without treating them as calls.
  defp walk({head, _meta, args}, ctx) when head in @non_call_heads and is_list(args) do
    Enum.reduce(args, ctx, &walk/2)
  end

  # Rule 6: function call. Check args at position >= 1 for single-step pipes.
  defp walk({fname, _meta, args}, ctx) when is_atom(fname) and is_list(args) do
    ctx = maybe_flag_non_first_args(ctx, args, false)
    Enum.reduce(args, ctx, &walk/2)
  end

  defp walk({{:., _, _} = dot_expr, _meta, args}, ctx) when is_list(args) do
    ctx = maybe_flag_non_first_args(ctx, args, false)
    ctx = walk(dot_expr, ctx)
    Enum.reduce(args, ctx, &walk/2)
  end

  # List — distinguish keyword-list from plain list.
  defp walk(list, ctx) when is_list(list) do
    if keyword_like?(list) do
      Enum.reduce(list, ctx, &walk_kw_entry/2)
    else
      Enum.reduce(list, ctx, &walk/2)
    end
  end

  # Rule 4: 2-tuple literal (outside maps/keyword-lists/struct bodies).
  defp walk({a, b}, ctx) do
    meta = [line: tuple_literal_line(a, b)]
    ctx = maybe_flag_tuple_elems(ctx, [a, b], meta)
    ctx = walk(a, ctx)
    walk(b, ctx)
  end

  # Leaves (and any 3-tuple whose first element is not a matched atom/dot).
  defp walk(_node, ctx), do: ctx

  # A pipe's RHS: any explicit arg is an "effective non-first" arg. Only
  # recognised shapes are flaggable calls; everything else is walked as normal.
  defp walk_piped({fname, _meta, args}, ctx) when is_atom(fname) and is_list(args) do
    ctx = maybe_flag_non_first_args(ctx, args, true)
    Enum.reduce(args, ctx, &walk/2)
  end

  defp walk_piped({{:., _, _} = dot_expr, _meta, args}, ctx) when is_list(args) do
    ctx = maybe_flag_non_first_args(ctx, args, true)
    ctx = walk(dot_expr, ctx)
    Enum.reduce(args, ctx, &walk/2)
  end

  defp walk_piped(other, ctx), do: walk(other, ctx)

  # Keyword-list entries: descend into the value, not the `{key, value}`
  # wrapper (it's not a tuple literal). `keyword_like?/1` guarantees every
  # element is a 2-tuple so no fallback is needed.
  defp walk_kw_entry({_key, value}, ctx), do: walk(value, ctx)

  # Map literal entries: `{k, v}` for both atom- and non-atom-key forms.
  defp walk_map_entry({k, v}, ctx) do
    ctx = walk(k, ctx)
    walk(v, ctx)
  end

  # Map-update entries live inside `%{m | ...}` and are represented as
  # `{:|, _, [base, updates]}` — a 3-tuple, not a 2-tuple.
  defp walk_map_entry(other, ctx), do: walk(other, ctx)

  # --- Predicates ---------------------------------------------------------

  defp pipe?({:|>, _, _}), do: true
  defp pipe?(_), do: false

  defp single_step_pipe?({:|>, _, [lhs, _]}), do: not pipe?(lhs)
  defp single_step_pipe?(_), do: false

  # Non-binary-op rules (4 tuple element, 5 interpolation hole, 6 non-first arg)
  # exempt pipes whose operator itself spans multiple source lines (canonical:
  # heredoc |> String.downcase()). Binary-op rules do not call this — they flag
  # pipes regardless of layout.
  #
  # A source-level check complements the AST check because non-interpolated
  # heredoc literals are stored as raw binaries in the AST with no line meta —
  # AST alone can't tell that the LHS spanned multiple lines. If the source
  # text before `|>` on its line contains a heredoc closing delimiter, the LHS
  # was a heredoc.
  defp pipe_single_line?({:|>, meta, _} = pipe, ctx) do
    single_line_construct?(pipe) and not lhs_is_multi_line_in_source?(ctx, meta)
  end

  defp lhs_is_multi_line_in_source?(ctx, meta) do
    line_no = meta[:line]
    col = meta[:column]

    if is_integer(line_no) and is_integer(col) do
      line = SourceFile.line_at(ctx.source_file, line_no) || ""
      before_pipe = String.slice(line, 0, col - 1)

      # Heredoc/sigil close before `|>` on the same line, or `|>` is the first
      # non-whitespace on its line (LHS is on a previous line).
      String.contains?(before_pipe, ~s(""")) or
        String.contains?(before_pipe, "'''") or
        String.trim(before_pipe) == ""
    else
      false
    end
  end

  defp keyword_like?([]), do: false

  defp keyword_like?([_ | _] = list) do
    Enum.all?(list, fn
      {k, _} when is_atom(k) -> true
      _ -> false
    end)
  end

  # --- Rule checks --------------------------------------------------------

  # Rule 3: pipe into a `Kernel.<op>(arg)` call. `Credo.Code.ast/1` always
  # emits the `:__aliases__` form for `Kernel`, so the bare-atom shape does
  # not need a clause here.
  defp maybe_flag_kernel_op(
         ctx,
         {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, _, _} = _rhs,
         meta
       )
       when op in @kernel_ops do
    put_issue(ctx, rule3_issue(ctx, op, meta))
  end

  defp maybe_flag_kernel_op(ctx, _rhs, _meta), do: ctx

  # Rule 2 (tight-op path): pipe's RHS is `<>` / `++` / `in` because those
  # bind tighter than `|>`.
  defp maybe_flag_tight_binop_in_pipe(ctx, {op, meta, [_, _]})
       when op in @binary_flag_inside_pipe do
    put_issue(ctx, rule2_issue(ctx, op, meta))
  end

  defp maybe_flag_tight_binop_in_pipe(ctx, _rhs), do: ctx

  # Rule 4: any tuple element that is itself a single-line, single-step pipe.
  defp maybe_flag_tuple_elems(ctx, elems, meta) do
    Enum.reduce(elems, ctx, fn elem, ctx ->
      if single_step_pipe?(elem) and pipe_single_line?(elem, ctx) do
        put_issue(ctx, rule4_issue(ctx, line_of(elem) || meta[:line]))
      else
        ctx
      end
    end)
  end

  # Rule 5: each interpolation hole whose inner is a single-step, single-line
  # pipe.
  defp maybe_flag_interp_part(
         {:"::", _,
          [
            {{:., _, [Kernel, :to_string]}, _, [inner]},
            {:binary, _, _}
          ]},
         ctx
       ) do
    if single_step_pipe?(inner) and pipe_single_line?(inner, ctx) do
      put_issue(ctx, rule5_issue(ctx, line_of(inner)))
    else
      ctx
    end
  end

  defp maybe_flag_interp_part(_part, ctx), do: ctx

  # Rule 6: args at position >= 1 (or all args, when the call is piped) that
  # are themselves single-line single-step pipes.
  defp maybe_flag_non_first_args(ctx, args, piped?) do
    start_idx = if piped?, do: 0, else: 1

    args
    |> Enum.with_index()
    |> Enum.reduce(ctx, fn {arg, idx}, ctx ->
      if idx >= start_idx and single_step_pipe?(arg) and pipe_single_line?(arg, ctx) do
        put_issue(ctx, rule6_issue(ctx, line_of(arg)))
      else
        ctx
      end
    end)
  end

  # Rule 7: condition contains a pipe joined by &&/||/and/or. Flags regardless
  # of whether the condition itself is multi-line.
  defp maybe_flag_condition(ctx, cond_expr, construct, meta) do
    if condition_has_joined_pipe?(cond_expr) do
      put_issue(ctx, rule7_issue(ctx, construct, meta))
    else
      ctx
    end
  end

  # Single-pass: maintain a depth counter of "inside a join op"; if we see a
  # pipe at depth > 0, that pipe is in the subtree of a join op — flag it.
  # Using `Macro.traverse/4` for the post callback to decrement depth on exit.
  defp condition_has_joined_pipe?(expr) do
    Macro.traverse(
      expr,
      0,
      fn
        {op, _, _} = node, depth when op in @condition_join_ops ->
          {node, depth + 1}

        {:|>, _, _} = node, depth when depth > 0 ->
          throw(:found)
          {node, depth}

        node, depth ->
          {node, depth}
      end,
      fn
        {op, _, _} = node, depth when op in @condition_join_ops ->
          {node, depth - 1}

        node, depth ->
          {node, depth}
      end
    )

    false
  catch
    :found -> true
  end

  # Rule 8: `fn` single-clause, single-line, body contains exactly one `|>`.
  defp maybe_flag_fn(ctx, {:fn, _, [{:->, _, [_args, body]}]} = node, meta) do
    if single_line_construct?(node) and pipe_count(body) == 1 do
      put_issue(ctx, rule8_issue(ctx, :fn, meta))
    else
      ctx
    end
  end

  # Rule 8: capture `&(body)`.
  defp maybe_flag_capture(ctx, node, body, meta) do
    if single_line_construct?(node) and pipe_count(body) == 1 do
      put_issue(ctx, rule8_issue(ctx, :&, meta))
    else
      ctx
    end
  end

  defp single_line_construct?(ast) do
    lines =
      ast
      |> collect_lines()
      |> Enum.reject(&is_nil/1)

    match?([_ | _], lines) and Enum.min(lines) == Enum.max(lines)
  end

  defp collect_lines(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {_, meta, _} = node, acc when is_list(meta) ->
          {node, meta_lines(meta) ++ acc}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # Pull every line number we can find out of a meta keyword list. Credo parses
  # with `token_metadata: true`, which adds `closing` / `do` / `end` /
  # `end_of_expression` sub-metas — these matter for multi-line detection
  # because they cover the *end* of a paren/brace/do-end span, not just its
  # start.
  defp meta_lines(meta) do
    [
      meta[:line],
      sub_meta_line(meta[:closing]),
      sub_meta_line(meta[:do]),
      sub_meta_line(meta[:end]),
      sub_meta_line(meta[:end_of_expression])
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp sub_meta_line(meta) when is_list(meta), do: meta[:line]
  defp sub_meta_line(_), do: nil

  defp pipe_count(ast) do
    {_, n} =
      Macro.prewalk(ast, 0, fn
        {:|>, _, _} = node, n -> {node, n + 1}
        node, n -> {node, n}
      end)

    n
  end

  defp line_of({_, meta, _}) when is_list(meta), do: meta[:line]
  defp line_of(_), do: nil

  defp tuple_literal_line(a, b), do: line_of(a) || line_of(b)

  # --- HEEx (Rule 9) ------------------------------------------------------

  defp scan_heex(source_file, ctx) do
    source_file
    |> HeexSource.templates()
    |> Enum.reduce(ctx, fn {contents, line_fn}, ctx ->
      scan_heex_template(contents, line_fn, ctx)
    end)
  end

  defp scan_heex_template(contents, line_fn, ctx) do
    contents
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce(ctx, fn {line, idx}, ctx ->
      if awkward_for_rhs?(line) do
        put_issue(ctx, rule9_issue(ctx, line_fn.(idx)))
      else
        ctx
      end
    end)
  end

  defp awkward_for_rhs?(line) do
    line
    |> scan_arrows()
    |> Enum.any?(&arrow_rhs_awkward?/1)
  end

  # Scan for all `<-` occurrences and return the RHS substring for each.
  defp scan_arrows(line) do
    line
    |> String.split(~r/\s<-\s+/)
    |> Enum.drop(1)
  end

  defp arrow_rhs_awkward?(after_arrow) do
    rhs = trim_rhs(after_arrow)
    pipe_occurrences(rhs) == 1
  end

  defp trim_rhs(text) do
    # Stop at the HEEx block terminator ` do %>` or the end of the `:for={...}`
    # brace. We use the first matching terminator; if none is present (rare),
    # the whole remainder is the RHS.
    cond do
      String.contains?(text, " do %>") ->
        [head, _] = String.split(text, " do %>", parts: 2)
        head

      String.contains?(text, "}") ->
        [head, _] = String.split(text, "}", parts: 2)
        head

      true ->
        text
    end
  end

  defp pipe_occurrences(text) do
    length(String.split(text, "|>")) - 1
  end

  # --- Issue builders -----------------------------------------------------

  defp rule1_issue(ctx, op, meta) do
    format_issue(ctx,
      message:
        "Avoid piping on either side of `#{op}`; rewrite the pipe as a plain function call.",
      trigger: Atom.to_string(op),
      line_no: meta[:line]
    )
  end

  defp rule2_issue(ctx, op, meta) do
    format_issue(ctx,
      message:
        "Avoid piping on either side of `#{op}`; rewrite the pipe as a plain function call.",
      trigger: Atom.to_string(op),
      line_no: meta[:line]
    )
  end

  defp rule3_issue(ctx, op, meta) do
    format_issue(ctx,
      message:
        "Avoid piping into `Kernel.#{op}`; break the chain and use `#{op}` directly in its infix form.",
      trigger: "Kernel.#{op}",
      line_no: meta[:line]
    )
  end

  defp rule4_issue(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid a single-step pipe inside a tuple literal — use the plain function-call form.",
      trigger: "|>",
      line_no: line_no
    )
  end

  defp rule5_issue(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid a single-step pipe inside string interpolation — use the plain function-call form.",
      trigger: "|>",
      line_no: line_no
    )
  end

  defp rule6_issue(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid a single-step pipe in a non-first argument position — use the plain function-call form.",
      trigger: "|>",
      line_no: line_no
    )
  end

  defp rule7_issue(ctx, construct, meta) do
    format_issue(ctx,
      message:
        "Avoid pipes joined by `&&`/`||`/`and`/`or` in an `#{construct}` condition — rewrite as plain calls.",
      trigger: Atom.to_string(construct),
      line_no: meta[:line]
    )
  end

  defp rule8_issue(ctx, kind, meta) do
    trigger = if kind == :fn, do: "fn", else: "&"

    format_issue(ctx,
      message:
        "Avoid a single-step pipe inside a single-line anonymous function — use a capture (`&fun/arity` or `&mod.fun/arity`) or the plain call form.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp rule9_issue(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid a single-step pipe on the RHS of `<-` inside HEEx `:for=` / `for` — use the plain function-call form.",
      trigger: "<-",
      line_no: line_no
    )
  end
end
