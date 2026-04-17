defmodule Rbtz.CredoChecks.Warning.EnumEachInHeexTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.EnumEachInHeex

  test "exposes metadata from `use Credo.Check`" do
    assert EnumEachInHeex.id() |> is_binary()
    assert EnumEachInHeex.category() |> is_atom()
    assert EnumEachInHeex.base_priority() |> is_atom()
    assert EnumEachInHeex.explanation() |> is_binary()
    assert EnumEachInHeex.params_defaults() |> is_list()
    assert EnumEachInHeex.params_names() |> is_list()
  end

  test "flags `<% Enum.each %>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <% Enum.each(@items, fn item -> %>
          <li>{item.name}</li>
        <% end) %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(EnumEachInHeex)
    |> assert_issue()
  end

  test "does not flag `<%= for %>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <li>{item.name}</li>
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(EnumEachInHeex)
    |> refute_issues()
  end

  test "does not flag `:for=` attribute" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <li :for={item <- @items}>{item.name}</li>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(EnumEachInHeex)
    |> refute_issues()
  end
end
