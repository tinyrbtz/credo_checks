defmodule Rbtz.CredoChecks.Readability.PreferDateTimeShiftTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferDateTimeShift

  test "exposes metadata from `use Credo.Check`" do
    assert PreferDateTimeShift.id() |> is_binary()
    assert PreferDateTimeShift.category() |> is_atom()
    assert PreferDateTimeShift.base_priority() |> is_atom()
    assert PreferDateTimeShift.explanations()[:check] |> is_binary()
    assert PreferDateTimeShift.param_defaults() |> is_list()
    assert PreferDateTimeShift.param_names() |> is_list()
  end

  defp run(source) do
    source
    |> to_source_file()
    |> run_check(PreferDateTimeShift)
  end

  test "flags calendar units" do
    """
    DateTime.add(now, -7, :day)
    DateTime.add(now, 1, :week)
    NaiveDateTime.add(now, 2, :hour)
    Time.add(now, 5, :minute)
    """
    |> run()
    |> assert_issues(fn issues ->
      assert issues |> Enum.map(& &1.trigger) |> Enum.sort() ==
               ["DateTime.add", "DateTime.add", "NaiveDateTime.add", "Time.add"]
    end)
  end

  test "flags second offsets built from calendar factors" do
    """
    DateTime.add(now, 2 * 3600)
    DateTime.add(now, -days * 86_400, :second)
    DateTime.add(now, n * 24 * 60 * 60)
    DateTime.add(now, minutes * -60, :second)
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "flags literal multiples of 60 seconds" do
    """
    DateTime.add(now, 300, :second)
    DateTime.add(now, -3600)
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "flags piped calls" do
    """
    now |> DateTime.add(-1, :day)
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 1 end)
  end

  test "flags every `Date.add`" do
    """
    Date.add(today, -1)
    today |> Date.add(7 * weeks)
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["Date.add", "Date.add"]
    end)
  end

  test "does not flag genuine second and millisecond offsets" do
    """
    DateTime.add(now, 45, :second)
    DateTime.add(now, 90)
    DateTime.add(now, 0)
    DateTime.add(now, 250, :millisecond)
    DateTime.add(now, 60 * 1000, :millisecond)
    DateTime.add(now, timeout_seconds)
    DateTime.add(now, attempts * backoff, :second)
    now |> DateTime.add(45)
    """
    |> run()
    |> refute_issues()
  end

  test "does not flag `shift` or other modules' `add`" do
    """
    DateTime.shift(now, day: -7)
    Date.shift(today, day: 7)
    MapSet.add(set, :day)
    """
    |> run()
    |> refute_issues()
  end
end
