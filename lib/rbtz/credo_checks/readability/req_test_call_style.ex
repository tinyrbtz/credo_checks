defmodule Rbtz.CredoChecks.Readability.ReqTestCallStyle do
  use Credo.Check,
    id: "RBTZ0057",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Enforces the call style Req's own documentation uses for
      `Req.Test.expect` and `Req.Test.stub`: the stub name is the first
      argument, not piped in.

      Piping also invites chaining, which breaks: `Req.Test.stub/2` returns
      `:ok`, not the name.

      The check fires in test files on `Name |> Req.Test.expect(...)` and
      `Name |> Req.Test.stub(...)`.

      # Bad

          MyStub
          |> Req.Test.expect(&Req.Test.json(&1, %{"ok" => true}))

      # Good

          Req.Test.expect(MyStub, &Req.Test.json(&1, %{"ok" => true}))
      """
    ]

  alias Rbtz.CredoChecks.TestSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if TestSource.test_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp walk(
         {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Req, :Test]}, fun]}, meta, _}]} = ast,
         ctx
       )
       when fun in [:expect, :stub] do
    issue =
      format_issue(ctx,
        message:
          "Pass the name as the first argument, as Req's docs do: " <>
            "`Req.Test.#{fun}(Name, ...)`, not `Name |> Req.Test.#{fun}(...)`.",
        trigger: "Req.Test.#{fun}",
        line_no: meta[:line]
      )

    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}
end
