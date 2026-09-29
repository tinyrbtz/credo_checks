defmodule Rbtz.CredoChecks.Warning.ObanUniqueOptionsTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.ObanUniqueOptions

  test "exposes metadata from `use Credo.Check`" do
    assert ObanUniqueOptions.id() |> is_binary()
    assert ObanUniqueOptions.category() |> is_atom()
    assert ObanUniqueOptions.base_priority() |> is_atom()
    assert ObanUniqueOptions.explanations()[:check] |> is_binary()
    assert ObanUniqueOptions.param_defaults() |> is_list()
    assert ObanUniqueOptions.param_names() |> is_list()
  end

  defp run(source) do
    source
    |> to_source_file()
    |> run_check(ObanUniqueOptions)
  end

  test "flags `unique:` without a period" do
    """
    defmodule MyApp.SyncWorker do
      use Oban.Worker, queue: :default, unique: [keys: [:user_id]]
    end
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "`period: ...`"
    end)
  end

  test "flags an infinite period without `states: :incomplete`" do
    """
    defmodule MyApp.SyncWorker do
      use Oban.Pro.Worker, unique: [period: :infinity, states: :all]
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "`states: :incomplete`" end)
  end

  test "flags `unique: true`" do
    """
    defmodule MyApp.SyncWorker do
      use Oban.Worker, unique: true
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "`period: ...`" end)
  end

  test "does not flag complete options, finite periods, computed values, or workers without `unique:`" do
    """
    defmodule MyApp.SyncWorker do
      use Oban.Worker,
        unique: [
          keys: [:user_id],
          period: :infinity,
          states: :incomplete
        ]
    end

    defmodule MyApp.DigestWorker do
      use Oban.Worker, unique: [keys: [:user_id], period: {1, :day}]
    end

    defmodule MyApp.ImportWorker do
      use Oban.Worker, unique: @unique_opts
    end

    defmodule MyApp.CleanupWorker do
      use Oban.Worker, unique: [keys: [:id]] ++ @extra
    end

    defmodule MyApp.MailWorker do
      use Oban.Worker, queue: :mailers
    end

    defmodule MyApp.PlainWorker do
      use Oban.Worker
    end
    """
    |> run()
    |> refute_issues()
  end
end
