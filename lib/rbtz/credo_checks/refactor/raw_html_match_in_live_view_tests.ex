defmodule Rbtz.CredoChecks.Refactor.RawHtmlMatchInLiveViewTests do
  use Credo.Check,
    id: "RBTZ0014",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Forbids `html =~ "..."` assertions in test files.

      Asserting that a rendered HTML blob *contains* a particular string is
      brittle: any markup change (whitespace, attribute reordering, classname
      tweak) can flip the test red without the user-visible behaviour having
      changed. Worse, it tends to test that the string appears *somewhere*,
      not that the right element rendered the right text.

      Prefer selecting a specific element (by `id`, `data-test`, or other
      stable selector) and asserting on its text content via the project's
      DOM helpers (`get_text/2`, `has_element?/2`, etc.).

      The check fires on `=~ "string literal"` when the left-hand side is one
      of:

        * the bare variable `html`
        * a call to `render(...)` (e.g. `render(view)`)
        * a pipe ending in `render(...)` (e.g. `view |> render()`)

      Other `=~` usages (e.g. `log =~ "..."` against captured logs) are left
      alone, as is any regex match (`html =~ ~r/.../`).

      # Bad

          {:ok, view, html} = live(conn, "/users")
          assert html =~ "Welcome, Alice"
          assert render(view) =~ "Welcome, Alice"
          assert view |> render() =~ "Welcome, Alice"

      # Good

          @greeting_css "[data-test=greeting]"

          {:ok, view, _html} = live(conn, "/users")
          assert get_text(view, @greeting_css) == "Welcome, Alice"
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if test_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp test_file?(filename) when is_binary(filename) do
    expanded = Path.expand(filename)
    String.ends_with?(filename, "_test.exs") or String.contains?(expanded, "/test/")
  end

  defp test_file?(_), do: false

  defp walk({:=~, meta, [lhs, rhs]} = ast, acc) when is_binary(rhs) do
    if trigger = rendered_html_trigger(lhs) do
      {ast, put_issue(acc, issue_for(acc, meta, trigger))}
    else
      {ast, acc}
    end
  end

  defp walk(ast, acc), do: {ast, acc}

  defp rendered_html_trigger({:html, _, ctx}) when is_atom(ctx), do: "html =~"
  defp rendered_html_trigger({:render, _, _args}), do: "render(...) =~"
  defp rendered_html_trigger({:|>, _, [_, {:render, _, _}]}), do: "|> render() =~"
  defp rendered_html_trigger(_), do: nil

  defp issue_for(ctx, meta, trigger) do
    format_issue(ctx,
      message:
        ~s(Avoid `#{trigger} "..."` against rendered HTML in tests. ) <>
          "Select a specific element (e.g. by `data-test`) and assert on its text instead.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
