defmodule Rbtz.CredoChecks.Warning.SetMimicGlobal do
  use Credo.Check,
    id: "RBTZ0013",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Forbids enabling Mimic in global mode (`set_mimic_global`) inside test
      files.

      `set_mimic_global` allows mocks to be observed and set from any
      process, but it forces the test (and every test in its `setup_all`
      scope) to run synchronously. Once a single test opts in to global
      Mimic, the whole test module loses `async: true` parallelism.

      If you genuinely need cross-process mocking, isolate the affected test
      to its own module and accept the synchronous cost there — don't push
      it on the rest of the suite.

      # Bad

          setup :set_mimic_global

          setup_all :set_mimic_global

      # Good

          setup :verify_on_exit!
          # use `set_mimic_private` (the default) and pass mocks to spawned
          # processes via `Mimic.allow/3` if needed
      """
    ]

  alias Rbtz.CredoChecks.TestSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if TestSource.test_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp walk({op, meta, args} = ast, ctx)
       when op in [:setup, :setup_all] and is_list(args) do
    if Enum.any?(args, &set_mimic_global?/1) do
      {ast, put_issue(ctx, issue_for(ctx, op, meta))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp set_mimic_global?(:set_mimic_global), do: true

  defp set_mimic_global?({:set_mimic_global, _meta, _args}), do: true

  defp set_mimic_global?(list) when is_list(list) do
    not Keyword.keyword?(list) and Enum.any?(list, &set_mimic_global?/1)
  end

  defp set_mimic_global?(_), do: false

  defp issue_for(ctx, op, meta) do
    format_issue(ctx,
      message:
        "`#{op} :set_mimic_global` forces the test module to run synchronously. " <>
          "Use `set_mimic_private` (the default) and `Mimic.allow/3` for cross-process mocking.",
      trigger: ":set_mimic_global",
      line_no: meta[:line]
    )
  end
end
