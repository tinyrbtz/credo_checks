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
        * the unit is `:second` (or omitted) and the amount's integer
          literals multiply to a whole number of minutes (`300`,
          `2 * 3600`, `days * 24 * 60 * 60`)

      The message names the equivalent `shift` option, in the largest
      unit that divides the offset evenly.

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
  @unit_seconds [week: 604_800, day: 86_400, hour: 3600, minute: 60]

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
    case shift_option(amount, List.first(rest, :second)) do
      nil -> ctx
      option -> put_issue(ctx, issue_for(ctx, module, option, meta))
    end
  end

  defp check_call({{:., _, [{:__aliases__, _, [:Date]}, :add]}, meta, [_, amount]}, ctx),
    do: put_issue(ctx, issue_for(ctx, :Date, "day: #{Macro.to_string(amount)}", meta))

  defp check_call(_ast, ctx), do: ctx

  defp shift_option(amount, unit) when unit in @calendar_units,
    do: "#{unit}: #{Macro.to_string(amount)}"

  defp shift_option(amount, :second) do
    {literals, terms} = amount |> factors() |> Enum.split_with(&is_integer/1)
    seconds = Enum.product(literals)

    if literals != [] and seconds != 0 and rem(seconds, 60) == 0 do
      {unit, size} = Enum.find(@unit_seconds, fn {_unit, size} -> rem(seconds, size) == 0 end)
      "#{unit}: #{amount_string(div(seconds, size), terms)}"
    end
  end

  defp shift_option(_amount, _unit), do: nil

  defp factors({:*, _, [lhs, rhs]}), do: factors(lhs) ++ factors(rhs)
  defp factors({:-, _, [amount]}), do: [-1 | factors(amount)]
  defp factors(amount), do: [amount]

  defp amount_string(count, []), do: Integer.to_string(count)

  defp amount_string(count, terms) do
    product =
      [abs(count) | terms]
      |> Enum.reject(&(&1 == 1))
      |> Enum.reduce(&{:*, [], [&2, &1]})

    if count < 0, do: Macro.to_string({:-, [], [product]}), else: Macro.to_string(product)
  end

  defp issue_for(ctx, module, option, meta) do
    format_issue(ctx,
      message: message(module, option),
      trigger: "#{module}.add",
      line_no: meta[:line]
    )
  end

  defp message(:Date, option), do: "Use `Date.shift/2` with `#{option}` for date arithmetic."

  defp message(module, option) do
    "Use `#{module}.shift/2` with `#{option}` for calendar arithmetic; " <>
      "reserve `#{module}.add/3` for second / millisecond offsets."
  end
end
