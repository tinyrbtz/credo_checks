defmodule Rbtz.CredoChecks.MigrationSource do
  @moduledoc """
  Shared helpers for Credo checks that only want to run against Ecto migration
  files.

  A path counts as a migration when it lives under a `migrations/` directory
  anywhere in the expanded path and ends in `.exs`. This covers both the
  default `priv/repo/migrations/` layout and multi-repo projects that nest
  migrations under `priv/<repo>/migrations/`.
  """

  @doc """
  Returns `true` when `filename` looks like an Ecto migration file.
  """
  def migration_file?(filename) when is_binary(filename) do
    path = Path.expand(filename)
    String.contains?(path, "/migrations/") and String.ends_with?(path, ".exs")
  end

  def migration_file?(_), do: false
end
