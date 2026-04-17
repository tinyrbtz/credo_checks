defmodule Rbtz.CredoChecks.Readability.SnakeCaseVariableNumberingTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering

  test "exposes metadata from `use Credo.Check`" do
    assert SnakeCaseVariableNumbering.id() |> is_binary()
    assert SnakeCaseVariableNumbering.category() |> is_atom()
    assert SnakeCaseVariableNumbering.base_priority() |> is_atom()
    assert SnakeCaseVariableNumbering.explanation() |> is_binary()
    assert SnakeCaseVariableNumbering.params_defaults() |> is_list()
    assert SnakeCaseVariableNumbering.params_names() |> is_list()
  end

  test "flags `user1`, `user2`" do
    """
    defmodule MyTest do
      def test do
        user1 = %{name: "alice"}
        user2 = %{name: "bob"}
        {user1, user2}
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering)
    |> assert_issues(2)
  end

  test "does not flag single-letter names like `a1`, `x2`" do
    """
    defmodule MyTest do
      def test do
        a1 = %{}
        x2 = %{}
        {a1, x2}
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering)
    |> refute_issues()
  end

  test "ignores leading underscores when counting letters (`_a2` ok, `_ab2` flagged)" do
    """
    defmodule MyTest do
      def test do
        _a2 = %{}
        _ab2 = %{}
        {_a2, _ab2}
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering)
    |> assert_issue(&(&1.trigger == "_ab2"))
  end

  test "does not flag `user_1`, `user_2`" do
    """
    defmodule MyTest do
      def test do
        user_1 = %{name: "alice"}
        user_2 = %{name: "bob"}
        {user_1, user_2}
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering)
    |> refute_issues()
  end

  test "deduplicates by variable name" do
    """
    defmodule MyTest do
      def test do
        user1 = %{name: "alice"}
        # mention user1 again in the body
        IO.inspect(user1)
        IO.inspect(user1)
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering)
    |> assert_issue()
  end

  test "does not flag function calls" do
    """
    defmodule M do
      def go, do: foo() + bar()
      defp foo, do: 1
      defp bar, do: 2
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering)
    |> refute_issues()
  end

  test "does not flag names whose components match `:exclude`" do
    """
    defmodule M do
      def go do
        md5 = "a"
        md5_hash = "b"
        file_md5 = "c"
        content_md5_digest = "d"
        {md5, md5_hash, file_md5, content_md5_digest}
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering, exclude: ["md5"])
    |> refute_issues()
  end

  test "still flags when excluded pattern is only a substring of a component" do
    """
    defmodule M do
      def go do
        username1 = "a"
        username1
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering, exclude: ["name"])
    |> assert_issue()
  end

  test "accepts atoms in `:exclude`" do
    """
    defmodule M do
      def go do
        user_md5 = "a"
        user_md5
      end
    end
    """
    |> to_source_file()
    |> run_check(SnakeCaseVariableNumbering, exclude: [:md5])
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert SnakeCaseVariableNumbering.run(src, []) == []
  end
end
