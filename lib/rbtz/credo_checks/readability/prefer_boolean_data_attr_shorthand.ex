defmodule Rbtz.CredoChecks.Readability.PreferBooleanDataAttrShorthand do
  use Credo.Check,
    id: "RBTZ0036",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Forbids `data-[<name>]:` bracket-variant syntax for **boolean**
      data-attribute Tailwind variants. Use the shorthand `data-<name>:`
      form instead.

      Tailwind supports two forms for data-attribute variants:

        * `data-<name>:` — matches when the attribute is present (boolean).
        * `data-[<name>=<value>]:` — matches when the attribute has a
          specific value.

      For boolean attributes like `data-disabled` or `data-open`, the
      bracketed form (`data-[disabled]:`) is an obscure way of writing
      `data-disabled:`. Reserve brackets for value matching
      (`data-[state=open]:`).

      The check inspects every `~H` sigil and every `.heex` template
      referenced via `embed_templates`. Detection is line-by-line: a
      `data-[name]:` whose brackets wrap across lines is not flagged.

      # Bad

          <div class={["data-[disabled]:opacity-50"]}>...</div>

      # Good

          <div class={["data-disabled:opacity-50"]}>...</div>
          <div class={["data-[state=open]:bg-red-50"]}>...</div>
      """
    ]

  # `data-[<ident>]:` where the bracket body is a bare identifier (letters,
  # digits, hyphens, underscores) with no `=` inside.
  @bracket_bool_regex ~r/data-\[([A-Za-z][A-Za-z0-9_-]*)\]:/

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> Rbtz.CredoChecks.HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template/2)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx) do
    heex
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce(ctx, fn {line, idx}, ctx ->
      line_no = line_fn.(idx)

      @bracket_bool_regex
      |> Regex.scan(line, capture: :all_but_first)
      |> Enum.reduce(ctx, fn [name], ctx -> put_issue(ctx, issue_for(ctx, line_no, name)) end)
    end)
  end

  defp issue_for(ctx, line_no, name) do
    format_issue(ctx,
      message:
        "Use the shorthand `data-#{name}:` instead of `data-[#{name}]:` for boolean " <>
          "data-attribute variants. Reserve brackets for value matching " <>
          "like `data-[state=open]:`.",
      trigger: "data-[#{name}]:",
      line_no: line_no
    )
  end
end
