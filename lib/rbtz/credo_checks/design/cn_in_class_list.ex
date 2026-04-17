defmodule Rbtz.CredoChecks.Design.CnInClassList do
  use Credo.Check,
    id: "RBTZ0033",
    base_priority: :normal,
    category: :design,
    param_defaults: [helper_name: "cn"],
    explanations: [
      check: """
      Enforces correct use of the `cn(...)` class-merging helper in HEEx
      `class={...}` attributes alongside caller-provided assigns (`@class`,
      `@color`, `@size_class`, …).

      `cn/1` (or whatever helper your project uses to wrap `TwMerge.merge/1`)
      exists to deduplicate Tailwind classes when a parent overrides a child's
      defaults — e.g. `<.button class="w-full">` should win over the button's
      built-in `w-auto`. That overhead is wasted when there's nothing to merge,
      skipped (with broken overrides) when assigns are concatenated into a bare
      list, and silently defeated when assigns aren't listed last inside
      `cn(...)` — TwMerge resolves conflicts by keeping the *last* value.

      Three rules are enforced on every HEEx `class={...}` attribute:

        1. **`cn(...)` requires an assign.** A literal `cn([...])` call whose
           arguments don't contain any `@assign` is wasted — use a bare list
           (`class={[...]}`) instead.

        2. **A bare list mixing literal classes with an assign requires
           `cn(...)`.** A bare list `class={["a", "b", @color]}` will not dedupe
           when `@color` overlaps with a sibling — wrap with `cn([...])` so
           TwMerge can merge.

        3. **Inside `cn(...)`, assigns must come after all literal classes.**
           `cn([@color, "text-sm"])` silently loses the `@color` override
           because TwMerge keeps the later value — assigns must be listed last.

      Solo assign (`class={@class}`, `class={[@color]}`) is fine — there's
      nothing to merge.

      The helper name is configurable via the `:helper_name` param
      (default `"cn"`).

      # Bad — `cn` without any assign

          <div class={cn(["rounded border p-2"])}>...</div>

      # Bad — assign mixed with siblings in a bare list

          <div class={[
            "flex w-full items-center",
            "py-4 text-sm font-medium",
            @class
          ]}>...</div>

      # Bad — assign not last inside `cn(...)`

          <div class={cn([@color, "rounded border p-2"])}>...</div>

      # Good

          <div class={["rounded border p-2"]}>...</div>

          <div class={cn([
            "flex w-full items-center",
            "py-4 text-sm font-medium",
            @class
          ])}>...</div>

          <div class={@class}>...</div>

          # An `@assign` used only as a condition in a nested expression is
          # fine — the list elements resolve to literal strings, so there's
          # no caller-provided class to merge.
          <div class={[
            "rounded border",
            if(@compact, do: "p-1", else: "p-4")
          ]}>...</div>
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    helper_name = Params.get(params, :helper_name, __MODULE__)
    helper_atom = String.to_atom(helper_name)
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template(&1, &2, helper_name, helper_atom))
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx, helper_name, helper_atom) do
    heex
    |> find_class_attrs(line_fn)
    |> Enum.reduce(ctx, fn {line_no, content}, ctx ->
      scan_class_expr(ctx, content, line_no, helper_name, helper_atom)
    end)
  end

  defp scan_class_expr(ctx, content, line_no, helper_name, helper_atom) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        ctx
        |> maybe_flag_unwrapped(ast, line_no, helper_name)
        |> walk_helper_calls(ast, line_no, helper_name, helper_atom)

      _ ->
        ctx
    end
  end

  # Rule: a bare list with an assign and literal siblings must be wrapped in the helper.
  # Only top-level list elements count — `@assign` buried inside another expression
  # (e.g. `if(@variant, do: "a", else: "b")`) is a condition, not a class source.
  defp maybe_flag_unwrapped(ctx, ast, line_no, helper_name) do
    case ast do
      list when is_list(list) ->
        if length(list) > 1 and Enum.any?(list, &assign?/1) do
          put_issue(ctx, issue_for_unwrapped(ctx, line_no, helper_name))
        else
          ctx
        end

      _ ->
        ctx
    end
  end

  # Walks every literal `helper(...)` call and applies Rules 1 and 3.
  defp walk_helper_calls(ctx, ast, line_no, helper_name, helper_atom) do
    {_ast, ctx} =
      Macro.prewalk(ast, ctx, fn
        {^helper_atom, _meta, args} = node, ctx when is_list(args) ->
          {node, check_helper_call(ctx, args, line_no, helper_name)}

        {{:., _, [_mod, ^helper_atom]}, _meta, args} = node, ctx when is_list(args) ->
          {node, check_helper_call(ctx, args, line_no, helper_name)}

        node, ctx ->
          {node, ctx}
      end)

    ctx
  end

  defp check_helper_call(ctx, args, line_no, helper_name) do
    ctx
    |> maybe_flag_unneeded(args, line_no, helper_name)
    |> maybe_flag_misordered(args, line_no, helper_name)
  end

  # Rule: a `helper(...)` call whose args are pure literals has nothing to merge.
  # `args_are_literal?` already implies no `@assign` is present, since `@foo` AST
  # is never a literal.
  defp maybe_flag_unneeded(ctx, args, line_no, helper_name) do
    if args_are_literal?(args) do
      put_issue(ctx, issue_for_unneeded(ctx, line_no, helper_name))
    else
      ctx
    end
  end

  # Rule: inside `helper(list)`, no literal may appear after an `@assign`.
  defp maybe_flag_misordered(ctx, args, line_no, helper_name) do
    case args do
      [list] when is_list(list) ->
        if misordered_assigns?(list) do
          put_issue(ctx, issue_for_misordered(ctx, line_no, helper_name))
        else
          ctx
        end

      _ ->
        ctx
    end
  end

  defp misordered_assigns?(elements) do
    Enum.reduce_while(elements, false, fn elem, seen_assign? ->
      cond do
        assign?(elem) -> {:cont, true}
        seen_assign? and literal?(elem) -> {:halt, :violation}
        true -> {:cont, seen_assign?}
      end
    end) == :violation
  end

  defp assign?({:@, _, [{name, _, ctx}]}) when is_atom(name) and is_atom(ctx), do: true
  defp assign?(_), do: false

  # Only flag `helper(...)` calls whose args are pure literals —
  # nested lists/strings/atoms/numbers. Any `@assign`, slot access
  # (`tab[:class]`), variable, or function call might dynamically be a
  # caller-provided class, so we leave it alone.
  defp args_are_literal?(args) when is_list(args), do: Enum.all?(args, &literal?/1)

  defp literal?(list) when is_list(list), do: Enum.all?(list, &literal?/1)
  defp literal?(binary) when is_binary(binary), do: true
  defp literal?(number) when is_number(number), do: true
  defp literal?(atom) when is_atom(atom), do: true
  defp literal?({left, right}), do: literal?(left) and literal?(right)

  defp literal?({:{}, _meta, elements}) when is_list(elements),
    do: Enum.all?(elements, &literal?/1)

  defp literal?(_), do: false

  defp issue_for_unwrapped(ctx, line_no, helper_name) do
    format_issue(ctx,
      message:
        "A caller-provided assign is being merged with other classes in a bare list — " <>
          "wrap with `#{helper_name}([..., @assign])` so TwMerge can dedupe overlapping " <>
          "Tailwind utilities.",
      trigger: "class={",
      line_no: line_no
    )
  end

  defp issue_for_unneeded(ctx, line_no, helper_name) do
    format_issue(ctx,
      message:
        "`#{helper_name}/1` has nothing to merge — its arguments don't include any `@assign`. " <>
          "Use a bare list instead: `class={[...]}`.",
      trigger: "#{helper_name}(",
      line_no: line_no
    )
  end

  defp issue_for_misordered(ctx, line_no, helper_name) do
    format_issue(ctx,
      message:
        "Caller-provided assigns in `#{helper_name}(...)` must come after all literal classes — " <>
          "TwMerge keeps the last value, so assigns listed before literals lose their override.",
      trigger: "#{helper_name}(",
      line_no: line_no
    )
  end

  defp find_class_attrs(heex, line_fn) do
    heex
    |> :binary.matches("class={")
    |> Enum.flat_map(fn {start, _len} ->
      open_pos = start + byte_size("class={")
      rest = binary_part(heex, open_pos, byte_size(heex) - open_pos)

      case HeexSource.capture_interpolation(rest) do
        {:ok, content} ->
          line_no = heex |> binary_part(0, start) |> HeexSource.count_newlines() |> line_fn.()
          [{line_no, content}]

        :unterminated ->
          []
      end
    end)
  end
end
