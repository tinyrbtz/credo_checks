defmodule Rbtz.CredoChecks.Readability.TopLevelAliasImportRequireTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.TopLevelAliasImportRequire

  test "exposes metadata from `use Credo.Check`" do
    assert TopLevelAliasImportRequire.id() |> is_binary()
    assert TopLevelAliasImportRequire.category() |> is_atom()
    assert TopLevelAliasImportRequire.base_priority() |> is_atom()
    assert TopLevelAliasImportRequire.explanation() |> is_binary()
    assert TopLevelAliasImportRequire.params_defaults() |> is_list()
    assert TopLevelAliasImportRequire.params_names() |> is_list()
  end

  test "flags `import` inside a function body" do
    """
    defmodule MyModule do
      def query do
        import Ecto.Query

        from u in User
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> assert_issue()
  end

  test "flags `alias` inside a private function" do
    """
    defmodule MyModule do
      defp call do
        alias Foo.Bar

        Bar.baz()
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> assert_issue()
  end

  test "flags `require` inside a test block" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "something" do
        require Logger

        Logger.info("hi")
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> assert_issue()
  end

  test "flags inside `setup`" do
    """
    defmodule MyTest do
      setup do
        alias Foo.Bar
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> assert_issue()
  end

  test "does not flag top-level alias/import/require" do
    """
    defmodule MyModule do
      alias Foo.Bar
      import Ecto.Query
      require Logger

      def go, do: Bar.baz()
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end

  test "does not flag inside `quote` blocks" do
    """
    defmodule MyMacro do
      defmacro __using__(_) do
        quote do
          alias Foo.Bar
          import Ecto.Query
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end

  test "ignores `setup :atom_name` shorthand (no do block)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup :set_things_up
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end

  test "does not walk into nested defmodule blocks" do
    """
    defmodule Outer do
      def helper do
        defmodule Inner do
          alias Foo.Bar
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end

  test "flags multiple violations across one module" do
    """
    defmodule MyModule do
      def a do
        alias Foo.Bar
        Bar.x()
      end

      def b do
        import Foo
        x()
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> assert_issues(2)
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert TopLevelAliasImportRequire.run(src, []) == []
  end
end
