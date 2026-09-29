defmodule Rbtz.CredoChecks.Readability.MimicCallStyle do
  use Credo.Check,
    id: "RBTZ0056",
    base_priority: :normal,
    category: :readability,
    param_defaults: [detect_dependency: true],
    explanations: [
      check: """
      Enforces the call style Mimic's own documentation uses for test
      doubles, so every test sets them up the same way.

      `expect` and `stub` take the module piped in, which lets several
      doubles for one module chain together. `reject` takes a function
      capture.

      The check fires in test files on:

        * `expect(Module, :fun, ...)` / `stub(Module, :fun, ...)` — pipe the
          module in instead
        * `reject(:fun, arity)` (usually written `Module |> reject(:fun,
          arity)`) and `reject(Module, :fun, arity)` — use
          `reject(&Module.fun/arity)`

      `Mimic.`-qualified calls are flagged the same way. `stub(Module)`,
      which stubs every function in the module, is left alone.

      The check only runs when the project depends on `:mimic` — Mox and
      Hammox import `expect` / `stub` with the same shape, and their docs use
      the unpiped form. The project counts as depending on Mimic when its
      `mix.exs` lists `:mimic` in any environment (Credo only loads the
      current environment's deps, so an `only: :test` dep isn't loadable
      under `:dev`) or when the `Mimic` module is loadable.

      # Bad

          expect(File, :read, fn _ -> {:ok, "contents"} end)
          stub(File, :exists?, fn _ -> true end)

          File |> reject(:write, 2)

      # Good

          File
          |> expect(:read, fn _ -> {:ok, "contents"} end)
          |> stub(:exists?, fn _ -> true end)

          reject(&File.write/2)
      """,
      params: [
        detect_dependency:
          "Only run when the project depends on `:mimic`. Set to `false` to always run, " <>
            "e.g. in an umbrella whose root `mix.exs` doesn't list the dependency."
      ]
    ]

  alias Rbtz.CredoChecks.TestSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if TestSource.test_file?(source_file.filename) and mimic_present?(params) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    else
      []
    end
  end

  defp mimic_present?(params) do
    not Params.get(params, :detect_dependency, __MODULE__) or declares_mimic?() or
      Code.ensure_loaded?(Mimic)
  end

  defp declares_mimic? do
    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Enum.any?(&(elem(&1, 0) == :mimic))
  end

  defp walk({{:., _, [{:__aliases__, _, [:Mimic]}, fun]}, meta, args} = ast, ctx),
    do: walk({fun, meta, args}, ast, ctx)

  defp walk({fun, _meta, args} = ast, ctx) when is_atom(fun) and is_list(args),
    do: walk(ast, ast, ctx)

  defp walk(ast, ctx), do: {ast, ctx}

  defp walk({fun, meta, [module, name | _]}, ast, ctx)
       when fun in [:expect, :stub] and is_atom(name) do
    if module_ref?(module) do
      {ast, put_issue(ctx, pipe_issue(ctx, fun, meta))}
    else
      {ast, ctx}
    end
  end

  defp walk({:reject, meta, [name, arity]}, ast, ctx)
       when is_atom(name) and is_integer(arity),
       do: {ast, put_issue(ctx, capture_issue(ctx, meta))}

  defp walk({:reject, meta, [module, name, arity]}, ast, ctx)
       when is_atom(name) and is_integer(arity) do
    if module_ref?(module) do
      {ast, put_issue(ctx, capture_issue(ctx, meta))}
    else
      {ast, ctx}
    end
  end

  defp walk(_call, ast, ctx), do: {ast, ctx}

  defp module_ref?({:__aliases__, _, _}), do: true
  defp module_ref?({:__MODULE__, _, ctx}) when is_atom(ctx), do: true
  defp module_ref?(module), do: is_atom(module)

  defp pipe_issue(ctx, fun, meta) do
    format_issue(ctx,
      message:
        "Pipe the module into `#{fun}`, as Mimic's docs do: `Module |> #{fun}(:fun, ...)`.",
      trigger: "#{fun}",
      line_no: meta[:line]
    )
  end

  defp capture_issue(ctx, meta) do
    format_issue(ctx,
      message:
        "Pass `reject` a function capture, as Mimic's docs do: `reject(&Module.fun/arity)`.",
      trigger: "reject",
      line_no: meta[:line]
    )
  end
end
