defmodule Rbtz.CredoChecks.Readability.FunctionSpacingTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.FunctionSpacing

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert FunctionSpacing.run(src, []) == []
  end

  test "returns no issues for a module form without a do body" do
    src = Credo.SourceFile.parse("defmodule Foo", "lib/foo.ex")
    assert FunctionSpacing.run(src, []) == []
  end

  test "exposes metadata from `use Credo.Check`" do
    assert FunctionSpacing.id() |> is_binary()
    assert FunctionSpacing.category() == :readability
    assert FunctionSpacing.base_priority() |> is_atom()
    assert FunctionSpacing.explanations()[:check] |> is_binary()
    assert FunctionSpacing.param_defaults() |> is_list()
    assert FunctionSpacing.param_names() |> is_list()
  end

  describe "blank line above header block" do
    test "flags a header flush against the previous statement" do
      """
      defmodule M do
        def one, do: :ok
        @spec two() :: :ok
        def two, do: :ok
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issue(fn issue ->
        assert issue.trigger == "@spec"
        assert issue.message =~ "blank line above"
        assert issue.line_no == 3
      end)
    end

    test "flags the first line of a stacked header (attrs, dialyzer, comments)" do
      """
      defmodule M do
        def one, do: :ok
        # Public API
        @dialyzer {:nowarn_function, two: 0}
        @impl true
        @spec two() :: :ok
        def two, do: :ok
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issue(fn issue ->
        assert issue.trigger == "#"
        assert issue.line_no == 3
      end)
    end

    test "flags every offending header block, including in nested modules" do
      """
      defmodule Outer do
        def one, do: :ok
        @spec two() :: :ok
        def two, do: :ok

        defmodule Inner do
          def three, do: :ok
          @doc "four"
          def four, do: :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end

    test "flags headers inside defimpl that lack a blank above" do
      """
      defimpl Enumerable, for: List do
        def count(list), do: length(list)
        @doc "Member?"
        def member?(list, value), do: value in list
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issue(fn issue ->
        assert issue.trigger == "@doc"
        assert issue.message =~ "blank line above"
        assert issue.line_no == 3
      end)
    end

    test "does not flag module-leading, blank-separated, or non-function headers" do
      """
      defmodule Orphan do
        @spec one() :: :ok
      end

      defprotocol P do
        @doc "Callback."
        def one(x)
      end

      defimpl Enumerable, for: List do
        @doc "Count."
        def count(list), do: length(list)
      end

      defmodule M do
        # Entry point
        @impl true
        @spec one() :: :ok
        def one, do: :ok

        def two, do: :ok

        # Public API
        @doc \"\"\"
        Returns :ok.
        \"\"\"
        @spec three() :: :ok
        def three, do: :ok

        @doc "Types live below."
        @type t :: atom()
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> refute_issues()
    end
  end

  describe "header flush and multi-clause density" do
    test "flags a blank line between the header and the first clause" do
      """
      defmodule M do
        @spec one() :: :ok

        def one, do: :ok

        @spec two(atom()) :: atom()

        def two(x) when is_atom(x), do: x

        def two(x) when is_integer(x) do
          x
        end
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issues(fn issues ->
        assert length(issues) == 2
        assert Enum.all?(issues, &(&1.message =~ "no blank line between the function header"))
      end)
    end

    test "flags single-line groups that are not fully compact" do
      """
      defmodule M do
        @spec one(atom()) :: atom()
        def one(x) when is_atom(x), do: x

        def one(x) when is_integer(x), do: x

        def three(x) when is_atom(x), do: x

        def three(x) when is_integer(x), do: x

        @doc false
        defp four(x) when is_atom(x), do: x

        defp four(x) when is_integer(x), do: x

        @spec five(atom()) :: Macro.t()
        defmacro five(x) when is_atom(x), do: x

        defmacro five(x) when is_integer(x), do: x
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issues(fn issues ->
        assert length(issues) == 4
        assert Enum.all?(issues, &(&1.message =~ "all single-line"))
        triggers = issues |> Enum.map(& &1.trigger) |> Enum.sort()
        assert triggers == ["def", "def", "defmacro", "defp"]
      end)
    end

    test "flags multi-line groups that are not fully separated" do
      """
      defmodule M do
        @spec one(atom()) :: atom()
        def one(x) when is_atom(x), do: x
        def one(x) when is_integer(x) do
          x
        end

        def three(x) when is_atom(x), do: x
        def three(x) when is_integer(x) do
          x
        end
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issues(fn issues ->
        assert length(issues) == 2
        assert Enum.all?(issues, &(&1.message =~ "multi-line clause"))
        assert Enum.all?(issues, &(&1.message =~ "between every pair of clauses"))
      end)
    end

    test "flags non-compact multi-clause groups inside defimpl" do
      """
      defimpl Enumerable, for: List do
        def count(list) when is_list(list), do: length(list)

        def count(_), do: {:error, __MODULE__}
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> assert_issue(fn issue ->
        assert issue.trigger == "def"
        assert issue.message =~ "all single-line"
        assert issue.line_no == 2
      end)
    end

    test "does not flag correct compact and separated groups" do
      """
      defmodule M do
        @spec foo(atom()) :: atom()
        @spec foo(integer()) :: integer()
        # Compact single-line group.
        def foo(x) when is_atom(x), do: x
        def foo(x) when is_integer(x), do: x

        @spec bar(atom()) :: atom()
        def bar(x) when is_atom(x), do: x

        def bar(x) when is_integer(x) do
          x
        end

        def baz(x) when is_atom(x), do: x
        def baz(x) when is_integer(x), do: x

        def qux(x) when is_atom(x), do: x

        def qux(x) when is_integer(x) do
          x
        end

        @spec one() :: :ok
        def one, do: :ok

        @spec three(atom()) :: atom()
        def three(x), do: x

        def three(x, y), do: {x, y}
      end
      """
      |> to_source_file()
      |> run_check(FunctionSpacing)
      |> refute_issues()
    end
  end
end
