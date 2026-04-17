defmodule Rbtz.CredoChecks.Readability.AtomHttpStatusCodes do
  use Credo.Check,
    id: "RBTZ0009",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Forbids passing integer HTTP status codes to `Plug.Conn` and Phoenix
      controller helpers; use the corresponding atoms instead.

      Atoms (`:ok`, `:not_found`, `:unprocessable_entity`, ...) read more
      naturally than three-digit numbers, surface typos at compile time, and
      work uniformly across all `Plug.Conn` helpers.

      The check fires when a literal integer in the 100-599 range is passed
      as the status argument to `send_resp/3`, `put_status/2`, or `resp/3`
      (whether called directly or via `|>`, locally or as `Plug.Conn` /
      `Phoenix.Controller` remote calls).

      # Bad

          put_status(conn, 404)
          send_resp(conn, 200, body)
          Plug.Conn.resp(conn, 500, "oops")

      # Good

          put_status(conn, :not_found)
          send_resp(conn, :ok, body)
          Plug.Conn.resp(conn, :internal_server_error, "oops")
      """
    ]

  # function name => 0-indexed position of the status arg in the *unpiped* form.
  @status_arg_position %{
    send_resp: 1,
    put_status: 1,
    resp: 1
  }

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        ctx = walk(ast, ctx, false)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp walk({:|>, _meta, [lhs, rhs]}, ctx, _piped?) do
    ctx = walk(lhs, ctx, false)
    walk(rhs, ctx, true)
  end

  defp walk({fname, meta, args}, ctx, piped?) when is_atom(fname) and is_list(args) do
    ctx = maybe_flag(ctx, fname, meta, args, piped?)
    walk_children(args, ctx)
  end

  defp walk({{:., _, [_mod, fname]}, meta, args}, ctx, piped?)
       when is_atom(fname) and is_list(args) do
    ctx = maybe_flag(ctx, fname, meta, args, piped?)
    walk_children(args, ctx)
  end

  defp walk({_a, _meta, args}, ctx, _piped?) when is_list(args) do
    walk_children(args, ctx)
  end

  defp walk({a, b}, ctx, _piped?) do
    ctx = walk(a, ctx, false)
    walk(b, ctx, false)
  end

  defp walk(list, ctx, _piped?) when is_list(list) do
    walk_children(list, ctx)
  end

  defp walk(_, ctx, _), do: ctx

  defp walk_children(list, ctx) do
    Enum.reduce(list, ctx, &walk(&1, &2, false))
  end

  defp maybe_flag(ctx, fname, meta, args, piped?) do
    @status_arg_position
    |> Map.fetch(fname)
    |> case do
      {:ok, pos} ->
        adjusted = if piped?, do: pos - 1, else: pos

        case Enum.at(args, adjusted) do
          n when is_integer(n) and n >= 100 and n <= 599 ->
            put_issue(ctx, issue_for(ctx, fname, n, meta))

          _ ->
            ctx
        end

      :error ->
        ctx
    end
  end

  defp issue_for(ctx, fname, status, meta) do
    format_issue(ctx,
      message:
        "Use an atom status code instead of `#{status}` in `#{fname}`. " <>
          "Plug accepts atoms like `:ok`, `:not_found`, `:internal_server_error`.",
      trigger: to_string(fname),
      line_no: meta[:line]
    )
  end
end
