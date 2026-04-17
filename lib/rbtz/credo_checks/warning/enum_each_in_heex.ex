defmodule Rbtz.CredoChecks.Warning.EnumEachInHeex do
  use Credo.Check,
    id: "RBTZ0024",
    base_priority: :normal,
    category: :warning,
    explanations: [
      check: """
      Forbids `<% Enum.each %>` (and other side-effecting EEx constructs) in
      HEEx templates.

      `<% Enum.each %>` runs the enumeration purely for side effects and
      returns `:ok` — its body cannot emit markup the way `<%= for %>` or the
      `:for=` element attribute can. In a HEEx template this almost always
      means the markup the developer intended to render simply doesn't appear.

      Use the `:for=` attribute on the rendered element when iterating one
      element at a time, or the `<%= for %>` block expression when wrapping
      multiple elements per item.

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`. Detection is line-by-line: a `<% Enum.each` that
      wraps onto the next line is not flagged (the formatter keeps the opener
      on one line in practice).

      # Bad

          <% Enum.each(@items, fn item -> %>
            <li>{item.name}</li>
          <% end) %>

      # Good

          <li :for={item <- @items}>{item.name}</li>

          <%= for item <- @items do %>
            <li>{item.name}</li>
            <span>{item.subtitle}</span>
          <% end %>
      """
    ]

  @enum_each_regex ~r/<%\s*Enum\.each\b/

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
      if Regex.match?(@enum_each_regex, line) do
        put_issue(ctx, issue_for(ctx, line_fn.(idx)))
      else
        ctx
      end
    end)
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid `<% Enum.each %>` in HEEx — it discards markup. " <>
          "Use `:for={item <- @collection}` on the element, or `<%= for item <- @collection do %>` " <>
          "to wrap multiple elements.",
      trigger: "Enum.each",
      line_no: line_no
    )
  end
end
