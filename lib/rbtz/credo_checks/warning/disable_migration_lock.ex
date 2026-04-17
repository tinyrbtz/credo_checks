defmodule Rbtz.CredoChecks.Warning.DisableMigrationLock do
  use Credo.Check,
    id: "RBTZ0016",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Forbids `@disable_migration_lock true` in Ecto migration files.

      The migration lock prevents two deployment processes from running the
      same migration concurrently — disabling it can leave the schema in an
      inconsistent state under any rolling-deploy scenario. This project
      additionally configures `migration_lock: :pg_advisory_lock` globally,
      so the per-migration override should never be needed.

      If a long-running migration genuinely cannot hold the lock (e.g.
      `CREATE INDEX CONCURRENTLY`), break it into a separate migration that
      uses `@disable_ddl_transaction true` and discuss the deploy plan with
      the team rather than silently disabling locking.

      # Bad

          defmodule Repo.Migrations.AddIndex do
            use Ecto.Migration
            @disable_migration_lock true

            def change, do: ...
          end

      # Good (no override needed; rely on global config)

          defmodule Repo.Migrations.AddIndex do
            use Ecto.Migration

            def change, do: ...
          end
      """
    ]

  alias Rbtz.CredoChecks.MigrationSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if MigrationSource.migration_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp walk({:@, meta, [{:disable_migration_lock, _, [true]}]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta) do
    format_issue(ctx,
      message:
        "`@disable_migration_lock true` removes the safety net against concurrent " <>
          "migration runs. The project's global `migration_lock: :pg_advisory_lock` " <>
          "config means this override should never be needed.",
      trigger: "@disable_migration_lock",
      line_no: meta[:line]
    )
  end
end
