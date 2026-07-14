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
    lines = String.split(source, "\n")

    source
    |> Credo.Code.to_tokens()
    |> Enum.reduce(ctx, &check_token(&1, lines, &2))
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp check_token({:bin_string, {line, col, _}, _parts}, lines, ctx) do
    if has_escaped_quote?(lines, line, col) do
      put_issue(ctx, issue_for(ctx, line))
    else
      ctx
    end
  end

  defp check_token(_token, _lines, ctx), do: ctx

  defp has_escaped_quote?(lines, line, col) do
    [first | rest] = Enum.drop(lines, line - 1)
    body = Enum.join([String.slice(first, max(col - 1, 0)..-1//1) | rest], "\n")
    <<?", rest_body::binary>> = body
    do_scan(rest_body, 0)
  end

  # Returns true on the first unescaped `\"` at interpolation depth 0.
  # Skips `#{}` regions so quotes inside interpolations are not treated as
  # terminators. Well-formed string tokens always close before the body is empty.
  defp do_scan(<<?\\, ?", _rest::binary>>, 0), do: true
  defp do_scan(<<?\\, _::8, rest::binary>>, depth), do: do_scan(rest, depth)
  defp do_scan(<<?", _rest::binary>>, 0), do: false
  defp do_scan(<<?#, ?{, rest::binary>>, depth), do: do_scan(rest, depth + 1)
  defp do_scan(<<?{, rest::binary>>, depth) when depth > 0, do: do_scan(rest, depth + 1)
  defp do_scan(<<?}, rest::binary>>, depth) when depth > 0, do: do_scan(rest, depth - 1)
  defp do_scan(<<_::8, rest::binary>>, depth), do: do_scan(rest, depth)

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
