defmodule Rbtz.CredoChecks.Warning.SetMimicGlobalTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.SetMimicGlobal

  test "exposes metadata from `use Credo.Check`" do
    assert SetMimicGlobal.id() |> is_binary()
    assert SetMimicGlobal.category() |> is_atom()
    assert SetMimicGlobal.base_priority() |> is_atom()
    assert SetMimicGlobal.explanation() |> is_binary()
    assert SetMimicGlobal.params_defaults() |> is_list()
    assert SetMimicGlobal.params_names() |> is_list()
  end

  test "flags `setup :set_mimic_global`" do
    """
    defmodule MyTest do
      use ExUnit.Case
      use Mimic

      setup :set_mimic_global

      test "x", do: :ok
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(SetMimicGlobal)
    |> assert_issue()
  end

  test "flags `setup_all :set_mimic_global`" do
    """
    defmodule MyTest do
      use ExUnit.Case
      use Mimic

      setup_all :set_mimic_global

      test "x", do: :ok
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(SetMimicGlobal)
    |> assert_issue()
  end

  test "does not flag `setup :verify_on_exit!`" do
    """
    defmodule MyTest do
      use ExUnit.Case
      use Mimic

      setup :verify_on_exit!

      test "x", do: :ok
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(SetMimicGlobal)
    |> refute_issues()
  end

  test "flags `setup set_mimic_global()` (function-call form)" do
    """
    defmodule MyTest do
      use ExUnit.Case
      use Mimic

      setup set_mimic_global()

      test "x", do: :ok
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(SetMimicGlobal)
    |> assert_issue()
  end

  test "does not flag in non-test files" do
    """
    defmodule M do
      def setup_things, do: :set_mimic_global
    end
    """
    |> to_source_file("lib/my_app.ex")
    |> run_check(SetMimicGlobal)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert SetMimicGlobal.run(src, []) == []
  end
end
