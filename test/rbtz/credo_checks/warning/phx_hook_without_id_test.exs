defmodule Rbtz.CredoChecks.Warning.PhxHookWithoutIdTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.PhxHookWithoutId

  test "exposes metadata from `use Credo.Check`" do
    assert PhxHookWithoutId.id() |> is_binary()
    assert PhxHookWithoutId.category() |> is_atom()
    assert PhxHookWithoutId.base_priority() |> is_atom()
    assert PhxHookWithoutId.explanation() |> is_binary()
    assert PhxHookWithoutId.params_defaults() |> is_list()
    assert PhxHookWithoutId.params_names() |> is_list()
  end

  test "flags `<div phx-hook=...>` without `id`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookWithoutId)
    |> assert_issue()
  end

  test "flags multi-line tag missing `id`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div
          phx-hook=".PhoneNumber"
          class="something"
        >
          x
        </div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookWithoutId)
    |> assert_issue()
  end

  test "does not flag when `id` is present" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div id="phone" phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookWithoutId)
    |> refute_issues()
  end

  test "does not flag plain elements without phx-hook" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div>plain</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookWithoutId)
    |> refute_issues()
  end

  test "flags tag with only a hyphenated `*-id` attribute (not a real `id`)" do
    # Previously the id-detection regex matched on `\bid=`, which a
    # hyphenated attribute like `data-id=` satisfied and silently bypassed
    # the check. The attribute must be a standalone `id`, not a suffix.
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-id="x" phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookWithoutId)
    |> assert_issue()
  end
end
