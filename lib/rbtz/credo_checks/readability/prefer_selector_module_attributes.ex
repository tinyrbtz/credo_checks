defmodule Rbtz.CredoChecks.Readability.PreferSelectorModuleAttributes do
  use Credo.Check,
    id: "RBTZ0066",
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      functions: [
        element: 1,
        has_element?: 1,
        form: 1,
        "LazyHTML.query": 1,
        "LazyHTML.filter": 1,
        "Floki.find": 1,
        get_text: 1,
        get_attribute: 1,
        element_present?: 1,
        list_text: 1
      ],
      selector_builders: [:by_test_id]
    ],
    explanations: [
      check: """
      Requires CSS / test selectors in tests to be declared as module
      attributes at the top of the test file.

      A named attribute (`@save_button`) says what a selector means, and
      when the markup changes there's one line to update instead of every
      test that repeats the string.

      The check fires in test files (outside `test/support/`) when a
      selector-taking function gets a string literal as its selector, or a
      selector builder such as `by_test_id("save")` is called with a literal
      outside a module attribute. Bare HTML tag names (`"h1"`, `"span"`,
      `"a"`) passed straight to a selector-taking function to scope a lookup
      are allowed.

      The `:functions` param maps each selector-taking function to the
      (0-based) position of its selector argument, counting a piped-in value
      as position 0; remote functions are written as `"Module.function"`.
      `:selector_builders` lists functions whose first argument becomes a
      selector.

      # Bad

          test "saves", %{conn: conn} do
            {:ok, view, _html} = live(conn, ~p"/settings")
            view |> element("#settings-form button[type=submit]") |> render_click()
          end

      # Good

          @save_button "#settings-form button[type=submit]"

          test "saves", %{conn: conn} do
            {:ok, view, _html} = live(conn, ~p"/settings")
            view |> element(@save_button) |> render_click()
          end
      """,
      params: [
        functions:
          "Keyword list of selector-taking functions and the position of their selector argument.",
        selector_builders: "Functions that build a selector from their first argument."
      ]
    ]

  alias Rbtz.CredoChecks.TestSource

  @tag_name ~r/\A[a-z][a-z0-9]*\z/

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if TestSource.test_file?(source_file.filename) and
         not String.contains?(source_file.filename, "test/support/") do
      ctx = Context.build(source_file, params, __MODULE__)

      selector_functions =
        params
        |> Params.get(:functions, __MODULE__)
        |> Map.new(fn {k, v} -> {"#{k}", {v, true}} end)

      builders =
        params
        |> Params.get(:selector_builders, __MODULE__)
        |> Map.new(&{"#{&1}", {0, false}})

      functions = Map.merge(selector_functions, builders)

      {_functions, ctx} = Credo.Code.prewalk(source_file, &walk/2, {functions, ctx})
      ctx.issues
    else
      []
    end
  end

  defp walk({:@, _, [{_name, _, [_value]}]}, acc), do: {nil, acc}

  defp walk({:|>, _, [lhs, {callee, meta, args}]}, {functions, ctx}) when is_list(args) do
    call = {callee, meta, [lhs | args]}
    {call, {functions, check_call(call, functions, ctx)}}
  end

  defp walk(ast, {functions, ctx}), do: {ast, {functions, check_call(ast, functions, ctx)}}

  defp check_call({callee, meta, args}, functions, ctx) when is_list(args) do
    with name when is_binary(name) <- call_name(callee),
         {index, allow_tag?} <- Map.get(functions, name),
         selector when is_binary(selector) <- Enum.at(args, index),
         false <- allow_tag? and Regex.match?(@tag_name, selector) do
      put_issue(ctx, issue_for(ctx, name, selector, meta))
    else
      _ -> ctx
    end
  end

  defp check_call(_ast, _functions, ctx), do: ctx

  defp call_name({:., _, [{:__aliases__, _, parts}, fun]}), do: Enum.join(parts ++ [fun], ".")
  defp call_name(name) when is_atom(name), do: Atom.to_string(name)
  defp call_name(_callee), do: nil

  defp issue_for(ctx, name, selector, meta) do
    format_issue(ctx,
      message:
        "Declare the selector passed to `#{name}` as a module attribute at the top of the " <>
          "test file (e.g. `@save_button #{inspect(selector)}`) instead of inlining it.",
      trigger: selector,
      line_no: meta[:line]
    )
  end
end
