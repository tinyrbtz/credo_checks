defmodule Rbtz.CredoChecks.Warning.PreferGetFieldOnChangeset do
  use Credo.Check,
    id: "RBTZ0028",
    base_priority: :normal,
    category: :warning,
    explanations: [
      check: """
      Encourages reading schema fields off an `Ecto.Changeset` via
      `Ecto.Changeset.get_field/2` rather than direct struct access
      (`changeset.changes.field`, `changeset.data.field`) or `Access`
      (`changeset[:field]`).

      `get_field/2` returns the post-cast value: it transparently picks the
      change if one is present, falls back to the original data otherwise,
      and respects embeds. Reaching into `:data` or `:changes` by hand only
      sees one layer and easily reads a stale value when both exist.
      `changeset[:key]` is a friendlier shortcut for the same direct access
      and shares the pitfall.

      Reads of the `%Ecto.Changeset{}` struct's own fields
      (`changeset.valid?`, `changeset.data`, `changeset.errors`,
      `changeset.action`, etc.) are **not** flagged — those are legitimate
      uses of the struct's public API, not schema-field access.

      To limit false positives, the check only runs against files that
      `import` or `alias` `Ecto.Changeset` somewhere in the source — this
      keeps it from flagging unrelated variables that happen to be named
      `changeset` (e.g. struct fields, helper params).

      # Bad

          name = changeset.changes.name
          email = changeset.data.email
          age = changeset[:age]

      # Good

          name = Ecto.Changeset.get_field(changeset, :name)
          email = Ecto.Changeset.get_field(changeset, :email)
          age = Ecto.Changeset.get_field(changeset, :age)
      """
    ]

  @changeset_struct_fields ~w(action changes constraints data empty_values errors filters params prepare repo repo_opts required types valid? validations)a

  @skip_meta_fields [:__struct__, :__meta__]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        if uses_ecto_changeset?(ast) do
          ctx = Context.build(source_file, params, __MODULE__)
          {_ast, ctx} = Macro.prewalk(ast, ctx, &walk/2)
          Enum.reverse(ctx.issues)
        else
          []
        end

      _ ->
        []
    end
  end

  defp uses_ecto_changeset?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        node, true ->
          {node, true}

        {kw, _meta, [{:__aliases__, _, [:Ecto, :Changeset]} | _]} = node, _acc
        when kw in [:alias, :import] ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  # changeset.data.field / changeset.changes.field
  defp walk(
         {{:., _, [{{:., _, [{:changeset, _, ctx}, layer]}, _, []}, field]}, meta, []} = ast,
         walker_ctx
       )
       when is_atom(ctx) and layer in [:data, :changes] and is_atom(field) and
              field not in @skip_meta_fields do
    {ast, put_issue(walker_ctx, issue_for(walker_ctx, :compound, meta, {layer, field}))}
  end

  # changeset.field (schema fields only — struct fields are allowlisted)
  defp walk({{:., _, [{:changeset, _, ctx}, field]}, meta, []} = ast, walker_ctx)
       when is_atom(ctx) and is_atom(field) and field not in @changeset_struct_fields do
    {ast, put_issue(walker_ctx, issue_for(walker_ctx, :dot, meta, field))}
  end

  # changeset[:key]
  defp walk({{:., _, [Access, :get]}, meta, [{:changeset, _, ctx}, key]} = ast, walker_ctx)
       when is_atom(ctx) do
    {ast, put_issue(walker_ctx, issue_for(walker_ctx, :access, meta, key))}
  end

  defp walk(ast, walker_ctx), do: {ast, walker_ctx}

  defp issue_for(ctx, kind, meta, field) do
    {trigger, suggestion} =
      case {kind, field} do
        {:dot, field} ->
          {"changeset.#{field}", "Ecto.Changeset.get_field(changeset, :#{field})"}

        {:access, key} ->
          {"changeset[#{inspect(key)}]", "Ecto.Changeset.get_field(changeset, #{inspect(key)})"}

        {:compound, {layer, field}} ->
          {"changeset.#{layer}.#{field}", "Ecto.Changeset.get_field(changeset, :#{field})"}
      end

    format_issue(ctx,
      message:
        "Read changeset fields with `Ecto.Changeset.get_field/2` instead of `#{trigger}`. " <>
          "Use `#{suggestion}`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
