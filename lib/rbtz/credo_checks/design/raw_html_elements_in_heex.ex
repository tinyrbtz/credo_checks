defmodule Rbtz.CredoChecks.Design.RawHtmlElementsInHeex do
  use Credo.Check,
    id: "RBTZ0022",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Forbids raw `<button>`, `<input>`, `<select>`, `<textarea>`, and `<a>`
      elements in HEEx templates.

      Projects typically provide typed, accessible, design-system-consistent
      component equivalents (`<.button>`, `<.input>`, `<.select>`,
      `<.textarea>`, `<.link>`). Reaching for the raw HTML tag bypasses
      styling tokens, keyboard handling, and the focus-ring conventions that
      those components bake in.

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`. It does NOT flag `<.button>` etc. — only the
      bare-tag forms.

      # Bad

          <button type="submit">Save</button>
          <input name="email" />
          <a href="/">Home</a>

      # Good

          <.button type="submit">Save</.button>
          <.input field={@form[:email]} />
          <.link navigate={~p"/"}>Home</.link>
      """
    ]

  @raw_tags [
    {~r/<button(?=[\s>])/, "<button"},
    {~r/<input(?=[\s>\/])/, "<input"},
    {~r/<textarea(?=[\s>])/, "<textarea"},
    {~r/<select(?=[\s>])/, "<select"},
    {~r/<a(?=[\s>])/, "<a"}
  ]

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
    |> Enum.reduce(ctx, fn {line, idx}, ctx -> check_line({line, line_fn.(idx)}, ctx) end)
  end

  defp check_line({line, line_no}, ctx) do
    Enum.reduce(@raw_tags, ctx, fn {regex, tag}, ctx ->
      if Regex.match?(regex, line) do
        put_issue(ctx, issue_for(ctx, tag, line_no))
      else
        ctx
      end
    end)
  end

  defp issue_for(ctx, tag, line_no) do
    component =
      case tag do
        "<a" -> "<.link>"
        "<button" -> "<.button>"
        "<input" -> "<.input>"
        "<select" -> "<.select>"
        "<textarea" -> "<.textarea>"
      end

    format_issue(ctx,
      message: "Use the `#{component}` component instead of raw `#{tag}>` in HEEx templates.",
      trigger: tag,
      line_no: line_no
    )
  end
end
