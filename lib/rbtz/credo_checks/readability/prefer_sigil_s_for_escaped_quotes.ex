defmodule Rbtz.CredoChecks.Readability.PreferSigilSForEscapedQuotes do
  use Credo.Check,
    id: "RBTZ0005",
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Encourages using the `~s` sigil when a double-quoted string needs to
      escape one or more `"` characters.

      `~s(...)`, `~s{...}`, and friends let you pick a delimiter that doesn't
      collide with the string's contents, so the body reads as it will
      eventually print — no `\\"` noise to parse visually.

      Interpolation still works inside `~s`, so this is purely a readability
      swap — no semantic change.

      # Bad

          "Run \\"mix test.coverage\\" once all exports complete"
          ~s|He said \\"hi\\"|

      # Good

          ~s(Run "mix test.coverage" once all exports complete)
          ~s|He said "hi"|

      The check inspects every plain double-quoted string literal (`"..."`).
      Heredocs, sigils, and charlists are not flagged.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)
    source = SourceFile.source(source_file)

    source
    |> Credo.Code.to_tokens()
    |> Enum.reduce(ctx, &check_token(&1, source, &2))
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp check_token({:bin_string, {line, col, _}, _parts}, source, ctx) do
    if has_escaped_quote?(source, line, col) do
      put_issue(ctx, issue_for(ctx, line))
    else
      ctx
    end
  end

  defp check_token(_token, _source, ctx), do: ctx

  defp has_escaped_quote?(source, line, col) do
    <<?", body::binary>> = slice_from(source, line, col)
    scan(body, false)
  end

  defp slice_from(source, line, col) do
    [first | rest] = source |> String.split("\n") |> Enum.drop(line - 1)
    first_sliced = String.slice(first, (col - 1)..-1//1)
    Enum.join([first_sliced | rest], "\n")
  end

  defp scan(<<?\\, ?", rest::binary>>, _found), do: scan(rest, true)
  defp scan(<<?\\, _::8, rest::binary>>, found), do: scan(rest, found)
  defp scan(<<?", _rest::binary>>, found), do: found
  defp scan(<<_::8, rest::binary>>, found), do: scan(rest, found)

  defp issue_for(ctx, line) do
    format_issue(ctx,
      message:
        ~s|Use the `~s` sigil for strings that need escaped `"` characters, | <>
          ~s|e.g. `~s(Run "mix test" now)`.|,
      trigger: ~s|\\"|,
      line_no: line
    )
  end
end
