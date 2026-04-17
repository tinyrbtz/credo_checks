defmodule Rbtz.CredoChecks.Refactor.PreferEctoMigrationHelperTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Refactor.PreferEctoMigrationHelper

  test "exposes metadata from `use Credo.Check`" do
    assert PreferEctoMigrationHelper.id() |> is_binary()
    assert PreferEctoMigrationHelper.category() |> is_atom()
    assert PreferEctoMigrationHelper.base_priority() |> is_atom()
    assert PreferEctoMigrationHelper.explanation() |> is_binary()
    assert PreferEctoMigrationHelper.params_defaults() |> is_list()
    assert PreferEctoMigrationHelper.params_names() |> is_list()
  end

  test ~s|flags raw `execute("ALTER TABLE ...")`| do
    """
    defmodule Repo.Migrations.AddStatus do
      use Ecto.Migration

      def change do
        execute("ALTER TABLE users ADD COLUMN status text")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_add_status.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> assert_issue()
  end

  test ~s|flags raw `execute("CREATE TABLE ...")`| do
    """
    defmodule Repo.Migrations.CreateWidgets do
      use Ecto.Migration

      def change do
        execute("CREATE TABLE widgets (id bigserial PRIMARY KEY)")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_create_widgets.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> assert_issue()
  end

  test ~s|flags raw `execute("DROP TABLE ...")`| do
    """
    defmodule Repo.Migrations.DropWidgets do
      use Ecto.Migration

      def change do
        execute("DROP TABLE widgets")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_drop_widgets.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> assert_issue()
  end

  test ~s|flags raw `execute("CREATE INDEX ...")`| do
    """
    defmodule Repo.Migrations.IndexUsersEmail do
      use Ecto.Migration

      def change do
        execute("CREATE INDEX users_email_idx ON users (email)")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_index_users_email.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> assert_issue()
  end

  test ~s|flags raw `execute("CREATE UNIQUE INDEX ...")`| do
    """
    defmodule Repo.Migrations.UniqueUsersEmail do
      use Ecto.Migration

      def change do
        execute("CREATE UNIQUE INDEX users_email_idx ON users (email)")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_unique_users_email.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> assert_issue()
  end

  test "flags case-insensitively and tolerates leading whitespace" do
    """
    defmodule Repo.Migrations.AddStatus do
      use Ecto.Migration

      def change do
        execute("   alter table users add column status text")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_add_status.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> assert_issue()
  end

  test ~s|does not flag `execute("CREATE EXTENSION ...")` (no Ecto helper)| do
    """
    defmodule Repo.Migrations.EnableCitext do
      use Ecto.Migration

      def change do
        execute("CREATE EXTENSION IF NOT EXISTS citext")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_enable_citext.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> refute_issues()
  end

  test ~s|does not flag `execute("GRANT ...")` (no Ecto helper)| do
    """
    defmodule Repo.Migrations.GrantReader do
      use Ecto.Migration

      def change do
        execute("GRANT SELECT ON ALL TABLES IN SCHEMA public TO reader")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_grant_reader.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> refute_issues()
  end

  test ~s|does not flag `execute("UPDATE ...")` data backfills| do
    """
    defmodule Repo.Migrations.BackfillStatus do
      use Ecto.Migration

      def change do
        execute("UPDATE users SET status = 'pending' WHERE status IS NULL")
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_backfill_status.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> refute_issues()
  end

  test "does not flag `execute/2` with reverse direction" do
    """
    defmodule Repo.Migrations.Backfill do
      use Ecto.Migration

      def change do
        execute(
          "UPDATE users SET status = 'pending'",
          "UPDATE users SET status = NULL"
        )
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_backfill.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> refute_issues()
  end

  test "does not flag Ecto helpers" do
    """
    defmodule Repo.Migrations.AddStatus do
      use Ecto.Migration

      def change do
        alter table(:users) do
          add :status, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000000_add_status.exs")
    |> run_check(PreferEctoMigrationHelper)
    |> refute_issues()
  end

  test "ignores files outside migrations" do
    """
    defmodule M do
      def go, do: execute("ALTER TABLE users ADD COLUMN status text")
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(PreferEctoMigrationHelper)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert PreferEctoMigrationHelper.run(src, []) == []
  end
end
