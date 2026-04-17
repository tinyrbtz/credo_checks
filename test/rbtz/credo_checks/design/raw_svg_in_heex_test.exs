defmodule Rbtz.CredoChecks.Design.RawSvgInHeexTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.RawSvgInHeex

  test "exposes metadata from `use Credo.Check`" do
    assert RawSvgInHeex.id() |> is_binary()
    assert RawSvgInHeex.category() |> is_atom()
    assert RawSvgInHeex.base_priority() |> is_atom()
    assert RawSvgInHeex.explanation() |> is_binary()
    assert RawSvgInHeex.params_defaults() |> is_list()
    assert RawSvgInHeex.params_names() |> is_list()
  end

  test "flags raw `<svg>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <svg viewBox="0 0 24 24"><path d="..." /></svg>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawSvgInHeex)
    |> assert_issue()
  end

  test "does not flag FyrUI svg components" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.svg_lucide_search />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawSvgInHeex)
    |> refute_issues()
  end
end
