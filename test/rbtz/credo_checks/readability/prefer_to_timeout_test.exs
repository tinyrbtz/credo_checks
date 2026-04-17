defmodule Rbtz.CredoChecks.Readability.PreferToTimeoutTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferToTimeout

  test "exposes metadata from `use Credo.Check`" do
    assert PreferToTimeout.id() |> is_binary()
    assert PreferToTimeout.category() |> is_atom()
    assert PreferToTimeout.base_priority() |> is_atom()
    assert PreferToTimeout.explanation() |> is_binary()
    assert PreferToTimeout.params_defaults() |> is_list()
    assert PreferToTimeout.params_names() |> is_list()
  end

  test "flags `:timer.seconds/1`" do
    """
    defmodule M do
      def t, do: :timer.seconds(30)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> assert_issue()
  end

  test "flags `:timer.minutes/1`" do
    """
    defmodule M do
      def t, do: :timer.minutes(15)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> assert_issue()
  end

  test "flags `:timer.hours/1`" do
    """
    defmodule M do
      def t, do: :timer.hours(1)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> assert_issue()
  end

  test "flags `:timer.hms/3`" do
    """
    defmodule M do
      def t, do: :timer.hms(1, 30, 0)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> assert_issue()
  end

  test "flags piped `:timer.minutes/1`" do
    """
    defmodule M do
      def t(n), do: n |> :timer.minutes()
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> assert_issue()
  end

  test "flags multiple occurrences" do
    """
    defmodule M do
      def a, do: :timer.seconds(1)
      def b, do: :timer.minutes(2)
      def c, do: :timer.hours(3)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "does not flag `to_timeout/1`" do
    """
    defmodule M do
      def a, do: to_timeout(second: 30)
      def b, do: to_timeout(minute: 15)
      def c, do: to_timeout(hour: 1, minute: 30)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> refute_issues()
  end

  test "does not flag `:timer.sleep/1`" do
    """
    defmodule M do
      def t, do: :timer.sleep(100)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> refute_issues()
  end

  test "does not flag unrelated remote calls" do
    """
    defmodule M do
      def a, do: Foo.minutes(5)
      def b, do: Bar.hms(1, 2, 3)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> refute_issues()
  end

  test "does not flag `:timer.minutes` at unexpected arity" do
    """
    defmodule M do
      def t, do: :timer.minutes(1, 2)
    end
    """
    |> to_source_file()
    |> run_check(PreferToTimeout)
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PreferToTimeout.run(src, []) == []
  end
end
