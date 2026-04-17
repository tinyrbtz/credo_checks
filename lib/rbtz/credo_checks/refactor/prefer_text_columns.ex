defmodule Rbtz.CredoChecks.Refactor.PreferTextColumns do
  use Credo.Check,
    id: "RBTZ0001",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Ensures that Ecto migrations use `:text` rather than `:string` for column
      types.

      In modern versions of PostgreSQL there is no storage or performance
      benefit to textual columns with a fixed maximum length. It is almost
      always preferable to leave the maximum length unset in the database and
      enforce length limits as a business rule at the application level via
      changeset validations.

      # Bad

          add :name, :string
          modify :description, :string

      # Good

          add :name, :text
          modify :description, :text

      Like all `Design` issues, this one is not a technical concern.
      It encodes a project-wide convention; disable per-line with
      `# credo:disable-for-next-line` when a fixed-length column is genuinely
      required (e.g. legacy schemas, foreign keys to immutable identifiers).
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

  for op <- [:add, :modify] do
    defp walk({unquote(op), meta, [_field, :string | _rest]} = ast, ctx) do
      {ast, put_issue(ctx, issue_for(ctx, meta, unquote(op)))}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, op) do
    format_issue(ctx,
      message:
        "Prefer `:text` over `:string` for migration columns. " <>
          "Length limits should be enforced via changeset validations, not the database schema.",
      trigger: "#{op} :string",
      line_no: meta[:line]
    )
  end
end
