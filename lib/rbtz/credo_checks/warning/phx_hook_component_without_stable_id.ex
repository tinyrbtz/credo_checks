defmodule Rbtz.CredoChecks.Warning.PhxHookComponentWithoutStableId do
  use Credo.Check,
    id: "RBTZ0042",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Requires function components whose template uses `phx-hook` to bind the
      hook target element to a *stable* DOM `id`.

      Phoenix LiveView hooks are keyed by DOM `id`, so every hook target must
      have a stable, unique `id`. If the `id` can be missing or `nil` at
      runtime, multiple instances of the same component collide and LiveView
      can't route `pushEvent`s or maintain the hook across patches.

      A hook target's `id` is considered stable when it is any of:

        * a literal string on the element (`id="phone-number"`),
        * `id={@id}` bound to an attr declared as
          `attr :id, :string, required: true` or
          `attr :id, :string, default: "<literal>"` (binary default), or
        * `id={<expr>}` where the interpolation references only `@<name>`
          assigns that are each themselves declared as a stable-id attr —
          e.g. `id={@id <> "-trigger"}` with `attr :id, :string, required: true`.

      The attr name does not have to be literally `:id` — any name works,
      as long as every `@<name>` referenced inside the `id={...}`
      interpolation is declared with `required: true` or a binary `default:`.

      Anything else — no `id=` on the phx-hook element, a bare `@<name>`
      that isn't declared as a stable-id attr, an `id={...}` expression that
      references no assigns or references an unstable assign, or an attr
      with `default: nil` — is flagged.

      The check walks each module, tracks `attr` declarations preceding each
      `def`, and flags any function whose preceding `attr` block is non-empty
      and whose `~H` template has a phx-hook-carrying element without a
      stable `id` binding.

      # Bad

          attr :class, :string, default: nil
          def phone_number(assigns) do
            ~H\"\"\"
            <div id={@id} phx-hook=".PhoneNumber" class={@class}>...</div>
            \"\"\"
          end

          # `default: nil` doesn't guarantee a stable id
          attr :id, :string, default: nil
          def phone_number(assigns) do
            ~H\"\"\"
            <div id={@id} phx-hook=".PhoneNumber">...</div>
            \"\"\"
          end

      # Good

          attr :id, :string, required: true
          attr :class, :string, default: nil
          def phone_number(assigns) do
            ~H\"\"\"
            <div id={@id} phx-hook=".PhoneNumber" class={@class}>...</div>
            \"\"\"
          end

          # attr has a binary default — `@clear_button_id` is always populated
          attr :clear_button_id, :string, default: "search-clear-button"
          def clear_button(assigns) do
            ~H\"\"\"
            <button id={@clear_button_id} phx-hook="InputClearButton">...</button>
            \"\"\"
          end

          # derived id is fine when every referenced assign is stable
          attr :id, :string, required: true
          def trigger(assigns) do
            ~H\"\"\"
            <button id={@id <> "-trigger"} phx-hook=".Trigger">...</button>
            \"\"\"
          end

          # literal id on the element
          def phone_number(assigns) do
            ~H\"\"\"
            <div id="phone-number" phx-hook=".PhoneNumber">...</div>
            \"\"\"
          end
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, ctx} = Macro.prewalk(ast, ctx, &walk_module/2)
        Enum.reverse(ctx.issues)

      _ ->
        []
    end
  end

  defp walk_module({:defmodule, _meta, [_alias, [do: body]]} = ast, ctx) do
    {ast, scan_body(body, ctx)}
  end

  defp walk_module(ast, ctx), do: {ast, ctx}

  defp scan_body(body, ctx) do
    body
    |> body_statements()
    |> Enum.reduce({[], ctx}, &process_stmt/2)
    |> elem(1)
  end

  defp body_statements({:__block__, _meta, stmts}), do: stmts
  defp body_statements(stmt), do: [stmt]

  defp process_stmt({:attr, _meta, args} = stmt, {attrs, ctx}) when is_list(args) do
    {[stmt | attrs], ctx}
  end

  defp process_stmt({:def, _meta, [name_node, [do: _body]]} = def_ast, {attrs, ctx}) do
    ctx =
      cond do
        attrs == [] -> ctx
        not def_uses_phx_hook?(def_ast) -> ctx
        phx_hook_ids_all_stable?(def_ast, attrs) -> ctx
        true -> put_issue(ctx, issue_for(ctx, name_node))
      end

    {[], ctx}
  end

  defp process_stmt({:def, _meta, _args}, {_attrs, ctx}), do: {[], ctx}
  defp process_stmt({:defp, _meta, _args}, {_attrs, ctx}), do: {[], ctx}
  defp process_stmt(_, state), do: state

  defp def_uses_phx_hook?(def_ast) do
    {_, found?} =
      Macro.prewalk(def_ast, false, fn
        {:sigil_H, _, [{:<<>>, _, parts}, _]} = node, acc when is_list(parts) ->
          {node, acc or Enum.any?(parts, &heex_has_phx_hook?/1)}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp heex_has_phx_hook?(binary) when is_binary(binary), do: String.contains?(binary, "phx-hook")

  # True when every phx-hook-carrying opening tag in any `~H` template under
  # `def_ast` has a stable `id=` binding. An empty result (no such tag found)
  # also counts as stable — the `phx-hook` substring may have appeared inside
  # a comment or string rather than on an actual tag.
  defp phx_hook_ids_all_stable?(def_ast, attrs) do
    def_ast
    |> collect_heex_binaries()
    |> Enum.flat_map(&phx_hook_id_exprs/1)
    |> Enum.all?(&id_expr_stable?(&1, attrs))
  end

  defp collect_heex_binaries(def_ast) do
    {_, acc} =
      Macro.prewalk(def_ast, [], fn
        {:sigil_H, _, [{:<<>>, _, parts}, _]} = node, acc when is_list(parts) ->
          {node, Enum.reduce(parts, acc, fn p, a -> if is_binary(p), do: [p | a], else: a end)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp phx_hook_id_exprs(template) when is_binary(template) do
    template
    |> scan_opening_tag_bodies()
    |> Enum.filter(&String.contains?(&1, "phx-hook"))
    |> Enum.map(&classify_id_expr/1)
  end

  # A small binary state machine that extracts each HTML opening tag's body
  # (the text between `<tagname` and the matching `>`). Strings (`"..."` /
  # `'...'`) and `{...}` interpolations are treated as opaque so that `>`
  # inside them doesn't prematurely close a tag — the naive `[^>]*` regex
  # used elsewhere in this repo misfires on, e.g., `id={"x-" <> @y}`.
  defp scan_opening_tag_bodies(template), do: scan(template, :outside, [], [])

  defp scan(<<>>, _state, _buf, acc), do: Enum.reverse(acc)

  defp scan(<<"<", c, rest::binary>>, :outside, _buf, acc)
       when c in ?a..?z or c in ?A..?Z or c == ?. do
    scan(rest, :in_tag, [<<c>>], acc)
  end

  defp scan(<<_c, rest::binary>>, :outside, _buf, acc),
    do: scan(rest, :outside, [], acc)

  defp scan(<<?", rest::binary>>, :in_tag, buf, acc),
    do: scan(rest, {:in_str, ?"}, [~s(") | buf], acc)

  defp scan(<<"'", rest::binary>>, :in_tag, buf, acc),
    do: scan(rest, {:in_str, ?'}, ["'" | buf], acc)

  defp scan(<<"{", rest::binary>>, :in_tag, buf, acc),
    do: scan(rest, {:in_brace, 1}, ["{" | buf], acc)

  defp scan(<<">", rest::binary>>, :in_tag, buf, acc) do
    body = buf |> Enum.reverse() |> IO.iodata_to_binary()
    scan(rest, :outside, [], [body | acc])
  end

  defp scan(<<c, rest::binary>>, :in_tag, buf, acc),
    do: scan(rest, :in_tag, [<<c>> | buf], acc)

  defp scan(<<c, rest::binary>>, {:in_str, c}, buf, acc),
    do: scan(rest, :in_tag, [<<c>> | buf], acc)

  defp scan(<<c, rest::binary>>, {:in_str, q}, buf, acc),
    do: scan(rest, {:in_str, q}, [<<c>> | buf], acc)

  defp scan(<<"{", rest::binary>>, {:in_brace, d}, buf, acc),
    do: scan(rest, {:in_brace, d + 1}, ["{" | buf], acc)

  defp scan(<<"}", rest::binary>>, {:in_brace, 1}, buf, acc),
    do: scan(rest, :in_tag, ["}" | buf], acc)

  defp scan(<<"}", rest::binary>>, {:in_brace, d}, buf, acc),
    do: scan(rest, {:in_brace, d - 1}, ["}" | buf], acc)

  defp scan(<<c, rest::binary>>, {:in_brace, d}, buf, acc),
    do: scan(rest, {:in_brace, d}, [<<c>> | buf], acc)

  defp classify_id_expr(tag_body) do
    cond do
      Regex.match?(~r/(?:^|\s)id\s*=\s*"[^"]*"/, tag_body) -> :literal_string
      Regex.match?(~r/(?:^|\s)id\s*=\s*'[^']*'/, tag_body) -> :literal_string
      true -> classify_interp_id(tag_body)
    end
  end

  defp classify_interp_id(tag_body) do
    case Regex.run(~r/(?:^|\s)id\s*=\s*\{\s*@([a-z_][a-zA-Z0-9_]*)\s*\}/, tag_body) do
      [_, name] ->
        {:assign, String.to_atom(name)}

      nil ->
        case extract_id_interp_body(tag_body) do
          nil -> :missing
          content -> {:complex_assigns, assign_refs(content)}
        end
    end
  end

  # Locates the `id=\{...}` region in the tag body and returns the body
  # between the braces, handling nested braces. Returns `nil` if there is
  # no `id=\{` on this tag.
  defp extract_id_interp_body(tag_body) do
    case Regex.run(~r/(?:^|\s)id\s*=\s*\{/, tag_body, return: :index) do
      [{start, len}] ->
        from = start + len
        rest = binary_part(tag_body, from, byte_size(tag_body) - from)
        take_balanced(rest, 1, [])

      nil ->
        nil
    end
  end

  defp take_balanced(<<"}", _rest::binary>>, 1, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp take_balanced(<<"{", rest::binary>>, d, acc),
    do: take_balanced(rest, d + 1, ["{" | acc])

  defp take_balanced(<<"}", rest::binary>>, d, acc),
    do: take_balanced(rest, d - 1, ["}" | acc])

  defp take_balanced(<<c, rest::binary>>, d, acc),
    do: take_balanced(rest, d, [<<c>> | acc])

  defp assign_refs(content) do
    ~r/@([a-z_][a-zA-Z0-9_]*)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> String.to_atom(name) end)
    |> Enum.uniq()
  end

  defp id_expr_stable?(:literal_string, _attrs), do: true
  defp id_expr_stable?({:assign, name}, attrs), do: stable_id_provider?(attrs, name)
  defp id_expr_stable?({:complex_assigns, []}, _attrs), do: false

  defp id_expr_stable?({:complex_assigns, names}, attrs),
    do: Enum.all?(names, &stable_id_provider?(attrs, &1))

  defp id_expr_stable?(:missing, _attrs), do: false

  defp stable_id_provider?(attrs, name) do
    Enum.any?(attrs, fn
      {:attr, _, [^name, :string, opts]} when is_list(opts) ->
        Keyword.get(opts, :required) == true or
          (Keyword.has_key?(opts, :default) and is_binary(Keyword.get(opts, :default)))

      _ ->
        false
    end)
  end

  defp issue_for(ctx, name_node) do
    {name, line_no} = name_info(name_node)

    format_issue(ctx,
      message:
        "Component `#{name}/1` uses `phx-hook` in its template but the hook target " <>
          ~s(does not have a stable `id`. Give the element a literal `id="..."`, or ) <>
          "bind `id={@id}` to an attr declared as `attr :id, :string, required: true` " <>
          ~s(or `attr :id, :string, default: "<literal>"`. Without a stable id, ) <>
          "LiveView cannot route `pushEvent`s or maintain the hook across patches.",
      trigger: to_string(name),
      line_no: line_no
    )
  end

  defp name_info({:when, _, [inner | _]}), do: name_info(inner)
  defp name_info({name, meta, _}) when is_atom(name), do: {name, meta[:line]}
end
