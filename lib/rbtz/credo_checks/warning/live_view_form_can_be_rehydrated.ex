defmodule Rbtz.CredoChecks.Warning.LiveViewFormCanBeRehydrated do
  use Credo.Check,
    id: "RBTZ0003",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Ensures that LiveView forms (i.e. forms with `phx-submit`) carry both an
      `id` attribute and a `phx-change` attribute.

      Without these two attributes, LiveView cannot rehydrate the form's state
      across reconnects or live patches: the user's input is silently lost when
      the form is re-rendered. The `id` lets LiveView identify the form across
      renders, and `phx-change` keeps the server-side form data in sync with
      the user's keystrokes so it can be replayed.

      Forms without `phx-submit` are not driven by LiveView and are exempt.

      # Bad

          <.form for={@form} phx-submit="save">
            <.input field={@form[:name]} />
          </.form>

          <form phx-submit="save">
            <input name="name" />
          </form>

      # Good

          <.form for={@form} id="profile-form" phx-submit="save" phx-change="validate">
            <.input field={@form[:name]} />
          </.form>

      The check scans `~H` sigils and `.heex` template files referenced by
      `embed_templates`.
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  @form_tag_patterns [
    {~r/<form\b/, "<form"},
    {~r/<Form\.form\b/, "<Form.form"},
    {~r/<\.form\b/, "<.form"}
  ]

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

  defp scan_template(template, ctx) do
    template
    |> HeexSource.walk_tags(
      &detect_form_open/1,
      id: &HeexSource.has_id?/1,
      phx_change: &String.contains?(&1, "phx-change"),
      phx_submit: &String.contains?(&1, "phx-submit")
    )
    |> Enum.reduce(ctx, fn {open_line, trigger, presence}, ctx ->
      build_issue(ctx, trigger, open_line, presence)
    end)
  end

  defp build_issue(ctx, trigger, line_no, %{phx_submit: true, id: has_id, phx_change: has_chg})
       when not (has_id and has_chg) do
    put_issue(ctx, issue_for(ctx, trigger, line_no, has_id, has_chg))
  end

  defp build_issue(ctx, _trigger, _line_no, _presence), do: ctx

  defp detect_form_open(line) do
    Enum.find_value(@form_tag_patterns, fn {regex, trigger} ->
      case Regex.run(regex, line, return: :index) do
        [{start, len}] ->
          rest = String.slice(line, (start + len)..-1//1)
          {trigger, rest}

        _ ->
          nil
      end
    end)
  end

  defp issue_for(ctx, trigger, line_no, has_id, has_chg) do
    missing =
      [{has_id, "id"}, {has_chg, "phx-change"}]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map_join(", ", &elem(&1, 1))

    format_issue(ctx,
      message:
        "Form with `phx-submit` is missing `#{missing}`. " <>
          "Without these attributes, LiveView cannot rehydrate the form across reconnects or live patches.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
