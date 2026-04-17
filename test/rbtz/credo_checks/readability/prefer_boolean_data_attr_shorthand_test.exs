defmodule Rbtz.CredoChecks.Readability.PreferBooleanDataAttrShorthandTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferBooleanDataAttrShorthand

  test "exposes metadata from `use Credo.Check`" do
    assert PreferBooleanDataAttrShorthand.id() |> is_binary()
    assert PreferBooleanDataAttrShorthand.category() |> is_atom()
    assert PreferBooleanDataAttrShorthand.base_priority() |> is_atom()
    assert PreferBooleanDataAttrShorthand.explanation() |> is_binary()
    assert PreferBooleanDataAttrShorthand.params_defaults() |> is_list()
    assert PreferBooleanDataAttrShorthand.params_names() |> is_list()
  end

  test "flags `data-[disabled]:` in class list" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class={["data-[disabled]:opacity-50"]}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferBooleanDataAttrShorthand)
    |> assert_issue()
  end

  test "flags `data-[open]:` in plain class string" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class="data-[open]:block">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferBooleanDataAttrShorthand)
    |> assert_issue()
  end

  test "does not flag value-matching bracket form" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class={["data-[state=open]:bg-red-50"]}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferBooleanDataAttrShorthand)
    |> refute_issues()
  end

  test "does not flag shorthand boolean form" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class={["data-disabled:opacity-50"]}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferBooleanDataAttrShorthand)
    |> refute_issues()
  end

  test "flags multiple occurrences on different lines" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div class={["data-[disabled]:opacity-50"]}>
          <span class={["data-[open]:block"]}>x</span>
        </div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferBooleanDataAttrShorthand)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end
end
