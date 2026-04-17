defmodule Rbtz.CredoChecks.Readability.PreferCaptureTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferCapture

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PreferCapture.run(src, []) == []
  end

  test "exposes metadata from `use Credo.Check`" do
    assert PreferCapture.id() |> is_binary()
    assert PreferCapture.category() |> is_atom()
    assert PreferCapture.base_priority() |> is_atom()
    assert PreferCapture.explanation() |> is_binary()
    assert PreferCapture.params_defaults() |> is_list()
    assert PreferCapture.params_names() |> is_list()
  end

  describe "band A — direct pass-through" do
    test "flags local one-arg pass-through (`fn x -> foo(x) end` → `&foo/1`)" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> foo(x) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&foo/1" end)
    end

    test "flags local two-arg pass-through (`fn x, y -> foo(x, y) end` → `&foo/2`)" do
      """
      defmodule M do
        def go(xs), do: Enum.reduce(xs, 0, fn x, y -> add(x, y) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&add/2" end)
    end

    test "flags remote pass-through (`fn x -> Mod.foo(x) end` → `&Mod.foo/1`)" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> String.upcase(x) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&String.upcase/1" end)
    end

    test "flags nested-module remote pass-through" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> A.B.C.foo(x) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&A.B.C.foo/1" end)
    end
  end

  describe "band B — simple expressions" do
    test "flags `fn x -> x * 2 end` → `&(&1 * 2)`" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> x * 2 end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&(&1 * 2)" end)
    end

    test "flags `fn x -> x == :ok end` → `&(&1 == :ok)`" do
      """
      defmodule M do
        def go(xs), do: Enum.filter(xs, fn x -> x == :ok end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&(&1 == :ok)" end)
    end

    test "flags unary operator body (`fn x -> not x end` → `&(not &1)`)" do
      """
      defmodule M do
        def go(xs), do: Enum.filter(xs, fn x -> not x end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&(not &1)" end)
    end
  end

  describe "band C — partial application" do
    test "flags remote partial application (`fn x -> Map.get(x, :key) end` → `&Map.get(&1, :key)`)" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> Map.get(x, :key) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&Map.get(&1, :key)" end)
    end

    test "flags local partial application with a closure var" do
      """
      defmodule M do
        def go(xs, closure_var) do
          Enum.map(xs, fn x -> foo(closure_var, x) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&foo(closure_var, &1)" end)
    end

    test "flags multi-arg where one position wraps the arg in another call" do
      """
      defmodule M do
        def go(xs), do: Enum.reduce(xs, 0, fn x, y -> foo(x, g(y)) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&foo(&1, g(&2))" end)
    end

    test "flags remote call via a variable module (falls through to rewrite)" do
      """
      defmodule M do
        def go(xs, mod), do: Enum.map(xs, fn x -> mod.foo(x) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue -> assert issue.message =~ "&mod.foo(&1)" end)
    end
  end

  describe "does not flag" do
    test "multi-clause fns" do
      """
      defmodule M do
        def go(xs) do
          Enum.map(xs, fn
            :ok -> 1
            :error -> 2
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "pattern-matched tuple arg" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn {a, b} -> a + b end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "pattern-matched struct arg" do
      """
      defmodule M do
        def go(users), do: Enum.map(users, fn %User{name: n} -> n end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "guards" do
      """
      defmodule M do
        def go(xs), do: Enum.filter(xs, fn x when x > 0 -> x end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "arg used more than once" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> x + x end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "arg unused (underscore)" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn _ -> :ok end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "one of multiple args unused" do
      """
      defmodule M do
        def go(xs), do: Enum.reduce(xs, 0, fn x, _y -> foo(x) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "zero-arity anonymous fn" do
      """
      defmodule M do
        def go, do: Task.async(fn -> :ok end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "multi-statement body" do
      """
      defmodule M do
        def go(xs) do
          Enum.map(xs, fn x ->
            y = expensive(x)
            transform(y)
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "case body" do
      """
      defmodule M do
        def go(xs) do
          Enum.map(xs, fn x ->
            case x do
              :ok -> 1
              :error -> 0
            end
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "if body" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> if x, do: 1, else: 0 end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "pipe body" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> x |> foo() |> bar() end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "body containing a nested fn" do
      """
      defmodule M do
        def go(xs) do
          Enum.map(xs, fn x -> Enum.map(x, fn y -> foo(y) end) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> assert_issue(fn issue ->
        # The inner fn is flagged; the outer fn is not (contains a nested fn).
        assert issue.message =~ "&foo/1"
      end)
    end

    test "body containing an existing capture" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> Enum.map(x, &foo/1) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "out-of-order args" do
      """
      defmodule M do
        def go(xs), do: Enum.reduce(xs, 0, fn x, y -> sub(y, x) end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "identity `fn x -> x end`" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> x end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "literal body with no arg reference" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, fn x -> :ok end)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end

    test "existing capture form is ignored" do
      """
      defmodule M do
        def go(xs), do: Enum.map(xs, &String.upcase/1)
      end
      """
      |> to_source_file()
      |> run_check(PreferCapture)
      |> refute_issues()
    end
  end
end
