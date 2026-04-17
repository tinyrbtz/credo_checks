defmodule Rbtz.CredoChecks.Warning.PhxUpdateStreamWithoutIdTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.PhxUpdateStreamWithoutId

  test "exposes metadata from `use Credo.Check`" do
    assert PhxUpdateStreamWithoutId.id() |> is_binary()
    assert PhxUpdateStreamWithoutId.category() |> is_atom()
    assert PhxUpdateStreamWithoutId.base_priority() |> is_atom()
    assert PhxUpdateStreamWithoutId.explanation() |> is_binary()
    assert PhxUpdateStreamWithoutId.params_defaults() |> is_list()
    assert PhxUpdateStreamWithoutId.params_names() |> is_list()
  end

  test ~s(flags `<div phx-update="stream">` without id) do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div phx-update="stream">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxUpdateStreamWithoutId)
    |> assert_issue()
  end

  test "flags multi-line tag missing id" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div
          phx-update="stream"
          class="flex flex-col"
        >
          x
        </div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxUpdateStreamWithoutId)
    |> assert_issue()
  end

  test "does not flag when id is present" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div id="messages" phx-update="stream">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxUpdateStreamWithoutId)
    |> refute_issues()
  end

  test ~s(does not flag phx-update="ignore") do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div phx-update="ignore">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxUpdateStreamWithoutId)
    |> refute_issues()
  end

  test "does not flag plain elements" do
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
    |> run_check(PhxUpdateStreamWithoutId)
    |> refute_issues()
  end
end
