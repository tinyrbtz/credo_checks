defmodule Rbtz.CredoChecks.Warning.PhxClickAwayWithoutId do
  use Credo.Check,
    id: "RBTZ0012",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires every element with `phx-click-away` to also carry an `id`
      attribute.

      `phx-click-away` registers a document-level click listener that fires
      when the user clicks outside the element. LiveView uses the element's
      DOM `id` to match it across patches; without it, the listener can be
      orphaned, fire twice, or be lost entirely after re-render — leading to
      menus that won't close (or close at the wrong time).

      The check inspects every `~H` sigil and every `.heex` template
      referenced via `embed_templates`. It walks each opening tag (across
      multiple lines) and flags those that carry `phx-click-away=` without
      `id=`.

      # Bad

          <div phx-click-away="close">...</div>

      # Good

          <div id="menu" phx-click-away="close">...</div>
      """
    ]

  alias Rbtz.CredoChecks.PhxAttrRequiresId

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> PhxAttrRequiresId.offending_tag_lines(&String.contains?(&1, "phx-click-away"))
    |> Enum.reduce(ctx, fn line_no, ctx -> put_issue(ctx, issue_for(ctx, line_no)) end)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "An element with `phx-click-away` requires an `id` attribute on the same element. " <>
          "Without it, LiveView cannot maintain the click-outside listener across patches.",
      trigger: "phx-click-away",
      line_no: line_no
    )
  end
end
