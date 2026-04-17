defmodule Rbtz.CredoChecks.Readability.ShorthandDefMustBeCompactTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.ShorthandDefMustBeCompact

  test "exposes metadata from `use Credo.Check`" do
    assert ShorthandDefMustBeCompact.id() |> is_binary()
    assert ShorthandDefMustBeCompact.category() |> is_atom()
    assert ShorthandDefMustBeCompact.base_priority() |> is_atom()
    assert ShorthandDefMustBeCompact.explanation() |> is_binary()
    assert ShorthandDefMustBeCompact.params_defaults() |> is_list()
    assert ShorthandDefMustBeCompact.params_names() |> is_list()
  end

  test "does not flag a one-line shorthand def" do
    """
    defmodule MyModule do
      def foo(x), do: x + 1
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "does not flag a two-line shorthand def" do
    """
    defmodule MyModule do
      def foo(x),
        do: x + 1
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "flags the canonical broken-up shorthand from the user's example" do
    """
    defmodule MyModule do
      def something(x),
        do:
          one_very_long_method_call(x) || one_very_long_method_call(x) ||
            one_very_long_method_call(x)
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> assert_issue()
  end

  test "flags shorthand whose body wraps onto more than one line" do
    """
    defmodule MyModule do
      def foo(x),
        do:
          x +
            x
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> assert_issue()
  end

  test "does not flag shorthand with a multi-line head when body is single-line" do
    """
    defmodule MyModule do
      def foo(
        x,
        y
      ), do: x + y
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "does not flag shorthand with a nested-pattern head when body is single-line" do
    """
    defmodule MyModule do
      defp put_id(map, %{
             outer: %{inner: %{id: id}}
           }),
           do: Map.put(map, :id, id)
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "does not flag shorthand when only the `do:` wraps onto its own line" do
    """
    defmodule MyModule do
      def foo(x),
        do:
          x + 1
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "does not flag shorthand with a bare-literal body (no line metadata)" do
    """
    defmodule MyModule do
      def foo, do: 42
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "does not flag block form even when it spans many lines" do
    """
    defmodule MyModule do
      def foo(x) do
        a = x + 1
        b = a + 2
        c = b + 3
        c * 4
      end
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> refute_issues()
  end

  test "handles guarded shorthand whose body wraps" do
    """
    defmodule MyModule do
      def foo(x) when is_integer(x),
        do:
          x + 1 +
            x + 1
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> assert_issue()
  end

  test "flags `defp` shorthand whose body spans more than one line" do
    """
    defmodule MyModule do
      defp foo(x),
        do:
          x +
            x
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> assert_issue()
  end

  test "flags `defmacro` and `defmacrop` shorthand whose bodies span more than one line" do
    """
    defmodule MyModule do
      defmacro foo(x),
        do:
          x +
            x

      defmacrop bar(x),
        do:
          x +
            x
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "flags multiple violations across one module" do
    """
    defmodule MyModule do
      def a(x),
        do:
          x +
            x

      def b(y),
        do:
          y +
            y
    end
    """
    |> to_source_file()
    |> run_check(ShorthandDefMustBeCompact)
    |> assert_issues(2)
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert ShorthandDefMustBeCompact.run(src, []) == []
  end
end
