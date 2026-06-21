defmodule Rbtz.CredoChecks.Readability.PreferNilEqualityTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferNilEquality

  test "exposes metadata from `use Credo.Check`" do
    assert PreferNilEquality.id() |> is_binary()
    assert PreferNilEquality.category() |> is_atom()
    assert PreferNilEquality.base_priority() |> is_atom()
    assert PreferNilEquality.explanations()[:check] |> is_binary()
    assert PreferNilEquality.param_defaults() |> is_list()
    assert PreferNilEquality.param_names() |> is_list()
  end

  describe "if / unless conditions" do
    test "flags `if is_nil(x)` with the `== nil` message" do
      """
      defmodule M do
        def go(x), do: if is_nil(x), do: :missing, else: x
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue(fn issue ->
        assert issue.trigger == "is_nil"
        assert issue.message =~ "== nil"
      end)
    end

    test "flags `if !is_nil(x)` with the `!= nil` message" do
      """
      defmodule M do
        def go(x), do: if !is_nil(x), do: x, else: :missing
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue(fn issue ->
        assert issue.message =~ "!= nil"
      end)
    end

    test "flags `if not is_nil(x)` with the `!= nil` message and does not double-flag" do
      """
      defmodule M do
        def go(x) do
          if not is_nil(x) do
            x
          else
            :missing
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue(fn issue ->
        assert issue.message =~ "!= nil"
      end)
    end

    test "flags `unless is_nil(x)`" do
      """
      defmodule M do
        def go(x), do: unless is_nil(x), do: x
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end

    test "flags both sides of `is_nil(x) and is_nil(y)`" do
      """
      defmodule M do
        def go(x, y), do: if is_nil(x) and is_nil(y), do: :both, else: :ok
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end

    test "flags `is_nil` mixed with non-nil checks once each (||, not)" do
      """
      defmodule M do
        def go(x, y), do: if is_nil(x) || not is_nil(y), do: :a, else: :b
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issues(fn issues ->
        assert length(issues) == 2
        assert Enum.any?(issues, &(&1.message =~ "== nil"))
        assert Enum.any?(issues, &(&1.message =~ "!= nil"))
      end)
    end

    test "flags is_nil in nested if inside an if body" do
      """
      defmodule M do
        def go(c, x) do
          if c do
            if is_nil(x), do: :missing, else: x
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end
  end

  describe "cond / case" do
    test "flags is_nil in a cond clause head" do
      """
      defmodule M do
        def go(x) do
          cond do
            is_nil(x) -> :missing
            true -> x
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end

    test "flags is_nil in a case scrutinee" do
      """
      defmodule M do
        def go(x) do
          case is_nil(x) do
            true -> :missing
            false -> x
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end
  end

  describe "assert / refute" do
    test "flags `assert is_nil(result)`" do
      """
      defmodule MTest do
        use ExUnit.Case
        test "x" do
          result = nil
          assert is_nil(result)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end

    test "flags `refute is_nil(result)`" do
      """
      defmodule MTest do
        use ExUnit.Case
        test "x" do
          result = 1
          refute is_nil(result)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end

    test "flags `assert not is_nil(result)` with `!= nil` message" do
      """
      defmodule MTest do
        use ExUnit.Case
        test "x" do
          result = 1
          assert not is_nil(result)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue(fn issue -> assert issue.message =~ "!= nil" end)
    end

    test "flags `assert is_nil(x), msg` (assert with custom message)" do
      ~s'''
      defmodule MTest do
        use ExUnit.Case
        test "x" do
          x = nil
          assert is_nil(x), "should be nil"
        end
      end
      '''
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> assert_issue()
    end
  end

  describe "does not flag" do
    test "is_nil in a `def` guard" do
      """
      defmodule M do
        def safe(x) when is_nil(x), do: :missing
        def safe(x), do: x
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "negated is_nil in a `def` guard" do
      """
      defmodule M do
        def safe(x) when not is_nil(x), do: x
        def safe(_), do: :missing
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "is_nil in an anonymous function guard" do
      """
      defmodule M do
        def go(xs), do: Enum.filter(xs, fn x when is_nil(x) -> true; _ -> false end)
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "is_nil in a `with` clause guard" do
      """
      defmodule M do
        def go(maybe) do
          with {:ok, x} when not is_nil(x) <- maybe do
            x
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "is_nil inside an Ecto query (`where:` keyword)" do
      """
      defmodule M do
        import Ecto.Query
        def active(q), do: from(u in q, where: is_nil(u.deleted_at))
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "bare assignment `flag = is_nil(x)`" do
      """
      defmodule M do
        def go(x) do
          flag = is_nil(x)
          flag
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "the `&is_nil/1` capture" do
      """
      defmodule M do
        def go(xs), do: Enum.filter(xs, &is_nil/1)
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "is_nil passed as an argument to another function inside an `if`" do
      """
      defmodule M do
        def go(x), do: if foo(is_nil(x)), do: :a, else: :b
        defp foo(b), do: b
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "case with pattern matching on `nil`" do
      """
      defmodule M do
        def go(x) do
          case x do
            nil -> :missing
            _ -> x
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "non-is_nil expression wrapped in `not` (e.g. `if not foo`)" do
      """
      defmodule M do
        def go(b), do: if not b, do: :a, else: :b
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end

    test "code already using `== nil` / `!= nil`" do
      """
      defmodule M do
        def go(x) do
          if x == nil, do: :missing, else: x
        end

        def go2(x) do
          unless x != nil, do: :missing
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferNilEquality)
      |> refute_issues()
    end
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PreferNilEquality.run(src, []) == []
  end
end
