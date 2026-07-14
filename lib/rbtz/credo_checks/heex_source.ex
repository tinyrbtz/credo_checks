defmodule Rbtz.CredoChecks.HeexSource do
  @moduledoc """
  Internal helper used by the HEEx-scanning Rbtz Credo checks.

  ## Template extraction

  `templates/1` returns every `~H` sigil string and every `.heex` template
  referenced via `embed_templates` as a list of `{contents, line_fn}` tuples.
  `line_fn` is a function that takes an offset (0-based line index into
  `contents`) and returns the line number in the `.ex` source file to report
  an issue against.

  For `~H` sigils, `line_fn.(off)` = sigil_start_line + off for inline sigils
  (`~H"<x/>"`) or sigil_start_line + 1 + off for heredoc sigils (`~H\""" ... \"""`),
  since the first line of heredoc content sits on the source line *after* the
  opening delimiter.

  For `embed_templates`, the template contents live in a separate
  `.html.heex` file — Credo's `format_issue` can only reference lines that
  exist in the `.ex` source file, so `line_fn.(_)` always returns the line
  of the `embed_templates` call. When `root:` is passed, it is resolved
  relative to the calling file's directory (Phoenix's rule).

  ## Body capture

  `capture_interpolation/1` and `capture_string/1` extract the inside of
  `class={...}` and `class="..."` attribute bodies respectively, tracking
  string/escape state so braces nested inside strings or escaped quotes are
  handled correctly.

  `find_attr_bodies/3` finds every occurrence of a name-bounded attribute
  prefix (e.g. `class={` that is not a suffix of `wrapper_class=`) and returns
  `[{line_offset, content}]` pairs.

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
    content_offset = if meta[:delimiter] in [~s("""), "'''"], do: 1, else: 0
    line_fn = &(sigil_line + content_offset + &1)
    {ast, [{heex, line_fn} | acc]}
  end

  defp collect({:embed_templates, meta, [pattern | rest]} = ast, acc, source_file)
       when is_binary(pattern) do
    call_line = meta[:line] || 1
    line_fn = fn _off -> call_line end

    base_dir = Path.dirname(source_file.filename)
    root = embed_root(rest, base_dir)
    glob = Path.join(root, pattern <> ".html.heex")

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

  defp embed_root(rest, base_dir) do
    opts = List.first(rest)

    if is_list(opts) do
      case Keyword.get(opts, :root) do
        root when is_binary(root) -> Path.expand(root, base_dir)
        _ -> base_dir
      end
    else
      base_dir
    end
  end

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

  defp capture_interp(<<?\\, c, rest::binary>>, acc, depth, str) when str != nil do
    capture_interp(rest, <<acc::binary, ?\\, c>>, depth, str)
  end

  defp capture_interp(<<c, rest::binary>>, acc, depth, str) when str != nil and c == str do
    capture_interp(rest, <<acc::binary, c>>, depth, nil)
  end

  defp capture_interp(<<c, rest::binary>>, acc, depth, str) when str != nil do
    capture_interp(rest, <<acc::binary, c>>, depth, str)
  end

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

  defp capture_str(<<c, rest::binary>>, acc) do
    capture_str(rest, <<acc::binary, c>>)
  end

  @doc """
  Finds every name-bounded occurrence of `prefix` in `heex` and returns
  `[{line_offset, content}]` for successfully captured attribute bodies.

  `prefix` is typically `"class={"` or `~s(class=")`. A match is accepted only
  when it is not a suffix of a longer attribute name (`wrapper_class=`, etc.).
  """
  def find_attr_bodies(heex, prefix, capture_fn)
      when is_binary(heex) and is_binary(prefix) and is_function(capture_fn, 1) do
    heex
    |> :binary.matches(prefix)
    |> Enum.flat_map(&capture_attr_match(heex, prefix, capture_fn, &1))
  end

  defp capture_attr_match(heex, prefix, capture_fn, {start, _len}) do
    if attr_name_boundary?(heex, start) do
      open_pos = start + byte_size(prefix)
      rest = binary_part(heex, open_pos, byte_size(heex) - open_pos)

      case capture_fn.(rest) do
        {:ok, content} ->
          offset = heex |> binary_part(0, start) |> count_newlines()
          [{offset, content}]

        :unterminated ->
          []
      end
    else
      []
    end
  end

  defp attr_name_boundary?(_heex, 0), do: true

  defp attr_name_boundary?(heex, start) do
    <<prev>> = binary_part(heex, start - 1, 1)
    prev not in ?a..?z and prev not in ?A..?Z and prev not in ?0..?9 and prev not in [?_, ?-]
  end

  @doc """
  Returns `true` when `binary` contains a comma at brace/bracket/paren depth 0
  and outside string literals. Used by class-attribute formatting checks.
  """
  def top_level_comma?(binary) when is_binary(binary) do
    top_level_comma?(
      binary,
      %{brace_depth: 0, bracket_depth: 0, paren_depth: 0, str: nil}
    )
  end

  defp top_level_comma?(<<>>, _s), do: false

  defp top_level_comma?(<<?\\, _c, rest::binary>>, %{str: str} = s) when str != nil do
    top_level_comma?(rest, s)
  end

  defp top_level_comma?(<<c, rest::binary>>, %{str: str} = s) when str != nil and c == str do
    top_level_comma?(rest, %{s | str: nil})
  end

  defp top_level_comma?(<<_c, rest::binary>>, %{str: str} = s) when str != nil do
    top_level_comma?(rest, s)
  end

  defp top_level_comma?(<<?", rest::binary>>, s), do: top_level_comma?(rest, %{s | str: ?"})

  defp top_level_comma?(<<?', rest::binary>>, s), do: top_level_comma?(rest, %{s | str: ?'})

  defp top_level_comma?(<<?{, rest::binary>>, %{brace_depth: d} = s) do
    top_level_comma?(rest, %{s | brace_depth: d + 1})
  end

  defp top_level_comma?(<<?}, rest::binary>>, %{brace_depth: d} = s) do
    top_level_comma?(rest, %{s | brace_depth: d - 1})
  end

  defp top_level_comma?(<<?[, rest::binary>>, %{bracket_depth: d} = s) do
    top_level_comma?(rest, %{s | bracket_depth: d + 1})
  end

  defp top_level_comma?(<<?], rest::binary>>, %{bracket_depth: d} = s) do
    top_level_comma?(rest, %{s | bracket_depth: d - 1})
  end

  defp top_level_comma?(<<?(, rest::binary>>, %{paren_depth: d} = s) do
    top_level_comma?(rest, %{s | paren_depth: d + 1})
  end

  defp top_level_comma?(<<?), rest::binary>>, %{paren_depth: d} = s) do
    top_level_comma?(rest, %{s | paren_depth: d - 1})
  end

  defp top_level_comma?(<<?,, _rest::binary>>, %{
         brace_depth: 0,
         bracket_depth: 0,
         paren_depth: 0,
         str: nil
       }),
       do: true

  defp top_level_comma?(<<_c, rest::binary>>, s), do: top_level_comma?(rest, s)

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

  When a tag closes mid-line, the remainder is re-scanned for further open tags.

  Limitation: splits a tag at the first `>` on any line, so `>` characters
  inside attribute strings can prematurely close a tag. This matches the
  behaviour of the pre-extraction per-check scanners.
  """
  def walk_tags({contents, line_fn}, detect_open, attr_detectors)
      when is_binary(contents) and is_function(detect_open, 1) and is_list(attr_detectors) do
    empty = Map.new(attr_detectors, fn {k, _} -> {k, false} end)
    opts = %{detect_open: detect_open, attr_detectors: attr_detectors, empty: empty}

    contents
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce({nil, []}, fn {line, idx}, {state, records} ->
      process_tag_line(line, line_fn.(idx), state, records, opts)
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp process_tag_line(line, line_no, nil, records, opts) do
    case opts.detect_open.(line) do
      nil ->
        {nil, records}

      {trigger, rest} ->
        step_tag(rest, line_no, line_no, trigger, opts.empty, records, opts)
    end
  end

  defp process_tag_line(line, line_no, {open_line, trigger, presence}, records, opts) do
    step_tag(line, line_no, open_line, trigger, presence, records, opts)
  end

  defp step_tag(text, line_no, open_line, trigger, presence, records, opts) do
    case String.split(text, ">", parts: 2) do
      [only] ->
        presence = update_presence(presence, only, opts.attr_detectors)
        {{open_line, trigger, presence}, records}

      [before, after_text] ->
        presence = update_presence(presence, before, opts.attr_detectors)
        records = [{open_line, trigger, presence} | records]
        process_tag_line(after_text, line_no, nil, records, opts)
    end
  end

  defp update_presence(presence, text, attr_detectors) do
    Enum.reduce(attr_detectors, presence, fn {key, detector}, acc ->
      if not Map.get(acc, key) and detector.(text) do
        Map.put(acc, key, true)
      else
        acc
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
