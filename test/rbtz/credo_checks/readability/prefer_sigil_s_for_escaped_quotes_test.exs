defmodule Rbtz.CredoChecks.Readability.PreferSigilSForEscapedQuotesTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferSigilSForEscapedQuotes

  test "exposes metadata from `use Credo.Check`" do
    assert PreferSigilSForEscapedQuotes.id() |> is_binary()
    assert PreferSigilSForEscapedQuotes.category() |> is_atom()
    assert PreferSigilSForEscapedQuotes.base_priority() |> is_atom()
    assert PreferSigilSForEscapedQuotes.explanation() |> is_binary()
    assert PreferSigilSForEscapedQuotes.params_defaults() |> is_list()
    assert PreferSigilSForEscapedQuotes.params_names() |> is_list()
  end

  test "flags a double-quoted string with escaped quotes" do
    ~S"""
    defmodule MyMod do
      def msg, do: "Run \"mix test.coverage\" once all exports complete"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> assert_issue()
  end

  test "flags a string with a single escaped quote" do
    ~S"""
    defmodule MyMod do
      def msg, do: "He said \"hi\""
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> assert_issue()
  end

  test "does not flag a plain double-quoted string" do
    """
    defmodule MyMod do
      def msg, do: "Run mix test.coverage once all exports complete"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> refute_issues()
  end

  test "does not flag strings with other escape sequences" do
    ~S"""
    defmodule MyMod do
      def a, do: "line one\nline two"
      def b, do: "tab\there"
      def c, do: "backslash \\ here"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> refute_issues()
  end

  test "does not flag ~s sigil" do
    ~S"""
    defmodule MyMod do
      def msg, do: ~s(Run "mix test.coverage" once)
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> refute_issues()
  end

  test "does not flag heredocs that contain quotes" do
    ~S'''
    defmodule MyMod do
      def msg, do: """
      Run "mix test.coverage" once all exports complete
      """
    end
    '''
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> refute_issues()
  end

  test "does not flag charlists" do
    ~S"""
    defmodule MyMod do
      def msg, do: ~c"a \"char\"list"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> refute_issues()
  end

  test "still flags interpolated strings with escaped quotes" do
    ~S"""
    defmodule MyMod do
      def msg(x), do: "Value: \"#{x}\" received"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> assert_issue()
  end

  test "flags every offending string independently" do
    ~S"""
    defmodule MyMod do
      def a, do: "one \"quote\""
      def b, do: "two \"quotes\" here"
      def c, do: "clean string"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "does not flag a string containing only `\\\\`" do
    ~S"""
    defmodule MyMod do
      def msg, do: "path\\to\\thing"
    end
    """
    |> to_source_file()
    |> run_check(PreferSigilSForEscapedQuotes)
    |> refute_issues()
  end
end
