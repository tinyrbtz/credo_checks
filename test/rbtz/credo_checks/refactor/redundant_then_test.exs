defmodule Rbtz.CredoChecks.Refactor.RedundantThenTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.RedundantThen

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert RedundantThen.run(src, []) == []
  end

  test "exposes metadata from `use Credo.Check`" do
    assert RedundantThen.id() |> is_binary()
    assert RedundantThen.category() |> is_atom()
    assert RedundantThen.base_priority() |> is_atom()
    assert RedundantThen.explanation() |> is_binary()
    assert RedundantThen.params_defaults() |> is_list()
    assert RedundantThen.params_names() |> is_list()
  end

  describe "flags piped form" do
    test "arity-1 remote capture (`|> then(&String.upcase/1)` → `String.upcase()`)" do
      """
      defmodule M do
        def go(x), do: x |> then(&String.upcase/1)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`String.upcase()`" end)
    end

    test "arity-1 local capture (`|> then(&foo/1)` → `foo()`)" do
      """
      defmodule M do
        def go(x), do: x |> then(&foo/1)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`foo()`" end)
    end

    test "arity-1 nested-module capture" do
      """
      defmodule M do
        def go(x), do: x |> then(&A.B.C.foo/1)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`A.B.C.foo()`" end)
    end

    test "remote partial application (`|> then(&Map.get(&1, :key))` → `Map.get(:key)`)" do
      """
      defmodule M do
        def go(m), do: m |> then(&Map.get(&1, :key))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`Map.get(:key)`" end)
    end

    test "local partial application with multiple remaining args" do
      """
      defmodule M do
        def go(x, closure) do
          x |> then(&foo(&1, closure, 42))
        end
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`foo(closure, 42)`" end)
    end

    test "fn pass-through (remote)" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> String.upcase(v) end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`String.upcase()`" end)
    end

    test "fn pass-through (local)" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> foo(v) end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`foo()`" end)
    end

    test "fn partial application" do
      """
      defmodule M do
        def go(m), do: m |> then(fn x -> Map.get(x, :key) end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`Map.get(:key)`" end)
    end

    test "variable-module partial application" do
      """
      defmodule M do
        def go(x, mod), do: x |> then(&mod.foo(&1, :extra))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`mod.foo(:extra)`" end)
    end

    test "explicit-module `Kernel.then` form" do
      """
      defmodule M do
        def go(x), do: x |> Kernel.then(&String.upcase/1)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`String.upcase()`" end)
    end
  end

  describe "flags non-piped form" do
    test "`then(x, &String.upcase/1)`" do
      """
      defmodule M do
        def go(x), do: then(x, &String.upcase/1)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`String.upcase()`" end)
    end

    test "`then(x, fn v -> Map.get(v, :key) end)`" do
      """
      defmodule M do
        def go(x), do: then(x, fn v -> Map.get(v, :key) end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`Map.get(:key)`" end)
    end

    test "explicit-module non-piped `Kernel.then(x, f)`" do
      """
      defmodule M do
        def go(x), do: Kernel.then(x, &String.upcase/1)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> assert_issue(fn issue -> assert issue.message =~ "`String.upcase()`" end)
    end
  end

  describe "does not flag" do
    test "capture with piped val not at first-arg position" do
      """
      defmodule M do
        def go(x), do: x |> then(&foo(:a, &1))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "fn with piped val not at first-arg position" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> foo(:a, v) end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "capture with `&1` used twice" do
      """
      defmodule M do
        def go(x), do: x |> then(&(&1 + &1))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "fn with arg used twice" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> v + v end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "operator body capture (`|> then(&(&1 * 2))`)" do
      """
      defmodule M do
        def go(x), do: x |> then(&(&1 * 2))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "operator body fn" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> v * 2 end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "unary operator body capture" do
      """
      defmodule M do
        def go(x), do: x |> then(&(not &1))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "multi-clause fn" do
      """
      defmodule M do
        def go(x) do
          x
          |> then(fn
            nil -> :default
            v -> v
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "pattern-matched tuple arg" do
      """
      defmodule M do
        def go(x), do: x |> then(fn {a, b} -> a + b end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "pattern-matched struct arg" do
      """
      defmodule M do
        def go(x), do: x |> then(fn %User{name: n} -> n end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "guard" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v when v > 0 -> v end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "control-flow body (`case`)" do
      """
      defmodule M do
        def go(x) do
          x
          |> then(fn v ->
            case v do
              :ok -> 1
              :error -> 0
            end
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "control-flow body (`if`)" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> if v, do: 1, else: 0 end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "pipe body" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> v |> foo() |> bar() end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "nested fn in body" do
      """
      defmodule M do
        def go(x) do
          x |> then(fn v -> Enum.map(v, fn i -> i end) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "nested capture in body" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> Enum.map(v, &foo/1) end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "underscored/unused arg" do
      """
      defmodule M do
        def go(x), do: x |> then(fn _ -> :ok end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "bare variable function reference" do
      """
      defmodule M do
        def go(x, fun), do: x |> then(fun)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "multi-arg fn (defensive — wouldn't compile with `then/2`)" do
      """
      defmodule M do
        def go(x) do
          x |> then(fn a, b -> a + b end)
        end
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "zero-arity fn (defensive)" do
      """
      defmodule M do
        def go(x), do: x |> then(fn -> :ok end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "arity > 1 capture (defensive)" do
      """
      defmodule M do
        def go(x), do: x |> then(&foo/2)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "capture with higher-index `&N` reference (defensive)" do
      """
      defmodule M do
        def go(x), do: x |> then(&foo(&1, &2))
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end

    test "identity `fn v -> v end` (body not a call)" do
      """
      defmodule M do
        def go(x), do: x |> then(fn v -> v end)
      end
      """
      |> to_source_file()
      |> run_check(RedundantThen)
      |> refute_issues()
    end
  end
end
