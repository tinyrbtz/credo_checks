defmodule Rbtz.CredoChecks.Refactor.PreferToFormInTemplatesTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.PreferToFormInTemplates

  test "exposes metadata from `use Credo.Check`" do
    assert PreferToFormInTemplates.id() |> is_binary()
    assert PreferToFormInTemplates.category() |> is_atom()
    assert PreferToFormInTemplates.base_priority() |> is_atom()
    assert PreferToFormInTemplates.explanation() |> is_binary()
    assert PreferToFormInTemplates.params_defaults() |> is_list()
    assert PreferToFormInTemplates.params_names() |> is_list()
  end

  test "flags `@changeset` on the form opening tag" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@changeset} phx-submit="save">
          <.input field={@changeset[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferToFormInTemplates)
    |> assert_issues()
  end

  test "flags `@changeset` inside form body" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@form} phx-submit="save">
          <.input field={@changeset[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferToFormInTemplates)
    |> assert_issue()
  end

  test "does not flag `@changeset` outside any form scope" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <p>Status: {@changeset.action}</p>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferToFormInTemplates)
    |> refute_issues()
  end

  test "does not flag `@form` inside form scope" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@form} phx-submit="save">
          <.input field={@form[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferToFormInTemplates)
    |> refute_issues()
  end

  test "does not flag templates with no form" do
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
    |> run_check(PreferToFormInTemplates)
    |> refute_issues()
  end
end
