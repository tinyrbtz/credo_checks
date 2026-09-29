defmodule Rbtz.CredoChecks.Warning.ObanUniqueOptions do
  use Credo.Check,
    id: "RBTZ0062",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires Oban workers that set `unique:` to state the dedupe period,
      and to pair `period: :infinity` with `states: :incomplete`.

      Oban's defaults make uniqueness surprising: without `period:` the
      window is 60 seconds, so a duplicate enqueued a minute later runs
      anyway. With `period: :infinity`, the default states include
      `:completed`, so the same args can never run again once a job
      finishes; `states: :incomplete` dedupes only the jobs that haven't
      finished yet. A finite period with the default states is a valid
      "at most once per window" throttle and is left alone.

      The check fires on `use Oban.Worker` / `use Oban.Pro.Worker` when
      `unique:` is `true` or a literal keyword list without `period:`, or
      with `period: :infinity` but not `states: :incomplete`. A computed
      value (a variable, module attribute, or function call) is left alone.

      # Bad

          use Oban.Worker, unique: [keys: [:user_id]]

          use Oban.Worker, unique: [keys: [:user_id], period: :infinity]

      # Good

          use Oban.Worker,
            unique: [
              keys: [:user_id],
              period: :infinity,
              states: :incomplete
            ]

          use Oban.Worker, unique: [keys: [:user_id], period: {1, :day}]
      """
    ]

  @workers [[:Oban, :Worker], [:Oban, :Pro, :Worker]]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  defp walk({:use, meta, [{:__aliases__, _, worker}, opts]} = ast, ctx)
       when worker in @workers and is_list(opts) do
    case missing_options(Keyword.get(opts, :unique)) do
      [] -> {ast, ctx}
      missing -> {ast, put_issue(ctx, issue_for(ctx, missing, meta))}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp missing_options(true), do: ["period: ..."]

  defp missing_options(unique) when is_list(unique) do
    case Keyword.fetch(unique, :period) do
      :error ->
        ["period: ..."]

      {:ok, :infinity} ->
        if Keyword.get(unique, :states) == :incomplete, do: [], else: ["states: :incomplete"]

      {:ok, _period} ->
        []
    end
  end

  defp missing_options(_computed), do: []

  defp issue_for(ctx, [option], meta) do
    format_issue(ctx,
      message: "Add `#{option}` to the worker's `unique:` options — " <> reason(option),
      trigger: "unique",
      line_no: meta[:line]
    )
  end

  defp reason("period: ..."),
    do:
      "without it Oban dedupes for only 60 seconds (use `:infinity` to dedupe until the job runs)."

  defp reason("states: :incomplete"),
    do: "with `period: :infinity`, the default states block re-enqueueing after a job completes."
end
