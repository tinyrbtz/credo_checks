defmodule Rbtz.CredoChecks.Readability.FunctionSpacing do
  use Credo.Check,
    id: "RBTZ0055",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Requires consistent blank-line spacing around function definitions so
      they stay visually separated and easy to scan.

      ## Blank line above the header block

      A function header may stack several attributes (`@doc`, `@impl`, `@spec`,
      …). Those may sit flush against each other, but the *block as a whole*
      must be separated from the previous statement by a blank line.

      Header attributes that may stack without blanks between them: `@doc`,
      `@impl`, `@spec`, `@dialyzer`, `@deprecated`, `@since`, and
      `@decorate` / `@decorate_all`. Full-line comments immediately above or
      below those attributes are part of the same header block.

      No blank line is required when the line above the block is the
      `defmodule` (or `defprotocol` / `defimpl`) that opens the body.

      A header block is always flush against the first clause of the function
      it documents — never a blank line between `@spec` / `@impl` / … and
      `def`.

      ## Multi-clause density (name + arity)

      Clauses of the same function (`def` / `defp` / `defmacro` /
      `defmacrop` with the same name and arity) share one layout, with or
      without a header:

        * **All single-line** — no blank lines between clauses.
        * **Any multi-line** — a blank line between every pair of consecutive
          clauses.

      # Bad — missing blank above header

          @spec one() :: :ok
          def one, do: :ok
          @spec two() :: :ok
          def two, do: :ok

      # Bad — blank under header

          @spec one() :: :ok

          def one, do: :ok

      # Bad — single-line clauses must stay compact

          def one(x) when is_atom(x), do: x

          def one(x) when is_integer(x), do: x

      # Bad — multi-line clauses must be separated

          def one(x) when is_atom(x), do: x
          def one(x) when is_integer(x) do
            x
          end

      # Good

          defmodule M do
            @spec one() :: :ok
            def one, do: :ok

            @spec two() :: :ok
            def two, do: :ok

            # all single-line → compact clauses, flush header
            @spec three(atom()) :: atom()
            def three(x) when is_atom(x), do: x
            def three(x) when is_integer(x), do: x

            # any multi-line → separated clauses, still flush header
            @spec four(atom()) :: atom()
            def four(x) when is_atom(x), do: x

            def four(x) when is_integer(x) do
              x
            end
          end
      """
    ]

  @header_attrs [
    :doc,
    :impl,
    :spec,
    :dialyzer,
    :deprecated,
    :since,
    :decorate,
    :decorate_all
  ]
  @def_ops [:def, :defp, :defmacro, :defmacrop]
  @module_forms [:defmodule, :defprotocol, :defimpl]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        lines =
          source_file
          |> SourceFile.lines()
          |> Map.new(fn {n, text} -> {n, String.trim(text)} end)

        {_, ctx} = Macro.prewalk(ast, ctx, &walk_module(&1, &2, lines))
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp walk_module({form, _meta, args} = ast, ctx, lines) when form in @module_forms do
    case List.last(args) do
      [do: body] -> {ast, check_body(body, ctx, lines)}
      _ -> {ast, ctx}
    end
  end

  defp walk_module(ast, ctx, _lines), do: {ast, ctx}

  defp check_body({:__block__, _meta, stmts}, ctx, lines) when is_list(stmts),
    do: scan(stmts, nil, ctx, lines)

  defp check_body(stmt, ctx, lines), do: scan([stmt], nil, ctx, lines)

  defp scan([], _prev, ctx, _lines), do: ctx

  defp scan([stmt | rest] = from, prev, ctx, lines) do
    ctx =
      cond do
        header_attr?(stmt) and not header_attr?(prev) ->
          check_header_block(ctx, stmt, from, prev, lines)

        def_group_start?(stmt, prev) ->
          maybe_density(ctx, nil, from, lines)

        true ->
          ctx
      end

    scan(rest, stmt, ctx, lines)
  end

  defp def_group_start?(stmt, prev) do
    key = def_key(stmt)
    key != nil and not header_attr?(prev) and key != def_key(prev)
  end

  defp check_header_block(ctx, {:@, meta, [{name, _, _}]}, from_header, prev, lines) do
    attr_line = meta[:line]
    block_start = expand_comments(lines, attr_line, -1, &(&1 >= 1))

    ctx =
      if separator_above?(lines, block_start, prev) do
        ctx
      else
        trigger = if block_start == attr_line, do: "@#{name}", else: "#"

        put_issue(
          ctx,
          format_issue(ctx,
            message: "There should be a blank line above the function header block.",
            trigger: trigger,
            line_no: block_start
          )
        )
      end

    {headers, after_headers} = Enum.split_while(from_header, &header_attr?/1)
    maybe_density(ctx, List.last(headers), after_headers, lines)
  end

  defp maybe_density(ctx, header, stmts, lines) do
    case clauses_for(stmts) do
      [] ->
        ctx

      [first | _] = clauses ->
        ctx
        |> check_header_flush(header, first, lines)
        |> check_clause_gaps(clauses, lines)
    end
  end

  defp check_header_flush(ctx, nil, _first, _lines), do: ctx

  defp check_header_flush(ctx, header, first, lines) do
    header_end =
      expand_comments(lines, end_line(header), 1, &(&1 < start_line(first)))

    if blank_between?(lines, header_end, start_line(first)) do
      density_issue(
        ctx,
        first,
        "There should be no blank line between the function header and the first clause."
      )
    else
      ctx
    end
  end

  defp check_clause_gaps(ctx, [_single], _lines), do: ctx

  defp check_clause_gaps(ctx, [first | _] = clauses, lines) do
    want_blank? = Enum.any?(clauses, &multi_line?/1)

    gap_mismatch? =
      clauses
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [a, b] ->
        blank_between?(lines, end_line(a), start_line(b)) != want_blank?
      end)

    if gap_mismatch? do
      density_issue(ctx, first, clause_gap_message(want_blank?))
    else
      ctx
    end
  end

  defp clause_gap_message(true) do
    "Multi-clause function has a multi-line clause; add a blank line between every pair of clauses."
  end

  defp clause_gap_message(false) do
    "Multi-clause function clauses are all single-line; remove blank lines between clauses."
  end

  defp multi_line?(ast), do: end_line(ast) > start_line(ast)

  defp clauses_for([first | rest]) do
    case def_key(first) do
      nil -> []
      key -> [first | Enum.take_while(rest, &(def_key(&1) == key))]
    end
  end

  defp clauses_for([]), do: []

  defp def_key({op, _meta, [head | _]}) when op in @def_ops, do: name_arity(unwrap_when(head))
  defp def_key(_), do: nil

  defp unwrap_when({:when, _meta, [call | _]}), do: call
  defp unwrap_when(call), do: call

  defp name_arity({name, _meta, nil}) when is_atom(name), do: {name, 0}

  defp name_arity({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp header_attr?({:@, _meta, [{name, _, _}]}) when name in @header_attrs, do: true
  defp header_attr?(_), do: false

  # First body statement (`prev == nil`) sits under the module opener — no blank
  # required. Comments are not AST statements, so a top-of-body comment+header
  # still has `prev == nil`.
  defp separator_above?(_lines, _block_start, nil), do: true
  defp separator_above?(lines, block_start, _prev), do: Map.get(lines, block_start - 1, "") == ""

  defp expand_comments(lines, line_no, step, still?) do
    next = line_no + step

    if still?.(next) and comment_line?(lines, next) do
      expand_comments(lines, next, step, still?)
    else
      line_no
    end
  end

  defp comment_line?(lines, line_no) do
    lines |> Map.get(line_no, "") |> String.starts_with?("#")
  end

  defp blank_between?(lines, from, to) do
    to > from + 1 and Enum.any?((from + 1)..(to - 1), &(Map.get(lines, &1, "") == ""))
  end

  defp start_line({_form, meta, _args}), do: meta[:line]

  defp end_line({_form, meta, _args}) do
    get_in(meta, [:end_of_expression, :line]) || meta[:line]
  end

  defp density_issue(ctx, {op, meta, _args}, message) do
    put_issue(
      ctx,
      format_issue(ctx, message: message, trigger: to_string(op), line_no: meta[:line])
    )
  end
end
