defmodule Rbtz.CredoChecks.Design.PreferLogsterInLibTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.PreferLogsterInLib

  test "exposes metadata from `use Credo.Check`" do
    assert PreferLogsterInLib.id() |> is_binary()
    assert PreferLogsterInLib.category() |> is_atom()
    assert PreferLogsterInLib.base_priority() |> is_atom()
    assert PreferLogsterInLib.explanation() |> is_binary()
    assert PreferLogsterInLib.params_defaults() |> is_list()
    assert PreferLogsterInLib.params_names() |> is_list()
  end

  test "flags `Logger.info` in lib/" do
    """
    defmodule M do
      require Logger

      def go, do: Logger.info("hi")
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(PreferLogsterInLib)
    |> assert_issues()
  end

  test "flags `require Logger` in lib/" do
    """
    defmodule M do
      require Logger
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(PreferLogsterInLib)
    |> assert_issue()
  end

  test "flags `import Logger` in lib/" do
    """
    defmodule M do
      import Logger
      def go, do: info("hi")
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(PreferLogsterInLib)
    |> assert_issue()
  end

  test "does not flag `Logger.*` in test files" do
    """
    defmodule MTest do
      require Logger

      def go, do: Logger.info("hi")
    end
    """
    |> to_source_file("test/m_test.exs")
    |> run_check(PreferLogsterInLib)
    |> refute_issues()
  end

  test "flags every `Logger` log-level fn in lib/" do
    for level <- ~w(debug info notice warning warn error critical alert emergency log) do
      """
      defmodule M do
        require Logger
        def go, do: Logger.#{level}("hi")
      end
      """
      |> to_source_file("lib/m.ex")
      |> run_check(PreferLogsterInLib)
      |> assert_issues()
    end
  end

  test "does not flag non-log `Logger` fns in lib/" do
    """
    defmodule M do
      def go(metadata) do
        Logger.metadata(metadata)
        Logger.configure(level: :info)
        Logger.delete_process_level()
        _ = Logger.get_process_level(self())
      end
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(PreferLogsterInLib)
    |> refute_issues()
  end

  test "does not flag Logster usage" do
    """
    defmodule M do
      def go, do: Logster.info("hi")
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(PreferLogsterInLib)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert PreferLogsterInLib.run(src, []) == []
  end
end
