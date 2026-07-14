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

      ## Multi-clause density (name + arity)

      Clauses of the same function (`def` / `defp` / `defmacro` /
      `defmacrop` with the same name and arity) share one layout, with or
      without a header:

        * **All single-line** — no blank lines between clauses, and (when a
          header is present) no blank line under the header.
        * **Any multi-line** — a blank line between every pair of consecutive
          clauses, and (when a header is present) a blank line under the
          header.

      # Bad — missing blank above header

          @spec one() :: :ok
          def one, do: :ok
          @spec two() :: :ok
          def two, do: :ok

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

            # all single-line → compact
            @spec three(atom()) :: atom()
            def three(x) when is_atom(x), do: x
            def three(x) when is_integer(x), do: x

            # any multi-line → separated
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
        {_, ctx} = Macro.prewalk(ast, ctx, &walk_module/2)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp walk_module({form, _meta, args} = ast, ctx) when form in @module_forms do
    case List.last(args) do
      [do: body] -> {ast, check_body(body, ctx)}
      _ -> {ast, ctx}
    end
  end

  defp walk_module(ast, ctx), do: {ast, ctx}

  defp check_body({:__block__, _meta, stmts}, ctx) when is_list(stmts), do: scan(stmts, nil, ctx)
  defp check_body(stmt, ctx), do: scan([stmt], nil, ctx)

  defp scan([], _prev, ctx), do: ctx

  defp scan([stmt | rest] = from, prev, ctx) do
    ctx =
      cond do
        header_attr?(stmt) and not header_attr?(prev) ->
          check_header_block(ctx, stmt, from)

        def_group_start?(stmt, prev) ->
          maybe_density(ctx, nil, from)

        true ->
          ctx
      end

    scan(rest, stmt, ctx)
  end

  defp def_group_start?(stmt, prev) do
    key = def_key(stmt)
    key != nil and not header_attr?(prev) and key != def_key(prev)
  end

  defp check_header_block(ctx, {:@, meta, [{name, _, _}]}, from_header) do
    source = ctx.source_file
    attr_line = meta[:line]
    block_start = expand_comments_up(source, attr_line)

    ctx =
      if separator_above?(source, block_start) do
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
    maybe_density(ctx, List.last(headers), after_headers)
  end

  defp maybe_density(ctx, header, stmts) do
    case clauses_for(stmts) do
      [_, _ | _] = clauses -> check_density(ctx, header, clauses)
      _ -> ctx
    end
  end

  defp check_density(ctx, header, [first | _] = clauses) do
    source = ctx.source_file
    want_blank? = Enum.any?(clauses, &multi_line?/1)

    gap_mismatch? =
      clauses
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [a, b] ->
        blank_between?(source, end_line(a), start_line(b)) != want_blank?
      end)

    ctx =
      if gap_mismatch? do
        density_issue(ctx, first, clause_gap_message(want_blank?))
      else
        ctx
      end

    check_header_gap(ctx, header, first, want_blank?)
  end

  defp check_header_gap(ctx, nil, _first, _want_blank?), do: ctx

  defp check_header_gap(ctx, header, first, want_blank?) do
    source = ctx.source_file
    header_end = expand_comments_down(source, end_line(header), start_line(first))
    has_blank? = blank_between?(source, header_end, start_line(first))

    if has_blank? == want_blank? do
      ctx
    else
      density_issue(ctx, first, header_gap_message(want_blank?))
    end
  end

  defp clause_gap_message(true) do
    "Multi-clause function has a multi-line clause; add a blank line between every pair of clauses."
  end

  defp clause_gap_message(false) do
    "Multi-clause function clauses are all single-line; remove blank lines between clauses."
  end

  defp header_gap_message(true) do
    "Multi-clause function has a multi-line clause; add a blank line between the function header and the first clause."
  end

  defp header_gap_message(false) do
    "Multi-clause function clauses are all single-line; remove the blank line between the function header and the first clause."
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

  defp separator_above?(source, line_no) do
    previous = trimmed_line(source, line_no - 1)
    previous == "" or String.match?(previous, ~r/^(defmodule|defprotocol|defimpl)\b/)
  end

  defp expand_comments_up(source, line_no) do
    prev = line_no - 1

    if prev >= 1 and comment_line?(source, prev) do
      expand_comments_up(source, prev)
    else
      line_no
    end
  end

  defp expand_comments_down(source, line_no, stop_before) do
    next = line_no + 1

    if next < stop_before and comment_line?(source, next) do
      expand_comments_down(source, next, stop_before)
    else
      line_no
    end
  end

  defp comment_line?(source, line_no) do
    source |> trimmed_line(line_no) |> String.starts_with?("#")
  end

  defp trimmed_line(source, line_no) do
    (SourceFile.line_at(source, line_no) || "") |> String.trim()
  end

  defp blank_between?(source, from, to) do
    to > from + 1 and Enum.any?((from + 1)..(to - 1), &(trimmed_line(source, &1) == ""))
  end

  defp start_line({_form, meta, _args}), do: meta[:line]

  defp end_line({_form, meta, _args}) do
    meta
    |> Keyword.get(:end_of_expression)
    |> List.wrap()
    |> Keyword.get(:line, meta[:line])
  end

  defp density_issue(ctx, {op, meta, _args}, message) do
    put_issue(
      ctx,
      format_issue(ctx, message: message, trigger: to_string(op), line_no: meta[:line])
    )
  end
end
