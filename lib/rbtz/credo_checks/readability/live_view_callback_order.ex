defmodule Rbtz.CredoChecks.Readability.LiveViewCallbackOrder do
  use Credo.Check,
    id: "RBTZ0032",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Enforces a consistent top-to-bottom callback order in
      `Phoenix.LiveView` modules:

        1. `mount`
        2. `handle_params`
        3. `handle_event`
        4. `handle_info`
        5. `handle_async`
        6. `render`

      Reading a LiveView top-to-bottom in this order matches the lifecycle
      itself: how the view boots, how it reacts to URL changes, how it reacts
      to user events, how it reacts to messages, then the rendering. When
      callbacks are interleaved arbitrarily it takes longer to find the bit
      of behavior you're looking for and harder to spot missing handlers.

      Non-callback `def`/`defp` (helpers) are ignored — they may appear
      anywhere in the module. Only the relative order of the LiveView
      callbacks listed above is checked.

      The check only runs against modules that declare `use Phoenix.LiveView`
      directly or `use SomethingWeb, :live_view`. Multiple clauses of the
      same callback are fine; they share a bucket. The first out-of-order
      callback is flagged.

      # Bad

          def mount(_, _, socket), do: {:ok, socket}
          def render(assigns), do: ~H""
          def handle_event("x", _, socket), do: {:noreply, socket}

      # Good

          def mount(_, _, socket), do: {:ok, socket}
          def handle_event("x", _, socket), do: {:noreply, socket}
          def render(assigns), do: ~H""
      """
    ]

  @callback_buckets %{
    mount: 1,
    handle_params: 2,
    handle_event: 3,
    handle_info: 4,
    handle_async: 5,
    render: 6
  }

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, ctx} = Macro.prewalk(ast, ctx, &walk_module/2)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp walk_module({:defmodule, _meta, [_alias, [do: body]]} = ast, ctx) do
    if live_view_module?(body) do
      {ast, check_body(body, ctx)}
    else
      {ast, ctx}
    end
  end

  defp walk_module(ast, ctx), do: {ast, ctx}

  defp live_view_module?(body) do
    body
    |> body_statements()
    |> Enum.any?(&use_live_view?/1)
  end

  defp body_statements({:__block__, _meta, stmts}), do: stmts
  defp body_statements(stmt), do: [stmt]

  defp use_live_view?({:use, _, [{:__aliases__, _, [:Phoenix, :LiveView]} | _]}), do: true
  defp use_live_view?({:use, _, [_module, :live_view]}), do: true
  defp use_live_view?(_), do: false

  defp check_body(body, ctx) do
    body
    |> body_statements()
    |> Enum.flat_map(&def_bucket/1)
    |> find_first_violation()
    |> case do
      nil -> ctx
      {bucket, line_no, name} -> put_issue(ctx, issue_for(ctx, bucket, line_no, name))
    end
  end

  defp def_bucket({op, _meta, [{name, name_meta, _args} | _]})
       when op in [:def, :defp] and is_atom(name) do
    if bucket = @callback_buckets[name] do
      [{name, bucket, name_meta[:line]}]
    else
      []
    end
  end

  defp def_bucket(_), do: []

  defp find_first_violation(defs) do
    result =
      Enum.reduce_while(defs, 0, fn {name, bucket, line_no}, max_seen ->
        if bucket < max_seen do
          {:halt, {bucket, line_no, name}}
        else
          {:cont, max(max_seen, bucket)}
        end
      end)

    case result do
      {_, _, _} = violation -> violation
      _ -> nil
    end
  end

  defp issue_for(ctx, _bucket, line_no, name) do
    format_issue(ctx,
      message:
        "LiveView callback `#{name}` is out of order. Expected order: " <>
          "mount → handle_params → handle_event → handle_info → handle_async → render.",
      trigger: to_string(name),
      line_no: line_no
    )
  end
end
