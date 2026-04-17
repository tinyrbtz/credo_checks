defmodule Rbtz.CredoChecks.Design.BareScriptInHeex do
  use Credo.Check,
    id: "RBTZ0011",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Forbids raw inline `<script>` tags in HEEx templates.

      Inline `<script>` markup bypasses Phoenix LiveView's render lifecycle,
      breaks LiveView reconnect/morphdom semantics, and tends to grow into
      ad-hoc JavaScript that lives outside the asset pipeline. Use one of:

        * a colocated `phx-hook` for behavior tied to a specific element,
        * a colocated script via `:type={Phoenix.LiveView.ColocatedHook}` /
          `:type={Phoenix.LiveView.ColocatedJS}` (processed at compile time),
        * a `<script>` in the root layout for app-wide setup loaded once, or
        * an external script imported through the asset bundler for
          third-party integrations.

      Script tags are allowed when they are not inline bodies:

        * `<script :type={...}>` — a Phoenix colocated declaration, hoisted
          to a separate file at compile time.
        * `<script ... src="...">` — an external source; the tag body is
          ignored per the HTML spec.

      The check inspects every `~H` sigil and every `.heex` template
      referenced via `embed_templates`.

      # Bad

          <script>
            console.log("hello");
          </script>

      # Good

          <div id="phone" phx-hook=".PhoneNumber">...</div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".Filter">...</script>
          <script defer src="https://accounts.google.com/gsi/client"></script>
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  @script_open_regex ~r/<script(?=[\s>])(?:[^>{]|\{[^}]*\})*>/s

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template/2)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx) do
    @script_open_regex
    |> Regex.scan(heex, return: :index)
    |> Enum.reduce(ctx, fn [{start, length}], ctx ->
      tag = binary_part(heex, start, length)

      if allowed?(tag) do
        ctx
      else
        line_no = heex |> binary_part(0, start) |> HeexSource.count_newlines() |> line_fn.()
        put_issue(ctx, issue_for(ctx, line_no))
      end
    end)
  end

  defp allowed?(tag) do
    tag =~ ~r/\s:type=/ or tag =~ ~r/\ssrc=/
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid raw inline `<script>` tags in HEEx. Use a `phx-hook`, a colocated " <>
          "`:type={...}` declaration, the root layout, or the asset bundler instead.",
      trigger: "<script",
      line_no: line_no
    )
  end
end
