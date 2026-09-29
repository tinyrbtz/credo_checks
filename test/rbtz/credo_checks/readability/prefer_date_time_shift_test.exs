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

  defp messages(issues), do: issues |> Enum.sort_by(& &1.line_no) |> Enum.map(& &1.message)

  defp shift_options(issues) do
    for message <- messages(issues) do
      [_match, option] = Regex.run(~r/with `([^`]+)`/, message)
      option
    end
  end

  test "suggests the `shift` option matching the unit" do
    """
    DateTime.add(now, -@max_age_days, :day)
    Date.add(today, -1)
    """
    |> run()
    |> assert_issues(fn issues ->
      assert messages(issues) == [
               "Use `DateTime.shift/2` with `day: -@max_age_days` for calendar arithmetic; " <>
                 "reserve `DateTime.add/3` for second / millisecond offsets.",
               "Use `Date.shift/2` with `day: -1` for date arithmetic."
             ]
    end)
  end

  test "flags second offsets whose literal factors make whole minutes, suggesting the largest unit" do
    """
    DateTime.add(now, 2 * 3600)
    DateTime.add(now, -days * 86_400, :second)
    DateTime.add(now, n * 24 * 60 * 60)
    DateTime.add(now, minutes * -60, :second)
    DateTime.add(now, -(5 * 60))
    DateTime.add(now, 3 * n * 604_800)
    DateTime.add(now, 300, :second)
    DateTime.add(now, -3600)
    DateTime.add(now, 2 * 30 * n)
    """
    |> run()
    |> assert_issues(fn issues ->
      assert shift_options(issues) ==
               [
                 "hour: 2",
                 "day: -days",
                 "day: n",
                 "minute: -minutes",
                 "minute: -5",
                 "week: 3 * n",
                 "minute: 5",
                 "hour: -1",
                 "minute: n"
               ]
    end)
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
    DateTime.add(now, -timeout)
    DateTime.add(now, 90 * n)
    DateTime.add(now, amount, unit)
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
