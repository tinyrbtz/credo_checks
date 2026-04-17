defmodule Rbtz.CredoChecks.Warning.BooleanDataAttrCoalescesNil do
  use Credo.Check,
    id: "RBTZ0037",
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      names: ~w(
        active busy checked collapsed disabled enabled expanded focus
        hidden hover invalid loading open pressed readonly required
        selected valid visible
      )
    ],
    explanations: [
      check: """
      Requires boolean `data-*` attributes to coalesce with `nil` (or
      `false`) so the attribute is omitted from the DOM when falsy, not
      rendered as `data-disabled=""`.

      Given `<div data-disabled={@disabled}>`, when `@disabled` is `false`
      Phoenix still emits the attribute as an empty string —
      `data-disabled=""`. Tailwind's boolean data-attribute variant
      (`data-disabled:...`) matches on presence, so the empty form triggers
      the variant unintentionally. Writing `{@disabled || nil}` lets
      Phoenix skip the attribute entirely when falsy.

      The check scans HEEx templates for attributes whose name is in the
      configured boolean list (`disabled`, `open`, `selected`, …) and whose
      value is a bare expression (just `@assign` or a variable, with no
      `||` / `&&` / string literal / `nil`). Add new names via
      `:names` in `.credo.exs`.

      Detection is line-by-line: a `data-*={...}` body split across multiple
      source lines is not inspected (the Elixir formatter keeps these on one
      line in practice).

      # Bad

          <div data-disabled={@disabled}>...</div>
          <div data-open={open?}>...</div>

      # Good

          <div data-disabled={@disabled || nil}>...</div>
          <div data-open={open? && "true"}>...</div>
      """,
      params: [
        names: "List of boolean data-attribute name suffixes to scan."
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    names = Params.get(params, :names, __MODULE__)

    source_file
    |> Rbtz.CredoChecks.HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template(&1, &2, names))
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx, names) do
    regex = build_regex(names)

    heex
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce(ctx, fn {line, idx}, ctx ->
      line_no = line_fn.(idx)

      regex
      |> Regex.scan(line, capture: :all_but_first)
      |> Enum.reduce(ctx, &flag_match(&2, line_no, &1))
    end)
  end

  defp flag_match(ctx, line_no, [name, body]) do
    if bare_expr?(body) do
      put_issue(ctx, issue_for(ctx, line_no, name, body))
    else
      ctx
    end
  end

  defp build_regex(names) do
    alt = Enum.map_join(names, "|", &Regex.escape/1)
    Regex.compile!("data-(#{alt})=\\{([^{}]*)\\}")
  end

  @bare_expr_re ~r/^@?[a-zA-Z_][a-zA-Z0-9_]*[?!]?$/

  # A bare expression is `@assign` or a plain variable — anything else
  # (function call, operator expression, literal) is assumed intentional.
  defp bare_expr?(body) do
    trimmed = String.trim(body)
    String.match?(trimmed, @bare_expr_re) and trimmed not in ~w(nil true false)
  end

  defp issue_for(ctx, line_no, name, body) do
    body = String.trim(body)

    format_issue(ctx,
      message:
        "Boolean `data-#{name}` attribute should coalesce to nil when falsy — write " <>
          "`data-#{name}={#{body} || nil}` so the attribute is omitted from the DOM.",
      trigger: "data-#{name}={#{body}}",
      line_no: line_no
    )
  end
end
