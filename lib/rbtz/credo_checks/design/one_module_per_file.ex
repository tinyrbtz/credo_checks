defmodule Rbtz.CredoChecks.Design.OneModulePerFile do
  use Credo.Check,
    id: "RBTZ0059",
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Requires one module per file under `lib/`.

      Extra modules in a file — nested inside the main one or alongside
      it — are hard to find from their name, and nesting modules that
      reference each other invites cyclic compile-time dependencies.

      Exception and struct modules may stay with the module that owns
      them: any extra module that calls `defexception`, and any whose body
      is only a `defstruct` plus attributes, is allowed. Modules generated
      inside `quote` blocks are ignored, as are files outside `lib/` (tests
      often define small fake modules inline).

      # Bad

          # lib/my_app/parser.ex
          defmodule MyApp.Parser do
            def parse(input), do: MyApp.Parser.Tokenizer.tokenize(input)

            defmodule Tokenizer do
              def tokenize(input), do: String.split(input)
            end
          end

      # Good

          # lib/my_app/parser.ex
          defmodule MyApp.Parser do
            def parse(input), do: MyApp.Parser.Tokenizer.tokenize(input)

            defmodule Error do
              defexception [:message]
            end
          end

          # lib/my_app/parser/tokenizer.ex
          defmodule MyApp.Parser.Tokenizer do
            def tokenize(input), do: String.split(input)
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if lib_file?(source_file.filename) do
      ctx = Context.build(source_file, params, __MODULE__)
      {_seen, ctx} = Credo.Code.prewalk(source_file, &walk/2, {false, ctx})
      ctx.issues
    else
      []
    end
  end

  defp lib_file?(filename), do: filename |> Path.expand() |> Path.split() |> Enum.member?("lib")

  defp walk({:quote, _, _}, acc), do: {nil, acc}

  defp walk({:defmodule, meta, [name, [do: body]]} = ast, {seen, ctx}) do
    if seen and not (exception_module?(body) or struct_module?(body)) do
      {ast, {seen, put_issue(ctx, issue_for(ctx, name, meta))}}
    else
      {ast, {true, ctx}}
    end
  end

  defp walk(ast, acc), do: {ast, acc}

  defp exception_module?(body),
    do: body |> block_exprs() |> Enum.any?(&match?({:defexception, _, _}, &1))

  defp struct_module?(body) do
    exprs = block_exprs(body)

    Enum.any?(exprs, &match?({:defstruct, _, _}, &1)) and
      Enum.all?(exprs, &match?({call, _, _} when call in [:@, :defstruct], &1))
  end

  defp block_exprs({:__block__, _, exprs}), do: exprs
  defp block_exprs(expr), do: [expr]

  defp issue_for(ctx, name, meta) do
    trigger = Macro.to_string(name)

    format_issue(ctx,
      message: "Move `#{trigger}` into its own file — keep one module per file under `lib/`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
