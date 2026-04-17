defmodule Rbtz.CredoChecks.Readability.LiveViewCallbackOrderTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.LiveViewCallbackOrder

  test "exposes metadata from `use Credo.Check`" do
    assert LiveViewCallbackOrder.id() |> is_binary()
    assert LiveViewCallbackOrder.category() |> is_atom()
    assert LiveViewCallbackOrder.base_priority() |> is_atom()
    assert LiveViewCallbackOrder.explanation() |> is_binary()
    assert LiveViewCallbackOrder.params_defaults() |> is_list()
    assert LiveViewCallbackOrder.params_names() |> is_list()
  end

  test "flags render before handle_event" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      def mount(_, _, socket), do: {:ok, socket}
      def render(assigns), do: ~H""
      def handle_event("x", _, socket), do: {:noreply, socket}
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> assert_issue()
  end

  test "does not flag helpers interleaved with callbacks" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      def mount(_, _, socket), do: {:ok, socket}
      defp helper(x), do: x
      def handle_event("x", _, socket), do: {:noreply, socket}
      def render(assigns), do: ~H""
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "does not flag helpers defined above mount" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      defp helper(x), do: x
      defp another(y), do: y

      def mount(_, _, socket), do: {:ok, socket}
      def handle_event("x", _, socket), do: {:noreply, socket}
      def render(assigns), do: ~H""
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "flags callbacks out of order even when helpers sit between them" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      def mount(_, _, socket), do: {:ok, socket}
      def handle_event("x", _, socket), do: {:noreply, socket}
      defp helper(x), do: x
      def handle_params(_, _, socket), do: {:noreply, socket}
      def render(assigns), do: ~H""
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> assert_issue()
  end

  test "does not flag canonical order" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      def mount(_, _, socket), do: {:ok, socket}
      def handle_params(_, _, socket), do: {:noreply, socket}
      def handle_event("x", _, socket), do: {:noreply, socket}
      def handle_info(_, socket), do: {:noreply, socket}
      def handle_async(_, _, socket), do: {:noreply, socket}
      def render(assigns), do: ~H""
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "does not flag multiple handle_event clauses grouped together" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      def mount(_, _, socket), do: {:ok, socket}
      def handle_event("x", _, socket), do: {:noreply, socket}
      def handle_event("y", _, socket), do: {:noreply, socket}
      def render(assigns), do: ~H""
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "does not flag with `use SomethingWeb, :live_view`" do
    ~S'''
    defmodule MyAppWeb.PageLive do
      use MyAppWeb, :live_view

      def mount(_, _, socket), do: {:ok, socket}
      def handle_event("x", _, socket), do: {:noreply, socket}
      def render(assigns), do: ~H""
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "does not run on non-LiveView modules" do
    ~S'''
    defmodule MyMod do
      def render(_), do: :ok
      def mount(_), do: :ok
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "does not crash on a single-statement module body" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewCallbackOrder)
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert LiveViewCallbackOrder.run(src, []) == []
  end
end
