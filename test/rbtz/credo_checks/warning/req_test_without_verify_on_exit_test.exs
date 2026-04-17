defmodule Rbtz.CredoChecks.Warning.ReqTestWithoutVerifyOnExitTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.ReqTestWithoutVerifyOnExit

  test "exposes metadata from `use Credo.Check`" do
    assert ReqTestWithoutVerifyOnExit.id() |> is_binary()
    assert ReqTestWithoutVerifyOnExit.category() |> is_atom()
    assert ReqTestWithoutVerifyOnExit.base_priority() |> is_atom()
    assert ReqTestWithoutVerifyOnExit.explanation() |> is_binary()
    assert ReqTestWithoutVerifyOnExit.params_defaults() |> is_list()
    assert ReqTestWithoutVerifyOnExit.params_names() |> is_list()
  end

  test "flags Req.Test.expect without verify_on_exit!" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> assert_issue()
  end

  test "flags Req.Test.stub without verify_on_exit!" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      test "it" do
        Req.Test.stub(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> assert_issue()
  end

  test "does not flag when setup :verify_on_exit! is present" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      setup :verify_on_exit!

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not flag when setup do ... end calls verify_on_exit!" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      setup do
        Req.Test.verify_on_exit!()
        :ok
      end

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not flag when setup has bare verify_on_exit!()" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true
      import Req.Test

      setup do
        verify_on_exit!()
        :ok
      end

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not flag when module has no Req.Test usage" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      test "it", do: :ok
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not run on non-test files" do
    """
    defmodule M do
      def run do
        Req.Test.stub(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not flag when setup receives a list containing :verify_on_exit!" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      setup [:some_other, :verify_on_exit!]

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not flag when setup receives a bare `verify_on_exit!` identifier" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      setup verify_on_exit!

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "does not crash on `setup` referenced as a capture (e.g. `&setup/0`)" do
    # `&setup/0` must appear before the real `setup :verify_on_exit!` in
    # source order so the walker visits it before short-circuiting.
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      def hook, do: &setup/0

      setup :verify_on_exit!

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> refute_issues()
  end

  test "flags when setup receives a non-recognized argument (e.g. integer)" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      setup 42

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> assert_issue()
  end

  test "flags when verify_on_exit! is called top-level (not inside setup)" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      Req.Test.verify_on_exit!()

      test "it" do
        Req.Test.expect(MyApp.HTTP, fn conn -> conn end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(ReqTestWithoutVerifyOnExit)
    |> assert_issue()
  end
end
