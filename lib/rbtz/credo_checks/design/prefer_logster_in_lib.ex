defmodule Rbtz.CredoChecks.Design.PreferLogsterInLib do
  use Credo.Check,
    id: "RBTZ0015",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Forbids the standard `Logger` module in application code under `lib/`.

      This project standardises on `Logster` for application logs (it adds
      structured metadata, service-tagging, and request/job correlation that
      the bare `Logger` module cannot). Reaching for `Logger` skips that
      pipeline and produces logs that won't be correlated or filterable in
      production.

      The check fires when application code calls one of the `Logger`
      log-level functions (`debug`, `info`, `notice`, `warning`, `warn`,
      `error`, `critical`, `alert`, `emergency`, `log`) or uses `require
      Logger` / `import Logger`. It only inspects files under `lib/`;
      `test/` and `config/` may continue to use `Logger` directly.

      Other `Logger` functions (e.g. `Logger.metadata/0,1`,
      `Logger.configure/1`) are **not** flagged — they manage logger state
      and Logster reads from it.

      # Bad

          # in lib/my_app/orders.ex
          require Logger
          Logger.info("doing the thing")

      # Good

          # in lib/my_app/orders.ex
          Logster.info("doing the thing", order_id: order.id)
      """
    ]

  @log_fns [
    :debug,
    :info,
    :notice,
    :warning,
    :warn,
    :error,
    :critical,
    :alert,
    :emergency,
    :log
  ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if lib_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp lib_file?(filename) when is_binary(filename) do
    filename |> Path.expand() |> String.contains?("/lib/")
  end

  defp lib_file?(_), do: false

  # `Logger.info(...)`, `Logger.log(...)`, etc. — only the log-level fns.
  defp walk({{:., _, [{:__aliases__, _, [:Logger]}, fname]}, meta, _args} = ast, ctx)
       when fname in @log_fns do
    {ast, put_issue(ctx, issue_for(ctx, "Logger.#{fname}", meta))}
  end

  # `require Logger` / `import Logger`
  defp walk({op, meta, [{:__aliases__, _, [:Logger]}]} = ast, ctx)
       when op in [:require, :import] do
    {ast, put_issue(ctx, issue_for(ctx, "#{op} Logger", meta))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, trigger, meta) do
    format_issue(ctx,
      message:
        "Use `Logster` instead of `Logger` in application code under `lib/`. " <>
          "Logster adds structured metadata and service tagging that the bare `Logger` module cannot.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
