defmodule Rbtz.CredoChecks.Warning.UnnamedOtpProcess do
  use Credo.Check,
    id: "RBTZ0019",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires `DynamicSupervisor` and `Registry` child specs to declare a
      `:name` option.

      Both processes are typically referenced by name from the rest of the
      application: `DynamicSupervisor.start_child(MySupervisor, ...)`,
      `Registry.lookup(MyRegistry, key)`. Starting them anonymously means
      callers must thread the pid through every callsite, and crashes
      replace the pid with a new one — silently breaking every caller that
      cached the old reference.

      The check inspects list literals whose elements all look like child
      specs (bare module aliases or `{Module, opts}` 2-tuples) and flags
      `DynamicSupervisor`/`Registry` entries inside them that lack `:name`
      (or set `name:` to a literal `nil`).

      Map-form child specs (`%{id: ..., start: {M, :start_link, [opts]}}`)
      aren't inspected — they're rare and would require walking inside the
      `:start` MFA tuple.

      # Bad

          children = [
            DynamicSupervisor,
            {Registry, keys: :unique}
          ]

      # Good

          children = [
            {DynamicSupervisor, name: MyApp.WorkerSupervisor},
            {Registry, keys: :unique, name: MyApp.WorkerRegistry}
          ]
      """
    ]

  @processes [:DynamicSupervisor, :Registry]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  defp walk([_ | _] = list, ctx) do
    if child_spec_list?(list) do
      ctx = Enum.reduce(list, ctx, &check_child/2)
      {list, ctx}
    else
      {list, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp child_spec_list?(list) do
    Enum.all?(list, fn
      {:__aliases__, _, _} -> true
      {{:__aliases__, _, _}, opts} when is_list(opts) -> true
      _ -> false
    end)
  end

  defp check_child({:__aliases__, meta, [name]}, ctx) when name in @processes do
    put_issue(ctx, issue_for(ctx, name, meta))
  end

  defp check_child({{:__aliases__, meta, [name]}, opts}, ctx)
       when name in @processes and is_list(opts) do
    if has_usable_name?(opts) do
      ctx
    else
      put_issue(ctx, issue_for(ctx, name, meta))
    end
  end

  defp check_child(_, ctx), do: ctx

  # A literal `name: nil` doesn't meaningfully name the process — treat it as
  # missing. Any other `:name` value (atom, module alias, variable, call)
  # counts as present: the check can't evaluate non-literal expressions and
  # shouldn't second-guess them.
  defp has_usable_name?(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> false
      {:ok, _} -> true
      :error -> false
    end
  end

  defp issue_for(ctx, name, meta) do
    format_issue(ctx,
      message:
        "`#{name}` in a child spec must include `name:`. " <>
          "Anonymous OTP processes break callers when they restart.",
      trigger: to_string(name),
      line_no: meta[:line]
    )
  end
end
