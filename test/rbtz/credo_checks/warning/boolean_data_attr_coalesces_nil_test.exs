defmodule Rbtz.CredoChecks.Warning.BooleanDataAttrCoalescesNilTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.BooleanDataAttrCoalescesNil

  test "exposes metadata from `use Credo.Check`" do
    assert BooleanDataAttrCoalescesNil.id() |> is_binary()
    assert BooleanDataAttrCoalescesNil.category() |> is_atom()
    assert BooleanDataAttrCoalescesNil.base_priority() |> is_atom()
    assert BooleanDataAttrCoalescesNil.explanation() |> is_binary()
    assert BooleanDataAttrCoalescesNil.params_defaults() |> is_list()
    assert BooleanDataAttrCoalescesNil.params_names() |> is_list()
  end

  test "flags bare `@assign`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-disabled={@disabled}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> assert_issue()
  end

  test "flags bare variable" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-open={open?}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> assert_issue()
  end

  test "does not flag `expr || nil`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-disabled={@disabled || nil}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> refute_issues()
  end

  test ~s(does not flag `expr && "true"`) do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-open={@open && "true"}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> refute_issues()
  end

  test "does not flag non-boolean data attributes" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-user-id={@id}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> refute_issues()
  end

  test "flags only configured names via :names param" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-custom={@custom}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil, names: ["custom"])
    |> assert_issue()
  end

  test "does not flag function-call expressions like `to_string(@checked)`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-checked={to_string(@checked)}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> refute_issues()
  end

  test "does not flag multi-arg function calls like `encode_selected(@mode, @selected)`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-selected={encode_selected(@mode, @selected)}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> refute_issues()
  end

  test "does not flag string literal values" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-open="true">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BooleanDataAttrCoalescesNil)
    |> refute_issues()
  end
end
