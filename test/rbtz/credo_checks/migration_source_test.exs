defmodule Rbtz.CredoChecks.MigrationSourceTest do
  use ExUnit.Case, async: true

  alias Rbtz.CredoChecks.MigrationSource

  describe "migration_file?/1" do
    test "accepts paths under a `migrations/` directory with `.exs` extension" do
      assert MigrationSource.migration_file?("priv/repo/migrations/20250101_x.exs")
      assert MigrationSource.migration_file?("priv/other_repo/migrations/20250101_x.exs")
    end

    test "rejects `.ex` files and non-migration paths" do
      refute MigrationSource.migration_file?("priv/repo/migrations/20250101_x.ex")
      refute MigrationSource.migration_file?("lib/foo.exs")
      refute MigrationSource.migration_file?("priv/repo/seeds.exs")
    end

    test "rejects non-binary input (e.g. nil filename from Credo)" do
      refute MigrationSource.migration_file?(nil)
    end
  end
end
