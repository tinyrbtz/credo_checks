defmodule Rbtz.CredoChecks.Readability.PreferBlockFormForMultilineIfTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferBlockFormForMultilineIf

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PreferBlockFormForMultilineIf.run(src, []) == []
  end

  test "exposes metadata from `use Credo.Check`" do
    assert PreferBlockFormForMultilineIf.id() |> is_binary()
    assert PreferBlockFormForMultilineIf.category() |> is_atom()
    assert PreferBlockFormForMultilineIf.base_priority() |> is_atom()
    assert PreferBlockFormForMultilineIf.explanation() |> is_binary()
    assert PreferBlockFormForMultilineIf.params_defaults() |> is_list()
    assert PreferBlockFormForMultilineIf.params_names() |> is_list()
  end

  describe "flags multiline keyword form" do
    test "`if` with split `do:` / `else:`" do
      """
      defmodule M do
        def go(list) do
          if Enum.any?(list, &is_integer/1),
            do: List.first(list),
            else: List.last(list)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> assert_issue(fn issue ->
        assert issue.trigger == "if"
        assert issue.message =~ "block form"
      end)
    end

    test "`unless` with split `do:` / `else:`" do
      """
      defmodule M do
        def go(m) do
          unless map_size(m) == 0,
            do: Map.values(m),
            else: []
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> assert_issue(fn issue ->
        assert issue.trigger == "unless"
        assert issue.message =~ "block form"
      end)
    end

    test "`if` with `do:` only, split across cond and body" do
      """
      defmodule M do
        def go(list) do
          if Enum.any?(list, &is_integer/1),
            do: List.first(list)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> assert_issue(fn issue -> assert issue.trigger == "if" end)
    end

    test "`unless` with `do:` only, multiline" do
      """
      defmodule M do
        def go(list) do
          unless Enum.empty?(list),
            do: List.first(list)
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> assert_issue(fn issue -> assert issue.trigger == "unless" end)
    end

    test "split between `do:` value and `else:` value when value itself wraps" do
      """
      defmodule M do
        def go(list) do
          if Enum.any?(list, &is_integer/1), do:
            Enum.map(list, &(&1 * 2)), else: []
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> assert_issue(fn issue -> assert issue.trigger == "if" end)
    end

    test "multiline keyword `if` nested inside block-form `if` — only the inner is flagged" do
      """
      defmodule M do
        def go(x, list) do
          if x do
            if Enum.any?(list, &is_integer/1),
              do: List.first(list),
              else: List.last(list)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> assert_issue(fn issue ->
        assert issue.trigger == "if"
        assert issue.line_no >= 4
      end)
    end
  end

  describe "does not flag" do
    test "single-line `if cond, do: x, else: y`" do
      """
      defmodule M do
        def go(list), do: if(Enum.any?(list), do: List.first(list), else: List.last(list))
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "single-line `if cond, do: x`" do
      """
      defmodule M do
        def go(list), do: if(Enum.any?(list), do: List.first(list))
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "single-line `unless cond, do: x`" do
      """
      defmodule M do
        def go(list), do: unless(Enum.empty?(list), do: List.first(list))
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "block-form `if cond do ... else ... end`" do
      """
      defmodule M do
        def go(list) do
          if Enum.any?(list, &is_integer/1) do
            List.first(list)
          else
            List.last(list)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "block-form `unless cond do ... end`" do
      """
      defmodule M do
        def go(list) do
          unless Enum.empty?(list) do
            List.first(list)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "block-form `if` with only literal branches" do
      """
      defmodule M do
        def go(x) do
          if x do
            true
          else
            false
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "`case` with multiline clauses" do
      """
      defmodule M do
        def go(x) do
          case x do
            :a -> 1
            :b -> 2
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "`cond` with multiline clauses" do
      """
      defmodule M do
        def go(x) do
          cond do
            x > 0 -> :pos
            x < 0 -> :neg
            true -> :zero
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "`if` call with literal-only branches (no line metadata to span)" do
      """
      defmodule M do
        def go(), do: if(true, do: 1, else: 2)
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "`if/2` called with a keyword list that has no `:do` key" do
      """
      defmodule M do
        def go(x), do: if(x, foo: :bar)
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end

    test "`if` called with a non-list second argument" do
      """
      defmodule M do
        def go(x), do: if(x, :atom)
      end
      """
      |> to_source_file()
      |> run_check(PreferBlockFormForMultilineIf)
      |> refute_issues()
    end
  end
end
