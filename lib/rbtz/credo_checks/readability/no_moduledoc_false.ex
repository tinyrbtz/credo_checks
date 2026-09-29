defmodule Rbtz.CredoChecks.Readability.NoModuledocFalse do
  use Credo.Check,
    id: "RBTZ0061",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Forbids `@moduledoc false`.

      A module either has something worth documenting — add a
      `@moduledoc` — or it doesn't, and then it needs no attribute at all.
      `@moduledoc false` is noise that only exists to satisfy Credo's
      `Readability.ModuleDoc` check, so disable that check alongside this
      one.

      This also hides the module from ExDoc; in an application that isn't
      published, that has no effect. `@doc false` (hiding one public
      function) is unaffected.

      # Bad

          defmodule MyApp.Slug do
            @moduledoc false

            def from_title(title), do: title |> String.downcase() |> String.replace(" ", "-")
          end

      # Good

          defmodule MyApp.Slug do
            def from_title(title), do: title |> String.downcase() |> String.replace(" ", "-")
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  defp walk({:@, meta, [{:moduledoc, _, [false]}]} = ast, ctx) do
    issue =
      format_issue(ctx,
        message:
          "Remove `@moduledoc false` — write a `@moduledoc` if there's something worth saying, " <>
            "otherwise leave the attribute out.",
        trigger: "@moduledoc false",
        line_no: meta[:line]
      )

    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}
end
