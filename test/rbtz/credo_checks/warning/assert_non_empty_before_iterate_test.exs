defmodule Rbtz.CredoChecks.Warning.AssertNonEmptyBeforeIterateTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.AssertNonEmptyBeforeIterate

  test "exposes metadata from `use Credo.Check`" do
    assert AssertNonEmptyBeforeIterate.id() |> is_binary()
    assert AssertNonEmptyBeforeIterate.category() |> is_atom()
    assert AssertNonEmptyBeforeIterate.base_priority() |> is_atom()
    assert AssertNonEmptyBeforeIterate.explanation() |> is_binary()
    assert AssertNonEmptyBeforeIterate.params_defaults() |> is_list()
    assert AssertNonEmptyBeforeIterate.params_names() |> is_list()
  end

  test "flags Enum.each with assert and no prior guard" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        Enum.each(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> assert_issue()
  end

  test "flags piped Enum.each with assert and no prior guard" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        users |> Enum.each(fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> assert_issue()
  end

  test "does not flag when refute Enum.empty? precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        refute Enum.empty?(users)
        users |> Enum.each(fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when piped `refute x |> Enum.empty?()` precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        links = fetch()
        refute links |> Enum.empty?()

        links
        |> Enum.each(fn link ->
          assert link.href
        end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when piped `assert x |> Enum.empty?() == false` precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        links = fetch()
        assert links |> Enum.empty?() == false

        links |> Enum.each(fn link -> assert link.href end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when assert != [] precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        assert users != []
        Enum.each(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when assert length > 0 precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        assert length(users) > 0
        Enum.each(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when piped `assert x |> length() >= n` precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        figures = fetch()
        assert figures |> length() >= 3

        figures
        |> Enum.each(fn figure ->
          assert figure.src
        end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when `refute x == []` precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        refute users == []

        Enum.each(users, fn u -> assert u.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when `assert Enum.empty?(x) == false` precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        assert Enum.empty?(users) == false

        Enum.each(users, fn u -> assert u.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when `assert length(x) >= n` (direct form) precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        assert length(users) >= 1

        Enum.each(users, fn u -> assert u.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when piped `assert x |> length() > n` precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        assert users |> length() > 0

        users |> Enum.each(fn u -> assert u.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when `assert length(x) > n` (n > 0) precedes" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        figures = fetch()
        assert length(figures) > 2

        Enum.each(figures, fn f -> assert f.src end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag when iteration has no assert" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        Enum.each(users, fn user -> IO.inspect(user) end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "flags Enum.map with assert inside" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        Enum.map(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> assert_issue()
  end

  test "guard in one test does not leak into another" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "guarded" do
        users = fetch()
        refute Enum.empty?(users)
        Enum.each(users, fn user -> assert user.id end)
      end

      test "unguarded" do
        users = fetch()
        Enum.each(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> assert_issue()
  end

  test "does not run on non-test files" do
    """
    defmodule M do
      def go do
        users = fetch()
        Enum.each(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not crash on `test` call without a do block" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "placeholder"
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "handles a test body with a single (non-block) statement" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        assert true
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag Enum.each with a captured function (not a fn literal)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        Enum.each(users, &IO.inspect/1)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "does not flag piped Enum.each with a captured function" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        users |> Enum.each(&IO.inspect/1)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> refute_issues()
  end

  test "re-flags iteration when the variable is rebound after a guard" do
    """
    defmodule MyTest do
      use ExUnit.Case

      test "it" do
        users = fetch()
        refute Enum.empty?(users)

        users = filter(users)

        Enum.each(users, fn user -> assert user.id end)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AssertNonEmptyBeforeIterate)
    |> assert_issue()
  end
end
