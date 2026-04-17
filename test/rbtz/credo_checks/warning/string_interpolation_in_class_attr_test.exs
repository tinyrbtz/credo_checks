defmodule Rbtz.CredoChecks.Warning.StringInterpolationInClassAttrTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.StringInterpolationInClassAttr

  test "exposes metadata from `use Credo.Check`" do
    assert StringInterpolationInClassAttr.id() |> is_binary()
    assert StringInterpolationInClassAttr.category() |> is_atom()
    assert StringInterpolationInClassAttr.base_priority() |> is_atom()
    assert StringInterpolationInClassAttr.explanation() |> is_binary()
    assert StringInterpolationInClassAttr.params_defaults() |> is_list()
    assert StringInterpolationInClassAttr.params_names() |> is_list()
  end

  test ~S(flags `class={"btn-#{@variant}"}`) do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <button class={"btn-#{@variant}"}>Save</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> assert_issue()
  end

  test ~S(flags `class="px-#{@size}"`) do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class="px-#{@size}">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> assert_issue()
  end

  test "does not flag list-syntax classes" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <button class={["btn", @variants[@variant]]}>Save</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> refute_issues()
  end

  test "does not flag literal class string" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class="px-4 py-2">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> refute_issues()
  end

  test ~S|flags interpolation whose body contains nested braces| do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <button class={"btn-#{Map.get(%{a: 1}, :a)}"}>Save</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> assert_issue()
  end

  test ~S(does not flag when the `#` is escaped) do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class="\#{literal}">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> refute_issues()
  end

  test "ignores unterminated attributes" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class={"unterminated
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> refute_issues()
  end

  test "does not flag interpolation in non-class attributes" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.link patch={"/#{@team.slug}/members"} class="text-brand-500">Members</.link>
        <a href={"mailto:#{@email}"} class="underline">Email</a>
        <div data-id={"row-#{@id}"} class="px-4">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(StringInterpolationInClassAttr)
    |> refute_issues()
  end
end
