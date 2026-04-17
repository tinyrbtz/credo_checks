defmodule Rbtz.CredoChecks.Refactor.PreferEctoMigrationHelper do
  use Credo.Check,
    id: "RBTZ0017",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Discourages raw SQL `execute("...")` in Ecto migrations when an
      equivalent migration helper exists.

      Ecto's migration helpers (`create`, `alter`, `add`, `modify`, `remove`,
      `rename`, `unique_index`, `references`, ...) are reversible, get
      formatted into the `down/0` reverse migration automatically, and are
      portable across the Ecto-supported adapters.

      Reach for raw `execute/1` only when no helper covers your case (e.g.
      backfilling rows, vendor-specific DDL like `CREATE EXTENSION`); when
      you do, prefer `execute/2` so the reverse SQL is also captured.

      # Bad

          execute("ALTER TABLE users ADD COLUMN status text NOT NULL DEFAULT 'pending'")

      # Good

          alter table(:users) do
            add :status, :text, null: false, default: "pending"
          end

          # ...or, when raw SQL is genuinely required, capture both directions:
          execute(
            "UPDATE users SET status = 'pending' WHERE status IS NULL",
            "UPDATE users SET status = NULL WHERE status = 'pending'"
          )
      """
    ]

  alias Rbtz.CredoChecks.MigrationSource

  @ddl_with_helpers [
    "create unique index",
    "create index",
    "create table",
    "drop table",
    "drop index",
    "alter table",
    "rename table"
  ]

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

  defp walk({:execute, meta, [arg]} = ast, ctx) when is_binary(arg) do
    if ecto_helper_exists?(arg) do
      {ast, put_issue(ctx, issue_for(ctx, meta))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp ecto_helper_exists?(sql) do
    normalized = sql |> String.trim_leading() |> String.downcase()
    Enum.any?(@ddl_with_helpers, &String.starts_with?(normalized, &1))
  end

  defp issue_for(ctx, meta) do
    format_issue(ctx,
      message:
        ~s|Prefer Ecto migration helpers (`alter`, `add`, `modify`, ...) over raw `execute("...")`. | <>
          "If raw SQL is genuinely required, use `execute/2` to capture the reverse direction.",
      trigger: "execute",
      line_no: meta[:line]
    )
  end
end
