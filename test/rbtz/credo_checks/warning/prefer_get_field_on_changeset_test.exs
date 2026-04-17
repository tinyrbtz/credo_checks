defmodule Rbtz.CredoChecks.Warning.PreferGetFieldOnChangesetTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.PreferGetFieldOnChangeset

  test "exposes metadata from `use Credo.Check`" do
    assert PreferGetFieldOnChangeset.id() |> is_binary()
    assert PreferGetFieldOnChangeset.category() |> is_atom()
    assert PreferGetFieldOnChangeset.base_priority() |> is_atom()
    assert PreferGetFieldOnChangeset.explanation() |> is_binary()
    assert PreferGetFieldOnChangeset.params_defaults() |> is_list()
    assert PreferGetFieldOnChangeset.params_names() |> is_list()
  end

  test "flags `changeset.field`" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def name(changeset) do
        changeset.name
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> assert_issue()
  end

  test "flags `changeset.changes.field`" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def name(changeset) do
        changeset.changes.name
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> assert_issue()
  end

  test "flags `changeset.data.field`" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def email(changeset) do
        changeset.data.email
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> assert_issue()
  end

  test "flags `changeset[:key]`" do
    ~S'''
    defmodule MyMod do
      alias Ecto.Changeset

      def email(changeset) do
        changeset[:email]
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> assert_issue()
  end

  test "does not flag when Ecto.Changeset is not imported or aliased" do
    ~S'''
    defmodule MyMod do
      def name(changeset) do
        changeset.field
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> refute_issues()
  end

  test "does not flag `Ecto.Changeset.get_field/2` itself" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def name(changeset) do
        changeset |> get_field(:name)
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> refute_issues()
  end

  test "does not flag access on variables named differently" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def name(record) do
        record.name
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> refute_issues()
  end

  test "does not flag reads of Changeset struct fields" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def inspect_it(changeset) do
        _ = changeset.valid?
        _ = changeset.data
        _ = changeset.changes
        _ = changeset.errors
        _ = changeset.action
        _ = changeset.types
        _ = changeset.params
        _ = changeset.required
        :ok
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> refute_issues()
  end

  test "does not flag `changeset.data.__struct__` / `changeset.data.__meta__`" do
    ~S'''
    defmodule MyMod do
      import Ecto.Changeset

      def schema(changeset) do
        {changeset.data.__struct__, changeset.data.__meta__}
      end
    end
    '''
    |> to_source_file()
    |> run_check(PreferGetFieldOnChangeset)
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PreferGetFieldOnChangeset.run(src, []) == []
  end
end
