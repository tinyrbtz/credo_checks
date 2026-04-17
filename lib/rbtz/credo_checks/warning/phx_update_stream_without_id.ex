defmodule Rbtz.CredoChecks.Warning.PhxUpdateStreamWithoutId do
  use Credo.Check,
    id: "RBTZ0038",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires every element with `phx-update="stream"` to also carry an
      `id` attribute.

      LiveView streams key children by DOM id. Without a stable id on the
      stream container, LiveView cannot diff the inserted/removed items
      across patches — items disappear, duplicate, or land in the wrong
      position. The framework raises at runtime if the id is missing, but
      a static check catches the mistake at code-review time.

      The check inspects every `~H` sigil and every `.heex` template
      referenced via `embed_templates`. It walks each opening tag (across
      multiple lines) and flags those that carry `phx-update="stream"`
      without `id=`.

      # Bad

          <div phx-update="stream">
            <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>...</div>
          </div>

      # Good

          <div id="messages" phx-update="stream">
            <div :for={{dom_id, msg} <- @streams.messages} id={dom_id}>...</div>
          </div>
      """
    ]

  alias Rbtz.CredoChecks.PhxAttrRequiresId

  @stream_regex ~r/\bphx-update=("stream"|\{"stream"\})/

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> PhxAttrRequiresId.offending_tag_lines(&Regex.match?(@stream_regex, &1))
    |> Enum.reduce(ctx, fn line_no, ctx -> put_issue(ctx, issue_for(ctx, line_no)) end)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        ~s(An element with `phx-update="stream"` requires an `id` attribute on the ) <>
          "same element. Without it, LiveView cannot diff stream items across patches.",
      trigger: "phx-update",
      line_no: line_no
    )
  end
end
