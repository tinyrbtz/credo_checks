defmodule Rbtz.CredoChecks.Readability.RedundantClassAttrWrappingTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.RedundantClassAttrWrapping

  test "exposes metadata from `use Credo.Check`" do
    assert RedundantClassAttrWrapping.id() |> is_binary()
    assert RedundantClassAttrWrapping.category() |> is_atom()
    assert RedundantClassAttrWrapping.base_priority() |> is_atom()
    assert RedundantClassAttrWrapping.explanation() |> is_binary()
    assert RedundantClassAttrWrapping.params_defaults() |> is_list()
    assert RedundantClassAttrWrapping.params_names() |> is_list()
  end

  describe "bare static string" do
    test ~s(flags `class={"foo bar"}`) do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={"px-2 text-white"}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "does not flag a string that contains `\#{...}` interpolation" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={"px-2 text-#{@tone}"}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test ~s(does not flag a plain literal `class="..."`) do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class="px-2 text-white">x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "does not flag a string that contains an escaped `\\\\\#{` sequence" do
      # `"foo \#{bar}"` is a literal `#{` — not an interpolation.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={"px-2 bar"}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end
  end

  describe "single-element list with a static string" do
    test ~s(flags `class={["foo bar"]}`) do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["px-2 text-white"]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "flags a multi-line single-string list" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[
            "px-2 text-white"
          ]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "flags a list with whitespace padding inside the brackets" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[ "px-2 text-white" ]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "does not flag a list with multiple static strings" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["px-2 text-white", "rounded-md border"]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "flags a single-element list where the string has `\#{...}` interpolation" do
      # Here the rewrite drops only the list: `class={"px-2 text-#{@tone}"}`.
      # The string keeps its interp braces because it contains a `#{...}`.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["px-2 text-#{@tone}"]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test ~S(flags a single-string list whose string contains an escaped `\"`) do
      # Exercises the escape-inside-string branch of the top-level-comma scanner.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["foo \"bar\""]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end
  end

  describe "single-element list with an expression" do
    test "flags `class={[@cls]}`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[@cls]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "flags `class={[classes_for(@size)]}`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[classes_for(@size)]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "flags a single-element list wrapping an `if` expression" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[if(@cond, do: "px-2", else: "px-4")]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "does not flag a multi-element expression list" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[@a, @b]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "flags a single-element list wrapping a charlist argument" do
      # Exercises the `?'` (charlist) branch of the top-level-comma scanner —
      # the `,` inside `'a,b'` must not be mistaken for a list separator.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[to_string('a,b')]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "flags a single-element list wrapping a map literal" do
      # Exercises the `?{` / `?}` brace-depth tracking in the top-level-comma
      # scanner — the `,` inside `%{a: 1, b: 2}` is at brace depth 1.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[Map.get(%{a: 1, b: 2}, :a)]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end

    test "flags a single-element list wrapping a nested list literal" do
      # Exercises the nested `?[` / `?]` depth tracking — the `,` inside the
      # inner `[@a, @b]` is at bracket depth 1, not a top-level separator.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[[@a, @b]]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue()
    end
  end

  describe "skipped shapes" do
    test "does not flag an empty `class={}`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "does not flag `class={[]}`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test ~s(does not flag `class={""}`) do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={""}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "does not flag `class={nil}`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={nil}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "does not flag a charlist `class={'foo'}`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={'foo'}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test ~S|does not flag `class={cn(["foo"])}` (function call, not a direct list/string)| do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={cn(["px-2 text-white"])}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end

    test "does not flag unterminated `class={`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> refute_issues()
    end
  end

  describe "line reporting" do
    test "reports on the line containing `class={`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <div>
            <a class={["px-2 text-white"]}>x</a>
          </div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(RedundantClassAttrWrapping)
      |> assert_issue(fn issue ->
        assert issue.trigger == "class={"
        assert is_integer(issue.line_no)
      end)
    end
  end
end
