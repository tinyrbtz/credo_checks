defmodule Rbtz.CredoChecks.Refactor.PreferToFormInTemplates do
  use Credo.Check,
    id: "RBTZ0030",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Forbids passing a raw `@changeset` to a `<form>` / `<.form>` in HEEx —
      always wrap the changeset with `to_form/2` first and pass the resulting
      `@form`.

      `Phoenix.Component.to_form/2` builds a `Phoenix.HTML.Form` struct that
      knows how to render input names, attach errors per-field, derive a stable
      `id`, and round-trip values through `phx-change`. Passing the changeset
      directly skips all of that: errors won't appear next to the right inputs,
      `<.input field={...}>` cannot resolve the field name, and form recovery
      breaks on reconnect.

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`. It tracks when the cursor is inside a
      `<form>`/`<.form>` element and flags any `@changeset` reference in that
      scope.

      # Bad

          <.form for={@changeset} phx-submit="save">
            <.input field={@changeset[:name]} />
          </.form>

      # Good

          # In the LiveView:
          {:ok, assign(socket, :form, to_form(changeset))}

          # In the template:
          <.form for={@form} phx-submit="save">
            <.input field={@form[:name]} />
          </.form>
      """
    ]

  @form_open_patterns [~r/<form\b/, ~r/<\.form\b/, ~r/<Form\.form\b/]
  @form_close_patterns [~r/<\/form>/, ~r/<\/\.form>/, ~r/<\/Form\.form>/]
  @changeset_pattern ~r/@changeset\b/

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
    |> Enum.reduce({0, ctx}, fn {line, idx}, {depth, ctx} ->
      line_no = line_fn.(idx)
      depth_after = depth + line_open_count(line) - line_close_count(line)
      in_scope_during_line = depth > 0 or line_open_count(line) > 0

      ctx =
        if in_scope_during_line and Regex.match?(@changeset_pattern, line) do
          put_issue(ctx, issue_for(ctx, line_no))
        else
          ctx
        end

      {depth_after, ctx}
    end)
    |> elem(1)
  end

  defp line_open_count(line) do
    Enum.reduce(@form_open_patterns, 0, fn rx, acc ->
      acc + length(Regex.scan(rx, line))
    end)
  end

  defp line_close_count(line) do
    Enum.reduce(@form_close_patterns, 0, fn rx, acc ->
      acc + length(Regex.scan(rx, line))
    end)
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "Wrap the changeset with `to_form/2` and pass `@form` to the form instead of `@changeset`. " <>
          "Direct changeset access in templates breaks input field resolution, error placement, and form recovery.",
      trigger: "@changeset",
      line_no: line_no
    )
  end
end
