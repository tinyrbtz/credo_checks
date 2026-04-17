defmodule Rbtz.CredoChecks.Warning.PushEventSocketBindingTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.PushEventSocketBinding

  test "exposes metadata from `use Credo.Check`" do
    assert PushEventSocketBinding.id() |> is_binary()
    assert PushEventSocketBinding.category() |> is_atom()
    assert PushEventSocketBinding.base_priority() |> is_atom()
    assert PushEventSocketBinding.explanation() |> is_binary()
    assert PushEventSocketBinding.params_defaults() |> is_list()
    assert PushEventSocketBinding.params_names() |> is_list()
  end

  test "flags `push_event/3` as discarded statement" do
    """
    defmodule MyLive do
      def handle_event("save", _, socket) do
        push_event(socket, "saved", %{})
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(PushEventSocketBinding)
    |> assert_issue()
  end

  test "flags pipe-ending `push_event` as discarded statement" do
    """
    defmodule MyLive do
      def handle_event("save", _, socket) do
        socket |> push_event("saved", %{})
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(PushEventSocketBinding)
    |> assert_issue()
  end

  test "does not flag rebound `socket = push_event(...)`" do
    """
    defmodule MyLive do
      def handle_event("save", _, socket) do
        socket = push_event(socket, "saved", %{})
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(PushEventSocketBinding)
    |> refute_issues()
  end

  test "does not flag pipe assigned to socket" do
    """
    defmodule MyLive do
      def handle_event("save", _, socket) do
        socket = socket |> push_event("saved", %{})
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(PushEventSocketBinding)
    |> refute_issues()
  end

  test "does not flag if `push_event` is the sole expression" do
    """
    defmodule MyLive do
      def go(socket), do: push_event(socket, "x", %{})
    end
    """
    |> to_source_file()
    |> run_check(PushEventSocketBinding)
    |> refute_issues()
  end

  test "does not flag a pipe that continues past `push_event` to another stage" do
    # `push_event` is in the middle of a pipe chain, not at the end — we
    # can't tell whether the downstream stage preserves the event, so we
    # stay silent rather than risk a false positive.
    """
    defmodule MyLive do
      def handle_event("save", _, socket) do
        socket |> push_event("saved", %{}) |> some_other_transform()
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(PushEventSocketBinding)
    |> refute_issues()
  end
end
