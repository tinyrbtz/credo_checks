defmodule Rbtz.CredoChecks.Warning.PhxHookWithoutId do
  use Credo.Check,
    id: "RBTZ0026",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires every element with `phx-hook` to also carry an `id` attribute.

      Phoenix LiveView hooks are keyed by DOM `id`: without it, LiveView
      cannot route `pushEvent`s back to the right hook instance, and morphdom
      may swap the hooked element with a different one across patches —
      causing `mounted()` to be called repeatedly or never. The framework
      itself raises at runtime if you forget the `id`, but a static check
      catches the typo at code-review time instead.

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`. It walks each opening tag (across multiple lines)
      and flags those that carry `phx-hook=` without `id=`.

      # Bad

          <div phx-hook=".PhoneNumber">...</div>

      # Good

          <div id="phone-number" phx-hook=".PhoneNumber">...</div>
      """
    ]

  alias Rbtz.CredoChecks.PhxAttrRequiresId

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> PhxAttrRequiresId.offending_tag_lines(&String.contains?(&1, "phx-hook"))
    |> Enum.reduce(ctx, fn line_no, ctx -> put_issue(ctx, issue_for(ctx, line_no)) end)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "An element with `phx-hook` requires an `id` attribute on the same element. " <>
          "Without it, LiveView cannot route hook events or maintain the hook across patches.",
      trigger: "phx-hook",
      line_no: line_no
    )
  end
end
