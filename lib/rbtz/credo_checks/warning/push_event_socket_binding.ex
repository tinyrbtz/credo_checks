defmodule Rbtz.CredoChecks.Warning.PushEventSocketBinding do
  use Credo.Check,
    id: "RBTZ0021",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires the result of `push_event/3` to be reassigned to `socket`
      rather than discarded as a statement.

      `push_event/3` returns a new socket with the queued event attached. If
      the return value is thrown away, the event never reaches the client —
      the call silently no-ops. The fix is always to rebind: `socket =
      push_event(socket, ...)` or to chain the call onto a pipe that
      propagates the socket.

      The check fires on `push_event` calls that appear as a non-final
      statement in a block, with their return value discarded. Pipes ending
      in `push_event` (`socket |> push_event(...)`) are flagged the same
      way; pipes that continue past `push_event` to another stage
      (`socket |> push_event(...) |> other()`) are not, because the
      downstream stage may or may not preserve the event — we can't tell.

      # Bad

          def handle_event("save", _, socket) do
            push_event(socket, "saved", %{})
            {:noreply, socket}
          end

      # Good

          def handle_event("save", _, socket) do
            socket = push_event(socket, "saved", %{})
            {:noreply, socket}
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  defp walk({:__block__, _meta, stmts} = ast, ctx) when is_list(stmts) and length(stmts) >= 2 do
    non_final = Enum.drop(stmts, -1)
    ctx = Enum.reduce(non_final, ctx, &check_stmt/2)
    {ast, ctx}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp check_stmt({:push_event, meta, args}, ctx) when is_list(args) and length(args) >= 2 do
    put_issue(ctx, issue_for(ctx, meta))
  end

  defp check_stmt({:|>, _meta, [_lhs, {:push_event, meta, _}]}, ctx) do
    put_issue(ctx, issue_for(ctx, meta))
  end

  defp check_stmt(_, ctx), do: ctx

  defp issue_for(ctx, meta) do
    format_issue(ctx,
      message:
        "`push_event/3` returns a new socket; rebind it (`socket = socket |> push_event(...)`) " <>
          "or chain it into a pipe. Discarding the return value silently drops the event.",
      trigger: "push_event",
      line_no: meta[:line]
    )
  end
end
