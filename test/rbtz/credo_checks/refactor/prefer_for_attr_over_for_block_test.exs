defmodule Rbtz.CredoChecks.Refactor.PreferForAttrOverForBlockTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.PreferForAttrOverForBlock

  test "exposes metadata from `use Credo.Check`" do
    assert PreferForAttrOverForBlock.id() |> is_binary()
    assert PreferForAttrOverForBlock.category() |> is_atom()
    assert PreferForAttrOverForBlock.base_priority() |> is_atom()
    assert PreferForAttrOverForBlock.explanation() |> is_binary()
    assert PreferForAttrOverForBlock.params_defaults() |> is_list()
    assert PreferForAttrOverForBlock.params_names() |> is_list()
  end

  test "flags a `<%= for %>` block wrapping a single element" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <ul>
          <%= for item <- @items do %>
            <li>{item.name}</li>
          <% end %>
        </ul>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end

  test "flags a `<%= for %>` block wrapping a single self-closing element" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <.item_row item={item} />
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end

  test "flags a multiline single-element block" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <div
            id={item.id}
            class="foo"
          >
            {item.name}
          </div>
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end

  test "does not flag when the block wraps multiple sibling elements" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <dl>
          <%= for item <- @items do %>
            <dt>{item.name}</dt>
            <dd>{item.value}</dd>
          <% end %>
        </dl>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "does not flag `:for=` attribute usage" do
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
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "does not flag when the block has no elements (text/interpolation only)" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          {item.name}
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "does not flag the outer `<%= for %>` when it only wraps another `<%= for %>` block" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for group <- @groups do %>
          <%= for item <- group.items do %>
            <li>{item}</li>
          <% end %>
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    # Only the inner `<%= for %>` wraps a single element.
    |> assert_issue(&(&1.line_no >= 5))
  end

  test "does not flag `<%= for %>` with a conditional wrapping the single element" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <%= if item.active do %>
            <li>{item.name}</li>
          <% end %>
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "flags multiple for-blocks independently" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <ul>
          <%= for item <- @items do %>
            <li>{item.name}</li>
          <% end %>
        </ul>
        <dl>
          <%= for item <- @items do %>
            <dt>{item.name}</dt>
            <dd>{item.value}</dd>
          <% end %>
        </dl>
        <ol>
          <%= for item <- @other do %>
            <.row item={item} />
          <% end %>
        </ol>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issues(&(length(&1) == 2))
  end

  test "does not flag single-line `<%= for ..., do: ... %>` (not a block)" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <p><%= for name <- @names, do: name %></p>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "handles `into:` option before `do`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items, into: [] do %>
          <li>{item.name}</li>
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end

  test "still flags a single-element block when a non-block EEx tag sits alongside it" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <%= inspect(item) %>
          <li>{item.name}</li>
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end

  test "tolerates a `<%= for %>` with no matching `<% end %>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <li>{item.name}</li>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end

  test "tolerates an unclosed `<%` inside the block body" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <% unclosed eex
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "tolerates an unclosed HTML open tag inside the block body" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <li no closing
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "tolerates an orphaned `</` inside the block body" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          </orphan no close
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "does not flag a for-block whose body has an element and a sibling EEx expression" do
    # Two top-level elements (a child plus a sibling) — not flagged.
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <%= for item <- @items do %>
          <li>{item.name}</li>
          <hr />
        <% end %>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> refute_issues()
  end

  test "flags a for-block with a filter guard wrapping a single element" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <ul>
          <%= for item <- @items, item.active do %>
            <li>{item.name}</li>
          <% end %>
        </ul>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferForAttrOverForBlock)
    |> assert_issue()
  end
end
