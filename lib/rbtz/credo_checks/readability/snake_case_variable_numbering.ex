defmodule Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering do
  use Credo.Check,
    id: "RBTZ0010",
    base_priority: :normal,
    category: :readability,
    param_defaults: [exclude: []],
    explanations: [
      check: """
      Encourages numbered variables to use a separating underscore: `user_1`,
      `user_2` rather than `user1`, `user2`.

      The underscore makes it visually obvious that the trailing digit is an
      index, not part of the name. It also matches the rest of the snake_case
      convention used in Elixir code.

      # Bad

          user1 = %{name: "alice"}
          user2 = %{name: "bob"}

          def render(item1, item2), do: ...

      # Good

          user_1 = %{name: "alice"}
          user_2 = %{name: "bob"}

          def render(item_1, item_2), do: ...

      The check looks at every variable reference in the file. Each violating
      name is reported once at its first occurrence.

      Names where any snake_case component matches an entry in `:exclude`
      are skipped. Matching is component-wise, not substring — with
      `exclude: ["md5"]`:

      * `md5`, `md5_hash`, `file_md5`, `content_md5_digest` are ignored
      * `md5sum1` is still flagged (`md5` is not a whole component there)

          {Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering,
           [exclude: ["md5", "sha1", "sha256"]]}
      """,
      params: [
        exclude:
          "List of snake_case components (strings or atoms) to ignore. A variable is skipped when any of its underscore-separated components matches an entry."
      ]
    ]

  @bad_name_regex ~r/^_*[a-zA-Z][a-zA-Z_]*[a-zA-Z]\d+$/

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, {ctx, _seen}} = Macro.prewalk(ast, {ctx, MapSet.new()}, &walk/2)

        ctx.issues

      _ ->
        []
    end
  end

  defp walk({name, meta, nil} = ast, {ctx, seen}) when is_atom(name) do
    s = Atom.to_string(name)

    cond do
      MapSet.member?(seen, s) ->
        {ast, {ctx, seen}}

      Regex.match?(@bad_name_regex, s) and not excluded?(s, ctx.params.exclude) ->
        ctx = put_issue(ctx, issue_for(ctx, s, meta))
        {ast, {ctx, MapSet.put(seen, s)}}

      true ->
        {ast, {ctx, seen}}
    end
  end

  defp walk(ast, acc), do: {ast, acc}

  defp excluded?(name, patterns) do
    parts = String.split(name, "_")
    Enum.any?(patterns, &(to_string(&1) in parts))
  end

  defp issue_for(ctx, name, meta) do
    suggested = suggest(name)

    format_issue(ctx,
      message:
        "Variable `#{name}` should separate the trailing index with an underscore: `#{suggested}`.",
      trigger: name,
      line_no: meta[:line]
    )
  end

  defp suggest(name) do
    Regex.replace(~r/([a-zA-Z])(\d+)$/, name, "\\1_\\2")
  end
end
