defmodule Rbtz.CredoChecks.Warning.ApplicationPutEnvInTestsTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.ApplicationPutEnvInTests

  test "exposes metadata from `use Credo.Check`" do
    assert ApplicationPutEnvInTests.id() |> is_binary()
    assert ApplicationPutEnvInTests.category() |> is_atom()
    assert ApplicationPutEnvInTests.base_priority() |> is_atom()
    assert ApplicationPutEnvInTests.explanations()[:check] |> is_binary()
    assert ApplicationPutEnvInTests.param_defaults() |> is_list()
    assert ApplicationPutEnvInTests.param_names() |> is_list()
  end

  test "flags `Application.put_env` and `Application.put_all_env` in test files" do
    """
    defmodule MyApp.MailerTest do
      use ExUnit.Case

      test "skips delivery when disabled" do
        Application.put_env(:my_app, :deliver_emails, false)
        Application.put_all_env(my_app: [deliver_emails: false])
      end
    end
    """
    |> to_source_file("test/my_app/mailer_test.exs")
    |> run_check(ApplicationPutEnvInTests)
    |> assert_issues(fn issues ->
      assert issues |> Enum.map(&{&1.line_no, &1.trigger}) |> Enum.sort() == [
               {5, "Application.put_env"},
               {6, "Application.put_all_env"}
             ]
    end)
  end

  test "does not flag reads or `delete_env`" do
    """
    Application.get_env(:my_app, :deliver_emails)
    Application.fetch_env!(:my_app, :deliver_emails)
    Application.delete_env(:my_app, :deliver_emails)
    """
    |> to_source_file("test/my_app/mailer_test.exs")
    |> run_check(ApplicationPutEnvInTests)
    |> refute_issues()
  end

  test "does not flag test_helper.exs" do
    """
    Application.put_env(:my_app, :deliver_emails, false)
    ExUnit.start()
    """
    |> to_source_file("test/test_helper.exs")
    |> run_check(ApplicationPutEnvInTests)
    |> refute_issues()
  end

  test "does not flag files outside test/" do
    """
    Application.put_env(:my_app, :deliver_emails, false)
    """
    |> to_source_file("lib/my_app/release.ex")
    |> run_check(ApplicationPutEnvInTests)
    |> refute_issues()
  end
end
