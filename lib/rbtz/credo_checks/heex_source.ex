defmodule Rbtz.CredoChecks.HeexSource do
  @moduledoc """
  Internal helper used by the HEEx-scanning Rbtz Credo checks.

  ## Template extraction

  `templates/1` returns every `~H` sigil string and every `.heex` template
  referenced via `embed_templates` as a list of `{contents, line_fn}` tuples.
  `line_fn` is a function that takes an offset (0-based line index into
  `contents`) and returns the line number in the `.ex` source file to report
  an issue against.

  For `~H` sigils, `line_fn.(off)` = sigil_start_line + off.

  For `embed_templates`, the template contents live in a separate
  `.html.heex` file — Credo's `format_issue` can only reference lines that
  exist in the `.ex` source file, so `line_fn.(_)` always returns the line
  of the `embed_templates` call.

  ## Body capture

  `capture_interpolation/1` and `capture_string/1` extract the inside of
  `class={...}` and `class="..."` attribute bodies respectively, tracking
  string/escape state so braces nested inside strings or escaped quotes are
  handled correctly.

  ## Tag walking

  `walk_tags/3` walks a template line-by-line, tracking multi-line open tags,
  and returns one record per fully-opened tag (`{open_line, trigger, presence}`).
  Callers provide a tag-open detector and a keyword list of attribute detectors;
  the helper centralises the state machine the various `phx-*` checks share.
  """

  @doc """
  Returns `[{contents, line_fn}]` for every HEEx template embedded in the file.
  """
  def templates(source_file) do
    case Credo.Code.ast(source_file) do
      {:ok, ast} ->
        {_ast, acc} = Macro.prewalk(ast, [], &collect(&1, &2, source_file))
        Enum.reverse(acc)

      _ ->
        []
    end
  end

  defp collect({:sigil_H, meta, [{:<<>>, _, [heex]}, []]} = ast, acc, _source_file)
       when is_binary(heex) do
    sigil_line = meta[:line] || 1
    line_fn = &(sigil_line + &1)
    {ast, [{heex, line_fn} | acc]}
  end

  defp collect({:embed_templates, meta, [pattern | _]} = ast, acc, source_file)
       when is_binary(pattern) do
    call_line = meta[:line] || 1
    line_fn = fn _off -> call_line end

    base_dir = Path.dirname(source_file.filename)

    glob = Path.join(base_dir, pattern <> ".html.heex")

    acc =
      glob
      |> Path.wildcard()
      |> Enum.reduce(acc, fn file, acc ->
        # sobelow_skip ["Traversal.FileModule"]
        case File.read(file) do
          {:ok, contents} -> [{contents, line_fn} | acc]
          _ -> acc
        end
      end)

    {ast, acc}
  end

  defp collect(ast, acc, _source_file), do: {ast, acc}

  @doc """
  Captures the content of a `{...}` interpolation body.

  Call with `input` pointing to the first byte inside the `{`. Consumes until
  the matching close brace at depth 0 and returns `{:ok, captured}`, or
  `:unterminated` if the input runs out first. Braces inside string literals
  (with backslash escapes) do not affect the depth counter.
  """
  def capture_interpolation(input) when is_binary(input) do
    capture_interp(input, <<>>, 1, nil)
  end

  # Inside a string: handle escape, handle closing quote, consume.
  defp capture_interp(<<?\\, c, rest::binary>>, acc, depth, str) when str != nil do
    capture_interp(rest, <<acc::binary, ?\\, c>>, depth, str)
  end

  defp capture_interp(<<c, rest::binary>>, acc, depth, str) when str != nil and c == str do
    capture_interp(rest, <<acc::binary, c>>, depth, nil)
  end

  defp capture_interp(<<c, rest::binary>>, acc, depth, str) when str != nil do
    capture_interp(rest, <<acc::binary, c>>, depth, str)
  end

  # Outside strings: track `{`, `}`, and quote entry.
  defp capture_interp(<<?", rest::binary>>, acc, depth, nil) do
    capture_interp(rest, <<acc::binary, ?">>, depth, ?")
  end

  defp capture_interp(<<?{, rest::binary>>, acc, depth, nil) do
    capture_interp(rest, <<acc::binary, ?{>>, depth + 1, nil)
  end

  defp capture_interp(<<?}, _rest::binary>>, acc, 1, nil), do: {:ok, acc}

  defp capture_interp(<<?}, rest::binary>>, acc, depth, nil) do
    capture_interp(rest, <<acc::binary, ?}>>, depth - 1, nil)
  end

  defp capture_interp(<<c, rest::binary>>, acc, depth, nil) do
    capture_interp(rest, <<acc::binary, c>>, depth, nil)
  end

  defp capture_interp(<<>>, _acc, _depth, _str), do: :unterminated

  @doc """
  Captures the content of a `"..."` string literal body.

  Call with `input` pointing to the first byte inside the opening `"`. Consumes
  until the closing (unescaped) `"` and returns `{:ok, captured}`, or
  `:unterminated` if the input runs out first. The captured content preserves
  backslash escapes verbatim.
  """
  def capture_string(input) when is_binary(input) do
    capture_str(input, <<>>)
  end

  defp capture_str(<<>>, _acc), do: :unterminated

  defp capture_str(<<?\\, c, rest::binary>>, acc) do
    capture_str(rest, <<acc::binary, ?\\, c>>)
  end

  defp capture_str(<<?", _rest::binary>>, acc), do: {:ok, acc}
  defp capture_str(<<c, rest::binary>>, acc), do: capture_str(rest, <<acc::binary, c>>)

  @doc """
  Walks a HEEx template line-by-line and returns one record per fully-opened
  tag.

  `detect_open.(line)` returns `{trigger, rest_of_line}` for a tag opener it
  wants to track, or `nil` to skip the line. `attr_detectors` is a keyword list
  of `{key, detector_fn}` — each `detector_fn.(text)` is called with the
  current text slice and returns truthy if the attribute appears. Presence is
  sticky: once an attribute is seen on any line of a tag's body, it stays true.

  Returns `[{open_line, trigger, presence_map}]` in source order, where
  `presence_map` has one boolean per key in `attr_detectors`.

  Limitation: splits a tag at the first `>` on any line, so `>` characters
  inside attribute strings can prematurely close a tag. This matches the
  behaviour of the pre-extraction per-check scanners.
  """
  def walk_tags({contents, line_fn}, detect_open, attr_detectors)
      when is_binary(contents) and is_function(detect_open, 1) and is_list(attr_detectors) do
    keys = Enum.map(attr_detectors, &elem(&1, 0))
    empty = Map.new(keys, &{&1, false})

    contents
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce({nil, []}, fn {line, idx}, {state, records} ->
      process_tag_line(line, line_fn.(idx), state, records, detect_open, attr_detectors, empty)
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp process_tag_line(line, line_no, nil, records, detect_open, attr_detectors, empty) do
    case detect_open.(line) do
      nil ->
        {nil, records}

      {trigger, rest} ->
        step_tag(rest, line_no, trigger, empty, records, attr_detectors)
    end
  end

  defp process_tag_line(line, _line_no, {open_line, trigger, presence}, records, _, attrs, _) do
    step_tag(line, open_line, trigger, presence, records, attrs)
  end

  defp step_tag(text, open_line, trigger, presence, records, attr_detectors) do
    presence = update_presence(presence, text, attr_detectors)

    case String.split(text, ">", parts: 2) do
      [_only] ->
        {{open_line, trigger, presence}, records}

      [_before, _after] ->
        {nil, [{open_line, trigger, presence} | records]}
    end
  end

  defp update_presence(presence, text, attr_detectors) do
    Enum.reduce(attr_detectors, presence, fn {key, detector}, acc ->
      cond do
        Map.get(acc, key) -> acc
        detector.(text) -> Map.put(acc, key, true)
        true -> acc
      end
    end)
  end

  @doc """
  Returns the number of `\\n` bytes in `binary`.

  Checks that compute a line number by slicing into the template via
  `binary_part/3` use this to translate a byte offset into a line offset.
  """
  def count_newlines(binary) when is_binary(binary) do
    binary |> :binary.matches("\n") |> length()
  end

  # Anchored to `^` or whitespace so `data-id=`, `aria-labelledby=`, etc. are
  # not mistaken for an `id` attribute. Matches `id=`, `id=...`, or `id ` when
  # preceded by start-of-text or whitespace.
  @id_regex ~r/(?:^|\s)id(?:=|\s)/

  @doc """
  Returns `true` when `text` contains an `id=` (or `id ` / `id={`) attribute
  as a standalone token — not as a tail of a hyphenated name such as
  `data-id=` or `aria-labelledby=`.

  Shared between the `phx_*_without_id` checks and the
  `LiveViewFormCanBeRehydrated` check so the regex lives in one place.
  """
  def has_id?(text) when is_binary(text), do: Regex.match?(@id_regex, text)
end
