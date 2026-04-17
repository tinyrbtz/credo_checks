defmodule Rbtz.CredoChecks.Readability.PreferToTimeout do
  use Credo.Check,
    id: "RBTZ0048",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Prefers the Elixir 1.17+ `Kernel.to_timeout/1` helper over Erlang's
      `:timer.seconds/1`, `:timer.minutes/1`, `:timer.hours/1`, and
      `:timer.hms/3`.

      `to_timeout/1` is self-documenting, composes multiple units in a single
      call, and keeps timeout construction in idiomatic Elixir rather than
      Erlang interop.

      # Bad

          :timer.seconds(30)
          :timer.minutes(15)
          :timer.hours(1)
          :timer.hms(1, 30, 0)

      # Good

          to_timeout(second: 30)
          to_timeout(minute: 15)
          to_timeout(hour: 1)
          to_timeout(hour: 1, minute: 30)
      """
    ]

  @replacements %{
    {:seconds, 1} => "to_timeout(second: ...)",
    {:minutes, 1} => "to_timeout(minute: ...)",
    {:hours, 1} => "to_timeout(hour: ...)",
    {:hms, 3} => "to_timeout(hour: ..., minute: ..., second: ...)"
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

  defp walk({{:., _, [:timer, fname]}, meta, args}, ctx, piped?)
       when is_atom(fname) and is_list(args) do
    arity = length(args) + if piped?, do: 1, else: 0
    ctx = maybe_flag(ctx, fname, arity, meta)
    walk_children(args, ctx)
  end

  defp walk({_form, _meta, args}, ctx, _piped?) when is_list(args) do
    walk_children(args, ctx)
  end

  defp walk({a, b}, ctx, _piped?) do
    ctx = walk(a, ctx, false)
    walk(b, ctx, false)
  end

  defp walk(list, ctx, _piped?) when is_list(list) do
    walk_children(list, ctx)
  end

  defp walk(_, ctx, _piped?), do: ctx

  defp walk_children(list, ctx), do: Enum.reduce(list, ctx, &walk(&1, &2, false))

  defp maybe_flag(ctx, fname, arity, meta) do
    case Map.fetch(@replacements, {fname, arity}) do
      {:ok, suggestion} ->
        put_issue(ctx, issue_for(ctx, fname, arity, suggestion, meta))

      :error ->
        ctx
    end
  end

  defp issue_for(ctx, fname, arity, suggestion, meta) do
    format_issue(ctx,
      message:
        "Use `#{suggestion}` instead of `:timer.#{fname}/#{arity}` " <>
          "for self-documenting, composable timeouts.",
      trigger: ":timer.#{fname}",
      line_no: meta[:line]
    )
  end
end
