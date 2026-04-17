defmodule Rbtz.CredoChecks.Warning.PhxClickAwayWithoutIdTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.PhxClickAwayWithoutId

  test "exposes metadata from `use Credo.Check`" do
    assert PhxClickAwayWithoutId.id() |> is_binary()
    assert PhxClickAwayWithoutId.category() |> is_atom()
    assert PhxClickAwayWithoutId.base_priority() |> is_atom()
    assert PhxClickAwayWithoutId.explanation() |> is_binary()
    assert PhxClickAwayWithoutId.params_defaults() |> is_list()
    assert PhxClickAwayWithoutId.params_names() |> is_list()
  end

  test "flags `<div phx-click-away=...>` without `id`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div phx-click-away="close">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxClickAwayWithoutId)
    |> assert_issue()
  end

  test "flags multi-line tag missing `id`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div
          phx-click-away="close"
          class="something"
        >
          x
        </div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxClickAwayWithoutId)
    |> assert_issue()
  end

  test "does not flag when `id` is present" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div id="menu" phx-click-away="close">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxClickAwayWithoutId)
    |> refute_issues()
  end

  test "does not flag plain elements without phx-click-away" do
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
    |> run_check(PhxClickAwayWithoutId)
    |> refute_issues()
  end
end
