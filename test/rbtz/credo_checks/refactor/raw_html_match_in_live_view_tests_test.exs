defmodule Rbtz.CredoChecks.Refactor.RawHtmlMatchInLiveViewTestsTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.RawHtmlMatchInLiveViewTests

  test "exposes metadata from `use Credo.Check`" do
    assert RawHtmlMatchInLiveViewTests.id() |> is_binary()
    assert RawHtmlMatchInLiveViewTests.category() |> is_atom()
    assert RawHtmlMatchInLiveViewTests.base_priority() |> is_atom()
    assert RawHtmlMatchInLiveViewTests.explanation() |> is_binary()
    assert RawHtmlMatchInLiveViewTests.params_defaults() |> is_list()
    assert RawHtmlMatchInLiveViewTests.params_names() |> is_list()
  end

  test ~s(flags `html =~ "text"`) do
    """
    defmodule MyLiveTest do
      use ExUnit.Case

      test "renders" do
        html = render(view)
        assert html =~ "Welcome"
      end
    end
    """
    |> to_source_file("test/my_live_test.exs")
    |> run_check(RawHtmlMatchInLiveViewTests)
    |> assert_issue()
  end

  test ~s|flags `render(view) =~ "text"`| do
    """
    defmodule MyLiveTest do
      use ExUnit.Case

      test "renders" do
        assert render(view) =~ "Welcome"
      end
    end
    """
    |> to_source_file("test/my_live_test.exs")
    |> run_check(RawHtmlMatchInLiveViewTests)
    |> assert_issue()
  end

  test ~s{flags `view |> render() =~ "text"`} do
    """
    defmodule MyLiveTest do
      use ExUnit.Case

      test "renders" do
        assert view |> render() =~ "Welcome"
      end
    end
    """
    |> to_source_file("test/my_live_test.exs")
    |> run_check(RawHtmlMatchInLiveViewTests)
    |> assert_issue()
  end

  test "does not flag `html =~ ~r/.../`" do
    """
    defmodule MyLiveTest do
      use ExUnit.Case

      test "renders" do
        html = render(view)
        assert html =~ ~r/Welcome/
      end
    end
    """
    |> to_source_file("test/my_live_test.exs")
    |> run_check(RawHtmlMatchInLiveViewTests)
    |> refute_issues()
  end

  test ~s(does not flag `log =~ "text"` in a log-capture test) do
    """
    defmodule ReqLoggerTest do
      use ExUnit.Case, async: false
      import ExUnit.CaptureLog

      test "logs a message" do
        log = capture_log(fn -> :ok end)
        assert log =~ "[debug] hello"
      end
    end
    """
    |> to_source_file("test/req/req_logger_test.exs")
    |> run_check(RawHtmlMatchInLiveViewTests)
    |> refute_issues()
  end

  test "does not flag in non-test files" do
    """
    defmodule M do
      def matches?(html), do: html =~ "Welcome"
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(RawHtmlMatchInLiveViewTests)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert RawHtmlMatchInLiveViewTests.run(src, []) == []
  end
end
