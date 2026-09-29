defmodule Rbtz.CredoChecks.Readability.PreferDateTimeShift do
  use Credo.Check,
    id: "RBTZ0058",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Prefers `DateTime.shift/2` (and the `NaiveDateTime` / `Date` / `Time`
      equivalents) for calendar arithmetic, reserving `add/3` for genuine
      second / millisecond offsets.

      `shift` states the unit in the call (`day: -7`), where `add` hides it
      in a unit atom or a multiplication by 60 / 3600 / 86400.

      The check fires on `DateTime.add`, `NaiveDateTime.add`, and
      `Time.add` when:

        * the unit is `:minute`, `:hour`, `:day`, or `:week`
        * the unit is `:second` (or omitted) and the amount is a
          multiplication by 60, 3600, 86400, or 604800, or a literal
          multiple of 60

      It also fires on every `Date.add/2`: a date offset is always in days,
      so `Date.shift(date, day: n)` says the same thing and extends to weeks
      and months.

      # Bad

          DateTime.add(now, -7, :day)
          DateTime.add(now, 2 * 3600)
          NaiveDateTime.add(now, 300, :second)
          Date.add(today, -1)

      # Good

          DateTime.shift(now, day: -7)
          DateTime.shift(now, hour: 2)
          NaiveDateTime.shift(now, minute: 5)
          Date.shift(today, day: -1)

          DateTime.add(now, 45, :second)
          DateTime.add(now, 250, :millisecond)
      """
    ]

  @modules [:DateTime, :NaiveDateTime, :Time]
  @calendar_units [:minute, :hour, :day, :week]
  @calendar_factors [60, 3600, 86_400, 604_800]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    result = Credo.Code.prewalk(source_file, &walk/2, ctx)
    result.issues
  end

  defp walk({:|>, _, [lhs, {callee, meta, args}]}, ctx) when is_list(args) do
    call = {callee, meta, [lhs | args]}
    {call, check_call(call, ctx)}
  end

  defp walk(ast, ctx), do: {ast, check_call(ast, ctx)}

  defp check_call({{:., _, [{:__aliases__, _, [module]}, :add]}, meta, [_, amount | rest]}, ctx)
       when module in @modules and length(rest) <= 1 do
    unit = List.first(rest, :second)

    if calendar_offset?(amount, unit) do
      put_issue(ctx, issue_for(ctx, module, meta))
    else
      ctx
    end
  end

  defp check_call({{:., _, [{:__aliases__, _, [:Date]}, :add]}, meta, [_, _]}, ctx),
    do: put_issue(ctx, issue_for(ctx, :Date, meta))

  defp check_call(_ast, ctx), do: ctx

  defp calendar_offset?(_amount, unit) when unit in @calendar_units, do: true
  defp calendar_offset?(amount, :second), do: calendar_seconds?(amount)
  defp calendar_offset?(_amount, _unit), do: false

  defp calendar_seconds?({:-, _, [amount]}), do: calendar_seconds?(amount)

  defp calendar_seconds?(amount) when is_integer(amount),
    do: amount != 0 and rem(amount, 60) == 0

  defp calendar_seconds?({:*, _, [lhs, rhs]}), do: factor?(lhs) or factor?(rhs)

  defp calendar_seconds?(_amount), do: false

  defp factor?({:-, _, [amount]}), do: factor?(amount)
  defp factor?(amount), do: amount in @calendar_factors

  defp issue_for(ctx, module, meta) do
    format_issue(ctx, message: message(module), trigger: "#{module}.add", line_no: meta[:line])
  end

  defp message(:Date),
    do: "Use `Date.shift/2` for date arithmetic (e.g. `Date.shift(date, day: -1)`)."

  defp message(module) do
    "Use `#{module}.shift/2` for calendar arithmetic (e.g. `#{module}.shift(value, day: -7)`); " <>
      "reserve `#{module}.add/3` for second / millisecond offsets."
  end
end
