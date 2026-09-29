defmodule Rbtz.CredoChecks.Readability.NoModuledocFalseTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.NoModuledocFalse

  test "exposes metadata from `use Credo.Check`" do
    assert NoModuledocFalse.id() |> is_binary()
    assert NoModuledocFalse.category() |> is_atom()
    assert NoModuledocFalse.base_priority() |> is_atom()
    assert NoModuledocFalse.explanations()[:check] |> is_binary()
    assert NoModuledocFalse.param_defaults() |> is_list()
    assert NoModuledocFalse.param_names() |> is_list()
  end

  test "flags `@moduledoc false`" do
    """
    defmodule MyApp.Slug do
      @moduledoc false

      def from_title(title), do: String.downcase(title)
    end
    """
    |> to_source_file()
    |> run_check(NoModuledocFalse)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@moduledoc false"
      assert issue.line_no == 2
    end)
  end

  test "does not flag a written `@moduledoc`, no attribute, or `@doc false`" do
    """
    defmodule MyApp.Slug do
      @moduledoc "Builds URL slugs from titles."

      @doc false
      def from_title(title), do: String.downcase(title)
    end

    defmodule MyApp.Title do
      def trim(title), do: String.trim(title)
    end
    """
    |> to_source_file()
    |> run_check(NoModuledocFalse)
    |> refute_issues()
  end
end
