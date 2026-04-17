defmodule Rbtz.CredoChecks.Warning.DisableMigrationLockTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.DisableMigrationLock

  test "exposes metadata from `use Credo.Check`" do
    assert DisableMigrationLock.id() |> is_binary()
    assert DisableMigrationLock.category() |> is_atom()
    assert DisableMigrationLock.base_priority() |> is_atom()
    assert DisableMigrationLock.explanation() |> is_binary()
    assert DisableMigrationLock.params_defaults() |> is_list()
    assert DisableMigrationLock.params_names() |> is_list()
  end

  test "flags `@disable_migration_lock true`" do
    """
    defmodule Repo.Migrations.AddIndex do
      use Ecto.Migration
      @disable_migration_lock true

      def change, do: :ok
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_add_index.exs")
    |> run_check(DisableMigrationLock)
    |> assert_issue()
  end

  test "does not flag without the override" do
    """
    defmodule Repo.Migrations.AddIndex do
      use Ecto.Migration

      def change, do: :ok
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_add_index.exs")
    |> run_check(DisableMigrationLock)
    |> refute_issues()
  end

  test "ignores files outside migrations" do
    """
    defmodule M do
      @disable_migration_lock true
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(DisableMigrationLock)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert DisableMigrationLock.run(src, []) == []
  end
end
