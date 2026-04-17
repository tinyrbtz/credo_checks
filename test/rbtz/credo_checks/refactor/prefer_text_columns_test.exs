defmodule Rbtz.CredoChecks.Refactor.PreferTextColumnsTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.PreferTextColumns

  test "exposes metadata from `use Credo.Check`" do
    assert PreferTextColumns.id() |> is_binary()
    assert PreferTextColumns.category() |> is_atom()
    assert PreferTextColumns.base_priority() |> is_atom()
    assert PreferTextColumns.explanation() |> is_binary()
    assert PreferTextColumns.params_defaults() |> is_list()
    assert PreferTextColumns.params_names() |> is_list()
  end

  test "flags `add :col, :string`" do
    """
    defmodule Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def change do
        create table(:users) do
          add :name, :string
          add :email, :string
          timestamps()
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_create_users.exs")
    |> run_check(PreferTextColumns)
    |> assert_issues(2)
  end

  test "flags `modify :col, :string`" do
    """
    defmodule Repo.Migrations.AlterUsers do
      use Ecto.Migration

      def change do
        alter table(:users) do
          modify :name, :string
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_alter_users.exs")
    |> run_check(PreferTextColumns)
    |> assert_issue()
  end

  test "does not flag `:text` columns" do
    """
    defmodule Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def change do
        create table(:users) do
          add :name, :text
          modify :email, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_create_users.exs")
    |> run_check(PreferTextColumns)
    |> refute_issues()
  end

  test "does not flag non-string column types" do
    """
    defmodule Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def change do
        create table(:users) do
          add :age, :integer
          add :balance, :decimal
          add :active, :boolean
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_create_users.exs")
    |> run_check(PreferTextColumns)
    |> refute_issues()
  end

  test "ignores files outside migrations" do
    """
    defmodule MyApp.Schema do
      def field, do: :string
    end
    """
    |> to_source_file("lib/my_app/schema.ex")
    |> run_check(PreferTextColumns)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert PreferTextColumns.run(src, []) == []
  end
end
