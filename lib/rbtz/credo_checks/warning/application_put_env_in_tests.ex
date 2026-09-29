defmodule Rbtz.CredoChecks.Warning.ApplicationPutEnvInTests do
  use Credo.Check,
    id: "RBTZ0060",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Forbids `Application.put_env` / `Application.put_all_env` in tests.

      Application env is global: changing it in one test leaks into every
      test running at the same time, so the test has to be `async: false`
      and restore the old value in `on_exit`. Read the value through a
      function in the app instead and stub that function (e.g. with Mimic)
      for the one test that needs a different value.

      `test_helper.exs` is exempt — it runs once, before any test starts.

      # Bad

          test "skips delivery when disabled" do
            Application.put_env(:my_app, :deliver_emails, false)
            on_exit(fn -> Application.delete_env(:my_app, :deliver_emails) end)
            # ...
          end

      # Good

          test "skips delivery when disabled" do
            MyApp.Config
            |> stub(:deliver_emails?, fn -> false end)
            # ...
          end
      """
    ]

  alias Rbtz.CredoChecks.TestSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if TestSource.test_file?(source_file.filename) and
         Path.basename(source_file.filename) != "test_helper.exs" do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp walk({{:., _, [{:__aliases__, _, [:Application]}, fun]}, meta, _args} = ast, ctx)
       when fun in [:put_env, :put_all_env] do
    issue =
      format_issue(ctx,
        message:
          "Don't change application env in tests — it's global, so the test can't run async. " <>
            "Read the value through a function and stub that instead.",
        trigger: "Application.#{fun}",
        line_no: meta[:line]
      )

    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}
end
