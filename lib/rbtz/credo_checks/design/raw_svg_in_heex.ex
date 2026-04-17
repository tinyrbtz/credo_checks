defmodule Rbtz.CredoChecks.Design.RawSvgInHeex do
  use Credo.Check,
    id: "RBTZ0023",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Forbids raw `<svg>` tags in HEEx templates.

      Icons should come from the `FyrUI.SVG` module via `<.svg_lucide_*>`
      function components (or `<.svg_hero_*>` when a Lucide variant is not
      available). The component approach keeps icon naming consistent across
      the app, supports compile-time icon-set verification, and avoids
      copy-pasting raw SVG markup across files.

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`. Detection is line-by-line: a `<svg` whose first
      attribute sits on the next line is not flagged.

      # Bad

          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <path d="..." />
          </svg>

      # Good

          <.svg_lucide_search />
      """
    ]

  @svg_open_regex ~r/<svg(?=[\s>])/

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
      if Regex.match?(@svg_open_regex, line) do
        put_issue(ctx, issue_for(ctx, line_fn.(idx)))
      else
        ctx
      end
    end)
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "Use a `FyrUI.SVG` icon component (e.g. `<.svg_lucide_search />`) instead of raw `<svg>` markup.",
      trigger: "<svg",
      line_no: line_no
    )
  end
end
