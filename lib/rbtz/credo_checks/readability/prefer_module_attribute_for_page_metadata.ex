defmodule Rbtz.CredoChecks.Readability.PreferModuleAttributeForPageMetadata do
  use Credo.Check,
    id: "RBTZ0065",
    base_priority: :normal,
    category: :readability,
    param_defaults: [keys: [:page_title, :page_description]],
    explanations: [
      check: """
      Requires static page metadata (`page_title`, `page_description`) to be
      declared as module attributes and assigned from there.

      A `@page_title` at the top of the LiveView or controller makes the
      page's identity visible at a glance and keeps the string in one place
      when several callbacks assign it.

      The check fires when `assign` or `render` is given a string literal for
      one of the configured keys — as a keyword (`page_title: "..."`), a map
      entry, or `assign(socket, :page_title, "...")`. Interpolated strings
      and computed values (e.g. `gettext("...")`) are left alone.

      # Bad

          def mount(_params, _session, socket) do
            {:ok, assign(socket, page_title: "Settings")}
          end

      # Good

          @page_title "Settings"

          def mount(_params, _session, socket) do
            {:ok, assign(socket, page_title: @page_title)}
          end
      """,
      params: [keys: "Assign keys whose static values must come from module attributes."]
    ]

  @calls [:assign, :render]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    keys = Params.get(params, :keys, __MODULE__)
    {_keys, ctx} = Credo.Code.prewalk(source_file, &walk/2, {keys, ctx})
    ctx.issues
  end

  defp walk({:|>, _, [lhs, {callee, meta, args}]}, {keys, ctx}) when is_list(args) do
    call = {callee, meta, [lhs | args]}
    {call, {keys, check_call(call, keys, ctx)}}
  end

  defp walk(ast, {keys, ctx}), do: {ast, {keys, check_call(ast, keys, ctx)}}

  defp check_call({callee, meta, [_ | args]}, keys, ctx) when is_list(args) do
    if call_name(callee) in @calls do
      args
      |> literal_keys(keys)
      |> Enum.reduce(ctx, &put_issue(&2, issue_for(&2, &1, meta)))
    else
      ctx
    end
  end

  defp check_call(_ast, _keys, ctx), do: ctx

  defp call_name({:., _, [_module, name]}), do: name
  defp call_name(name), do: name

  defp literal_keys([key, value | _], keys) when is_atom(key) and is_binary(value),
    do: if(key in keys, do: [key], else: [])

  defp literal_keys(args, keys) do
    for arg <- args,
        {key, value} <- pairs(arg),
        key in keys and is_binary(value),
        do: key
  end

  defp pairs({:%{}, _, pairs}), do: pairs
  defp pairs(list) when is_list(list), do: Enum.filter(list, &match?({_, _}, &1))
  defp pairs(_arg), do: []

  defp issue_for(ctx, key, meta) do
    format_issue(ctx,
      message:
        ~s|Declare the static `#{key}` as a module attribute (`@#{key} "..."`) and assign | <>
          "`#{key}: @#{key}`.",
      trigger: "#{key}",
      line_no: meta[:line]
    )
  end
end
