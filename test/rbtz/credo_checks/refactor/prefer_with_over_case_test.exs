defmodule Rbtz.CredoChecks.Refactor.PreferWithOverCaseTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.PreferWithOverCase

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PreferWithOverCase.run(src, []) == []
  end

  test "exposes metadata from `use Credo.Check`" do
    assert PreferWithOverCase.id() |> is_binary()
    assert PreferWithOverCase.category() |> is_atom()
    assert PreferWithOverCase.base_priority() |> is_atom()
    assert PreferWithOverCase.explanations()[:check] |> is_binary()
    assert PreferWithOverCase.param_defaults() |> is_list()
    assert PreferWithOverCase.param_names() |> is_list()
  end

  describe "flags" do
    test "specific pass-through clause (`{:error, reason} -> {:error, reason}`)" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:ok, contents} -> {:ok, String.trim(contents)}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> assert_issue(fn issue -> assert issue.trigger == "case" end)
    end

    test "bare `:error` atom pass-through (`:error -> :error`)" do
      """
      defmodule M do
        def go(map) do
          case Map.fetch(map, :count) do
            {:ok, count} -> {:ok, count + 1}
            :error -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> assert_issue(fn issue -> assert issue.message =~ "`with`" end)
    end

    test "pass-through clause listed first" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:error, reason} -> {:error, reason}
            {:ok, contents} -> String.trim(contents)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> assert_issue()
    end
  end

  describe "does not flag" do
    test "bare-variable default fall-through (not an error shape)" do
      """
      defmodule M do
        def go(cache, key) do
          case Map.get(cache, key) do
            nil -> %{}
            cached -> cached
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "bare-variable pass-through with specific happy path (`other -> other`)" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:ok, contents} -> String.upcase(contents)
            other -> other
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "both clauses do real work" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:ok, contents} -> {:ok, String.trim(contents)}
            {:error, reason} -> {:error, {:read_failed, reason}}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "three clauses" do
      """
      defmodule M do
        def go(value) do
          case Integer.parse(value) do
            {0, _rest} -> :zero
            {int, _rest} -> {:ok, int}
            :error -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "single clause" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:ok, contents} -> contents
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "guard on the error pass-through clause" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:ok, contents} -> contents
            {:error, reason} when is_atom(reason) -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "catch-all happy path with a specific pass-through (order-sensitive)" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:error, reason} -> {:error, reason}
            other -> String.upcase(other)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end

    test "both clauses are identical pass-through clauses" do
      """
      defmodule M do
        def go(path) do
          case File.read(path) do
            {:ok, contents} -> {:ok, contents}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PreferWithOverCase)
      |> refute_issues()
    end
  end
end
