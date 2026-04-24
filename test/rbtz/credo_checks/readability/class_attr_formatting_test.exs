defmodule Rbtz.CredoChecks.Readability.ClassAttrFormattingTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.ClassAttrFormatting

  test "exposes metadata from `use Credo.Check`" do
    assert ClassAttrFormatting.id() |> is_binary()
    assert ClassAttrFormatting.category() |> is_atom()
    assert ClassAttrFormatting.base_priority() |> is_atom()
    assert ClassAttrFormatting.explanation() |> is_binary()
    assert ClassAttrFormatting.params_defaults() |> is_list()
    assert ClassAttrFormatting.params_names() |> is_list()
  end

  describe "missing brackets" do
    test "flags multi-line class with comma-separated values" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={
            "px-2 text-white",
            @some_flag && "py-5"
          }>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue()
    end

    test "flags unparenthesized `if`" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={if @cond, do: "x", else: "y"}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue()
    end

    test "does not flag a list-wrapped class" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["px-2 text-white", @some_flag && "py-5"]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "does not flag if-with-parens" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={if(@cond, do: "x", else: "y")}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    # Exercises the single-quote-opens-string branch so a comma inside a
    # charlist isn't mistaken for a top-level comma.
    test "does not flag a charlist containing a comma" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={to_string('a,b')}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end
  end

  describe "line length" do
    test "flags single-line class attr that pushes the line past the default 100 chars" do
      # The full line below is well over 100 chars.
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["px-2 text-white", "py-5 bg-blue-600", "rounded-md border border-transparent", "hover:underline"]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue()
    end

    test "does not flag a multi-line class attr when each line is within the limit" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[
            "px-2 text-white",
            "py-5 bg-blue-600",
            "rounded-md border border-transparent",
            "hover:underline"
          ]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "flags a long string literal inside a multi-line class list" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[
            "px-2 py-1 text-white bg-blue-600 rounded-md border border-transparent hover:underline focus:ring-2",
            @extra
          ]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue()
    end

    test "flags a long string literal inside a multi-line helper call wrapping a list" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={
            cn([
              "px-2 py-1 text-white bg-blue-600 rounded-md border border-transparent hover:underline focus:ring-2",
              @extra
            ])
          }>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue()
    end

    test "reports the issue on the offending inner line, not the opening `class={` line" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[
            "px-2",
            "px-2 py-1 text-white bg-blue-600 rounded-md border border-transparent hover:underline focus:ring-2",
            @extra
          ]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue(fn issue ->
        # The `<a class={[` opening is on a line earlier than the long string.
        # The long string sits two lines below it, so the reported line_no
        # must be strictly greater than the opening line.
        assert issue.message =~ "exceeding"
        assert issue.line_no > 4
      end)
    end

    test "does not flag a short single-line class attr" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["px-2", @cls]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "respects :max_line_length param" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={["foo bar baz qux"]}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting, max_line_length: 30)
      |> assert_issue()
    end

    test "flags long literal-string class attribute" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class="px-2 text-white py-5 bg-blue-600 rounded-md border border-transparent hover:underline focus:ring-2">x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> assert_issue()
    end

    test "does not flag short literal-string class attribute" do
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
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end
  end

  describe "untouched cases" do
    test "single binding class is fine" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={@cls}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "cn() call wrapping a list is fine when short" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={cn(["px-2", @class])}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "string containing a comma does not count as a top-level comma" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={"hello, world"}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "string with escaped quote does not terminate the capture early" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={"foo \"bar"}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "nested braces inside class={...} are tracked through brace depth" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={Map.get(%{a: "x", b: "y"}, :a)}>x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "unterminated class={... is silently dropped (no crash)" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class={[
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test ~s(unterminated literal class=" string is silently dropped) do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class="never-closed
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end

    test "literal class with escaped quote does not terminate early" do
      ~S'''
      defmodule MyLive do
        def render(assigns) do
          ~H"""
          <a class="foo \" bar">x</a>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(ClassAttrFormatting)
      |> refute_issues()
    end
  end
end
