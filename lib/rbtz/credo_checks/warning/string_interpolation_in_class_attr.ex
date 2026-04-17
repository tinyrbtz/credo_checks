defmodule Rbtz.CredoChecks.Warning.StringInterpolationInClassAttr do
  use Credo.Check,
    id: "RBTZ0025",
    base_priority: :normal,
    category: :warning,
    explanations: [
      check: """
      Forbids string interpolation inside HEEx `class=` attributes.

      Tailwind's JIT compiler scans source for class names as *literal*
      strings. Constructions like `class={"btn-\#{variant}"}` produce a
      computed class name that Tailwind cannot statically discover, so the
      generated CSS won't include the corresponding utility — the styling
      silently disappears in production.

      Use a map of literal class strings keyed on the dynamic value instead:

          @variants %{
            primary: "bg-blue-600 text-white",
            secondary: "bg-gray-200 text-gray-900"
          }

          <button class={["btn", @variants[@variant]]}>...</button>

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`.

      # Bad

          <button class={"btn-\#{@variant}"}>...</button>
          <div class="px-\#{@size}">...</div>

      # Good

          <button class={["btn", @variants[@variant]]}>...</button>
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

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
    bodies =
      find_bodies(heex, "class={", &HeexSource.capture_interpolation/1) ++
        find_bodies(heex, ~s(class="), &HeexSource.capture_string/1)

    Enum.reduce(bodies, ctx, fn {offset, body}, ctx ->
      if interpolates?(body) do
        put_issue(ctx, issue_for(ctx, line_fn.(offset)))
      else
        ctx
      end
    end)
  end

  defp find_bodies(heex, prefix, capture_fn) do
    heex
    |> :binary.matches(prefix)
    |> Enum.flat_map(fn {start, _len} ->
      open_pos = start + byte_size(prefix)
      rest = binary_part(heex, open_pos, byte_size(heex) - open_pos)

      case capture_fn.(rest) do
        {:ok, body} ->
          offset = heex |> binary_part(0, start) |> HeexSource.count_newlines()
          [{offset, body}]

        :unterminated ->
          []
      end
    end)
  end

  # Detects `#{...}` outside escape contexts. `\#{` is an escape that suppresses
  # interpolation, so we only flag when the `#` is un-escaped.
  defp interpolates?(body), do: scan_interp(body)

  defp scan_interp(<<>>), do: false
  defp scan_interp(<<?\\, _c, rest::binary>>), do: scan_interp(rest)
  defp scan_interp(<<?#, ?{, _rest::binary>>), do: true
  defp scan_interp(<<_c, rest::binary>>), do: scan_interp(rest)

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "Avoid string interpolation in `class=` — Tailwind cannot statically discover " <>
          "computed class names. Use a map of literal classes keyed on the dynamic value.",
      trigger: "class=",
      line_no: line_no
    )
  end
end
