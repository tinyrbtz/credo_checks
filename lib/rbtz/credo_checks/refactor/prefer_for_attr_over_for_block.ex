defmodule Rbtz.CredoChecks.Refactor.PreferForAttrOverForBlock do
  use Credo.Check,
    id: "RBTZ0043",
    base_priority: :normal,
    category: :refactor,
    explanations: [
      check: """
      Prefers the `:for={item <- @collection}` attribute directly on an element
      over a `<%= for ... do %>` EEx block when the block wraps a single
      element.

      When the loop body is just one element, `<el :for={...}>` reads cleaner
      and keeps the iteration attached to the element being repeated. Reserve
      `<%= for %>` for loops that genuinely need to emit two or more sibling
      elements per iteration.

      The check inspects every `~H` sigil and every `.heex` template referenced
      via `embed_templates`. It locates each `<%= for ... do %>` block, scans
      its body for top-level HTML/HEEx elements (skipping nested EEx blocks),
      and flags the block when exactly one element is found.

      # Bad

          <%= for item <- @items do %>
            <li>{item.name}</li>
          <% end %>

      # Good

          <li :for={item <- @items}>{item.name}</li>

          <%= for item <- @items do %>
            <dt>{item.name}</dt>
            <dd>{item.value}</dd>
          <% end %>
      """
    ]

  alias Rbtz.CredoChecks.HeexSource

  @for_opener ~r/<%=\s*for\s+.*?\s+do\s*%>/s

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> HeexSource.templates()
    |> Enum.reduce(ctx, &scan_template/2)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp scan_template({heex, line_fn}, ctx) do
    heex
    |> find_for_blocks()
    |> Enum.reduce(ctx, fn {offset, body}, ctx ->
      if count_top_level_elements(body) == 1 do
        line_no = heex |> binary_part(0, offset) |> HeexSource.count_newlines() |> line_fn.()
        put_issue(ctx, issue_for(ctx, line_no))
      else
        ctx
      end
    end)
  end

  defp issue_for(ctx, line_no) do
    format_issue(ctx,
      message:
        "This `<%= for %>` block wraps a single element — put `:for={item <- @collection}` " <>
          "on the element itself. Reserve `<%= for %>` for loops that wrap multiple " <>
          "sibling elements per iteration.",
      trigger: "<%= for",
      line_no: line_no
    )
  end

  # ----- Finding <%= for ... do %> blocks and their bodies -----

  defp find_for_blocks(heex) do
    @for_opener
    |> Regex.scan(heex, return: :index)
    |> Enum.map(fn [{start, len}] ->
      body_start = start + len
      rest = binary_part(heex, body_start, byte_size(heex) - body_start)
      {body, _after_end} = find_block_boundary(rest, 1, <<>>)
      {start, body}
    end)
  end

  # Walks a block body, tracking nested `<% ... do %>` / `<% end %>` pairs.
  # Returns `{body_before_end, remaining_after_end}`. On malformed input
  # (no matching end), returns `{everything_seen, <<>>}`.
  defp find_block_boundary(<<>>, _depth, acc), do: {acc, <<>>}

  defp find_block_boundary(<<"<%", rest::binary>>, depth, acc) do
    case :binary.split(rest, "%>") do
      [eex_body, after_close] -> classify_block_eex(eex_body, after_close, depth, acc)
      _ -> {<<acc::binary, "<%", rest::binary>>, <<>>}
    end
  end

  defp find_block_boundary(<<c, rest::binary>>, depth, acc) do
    find_block_boundary(rest, depth, <<acc::binary, c>>)
  end

  defp classify_block_eex(eex_body, after_close, depth, acc) do
    tag = <<"<%", eex_body::binary, "%>">>
    content = eex_body |> String.trim_leading("=") |> String.trim_leading("!") |> String.trim()

    cond do
      content == "end" and depth == 1 ->
        {acc, after_close}

      content == "end" ->
        find_block_boundary(after_close, depth - 1, <<acc::binary, tag::binary>>)

      opens_block?(content) ->
        find_block_boundary(after_close, depth + 1, <<acc::binary, tag::binary>>)

      true ->
        find_block_boundary(after_close, depth, <<acc::binary, tag::binary>>)
    end
  end

  defp opens_block?(content), do: String.match?(content, ~r/\bdo$/)

  # ----- Counting top-level elements inside a block body -----

  defp count_top_level_elements(body), do: scan_elements(body, 0, 0)

  defp scan_elements(<<>>, _depth, count), do: count

  defp scan_elements(<<"<%", rest::binary>>, depth, count) do
    case :binary.split(rest, "%>") do
      [eex_body, after_close] -> handle_eex_in_body(eex_body, after_close, depth, count)
      _ -> count
    end
  end

  defp scan_elements(<<"</", rest::binary>>, depth, count) do
    case :binary.split(rest, ">") do
      [_tag, remaining] -> close_tag(remaining, depth, count)
      _ -> count
    end
  end

  defp scan_elements(<<"<", c, rest::binary>>, depth, count)
       when c in ?a..?z or c in ?A..?Z or c == ?. or c == ?: do
    case find_tag_end(<<c, rest::binary>>, 0, nil) do
      {:self_close, remaining} -> open_self_close(remaining, depth, count)
      {:open, remaining} -> scan_elements(remaining, depth + 1, count)
    end
  end

  defp scan_elements(<<_c, rest::binary>>, depth, count) do
    scan_elements(rest, depth, count)
  end

  defp handle_eex_in_body(eex_body, after_close, depth, count) do
    content = eex_body |> String.trim_leading("=") |> String.trim_leading("!") |> String.trim()

    if opens_block?(content) do
      {_body, after_end} = find_block_boundary(after_close, 1, <<>>)
      scan_elements(after_end, depth, count)
    else
      scan_elements(after_close, depth, count)
    end
  end

  defp close_tag(remaining, depth, count) do
    new_depth = depth - 1
    new_count = if new_depth == 0, do: count + 1, else: count
    scan_elements(remaining, new_depth, new_count)
  end

  defp open_self_close(remaining, depth, count) do
    new_count = if depth == 0, do: count + 1, else: count
    scan_elements(remaining, depth, new_count)
  end

  # Reads to the end of an HTML/HEEx tag, handling quoted attribute values and
  # `{...}` interpolation. Returns `{:self_close, rest}` or `{:open, rest}`.
  # On malformed input (no closing `>`), returns `{:open, <<>>}`.
  defp find_tag_end(<<>>, _braces, _str), do: {:open, <<>>}

  defp find_tag_end(<<c, rest::binary>>, braces, str) when c == str,
    do: find_tag_end(rest, braces, nil)

  defp find_tag_end(<<_c, rest::binary>>, braces, str) when str != nil,
    do: find_tag_end(rest, braces, str)

  defp find_tag_end(<<c, rest::binary>>, braces, nil) when c in [?", ?'],
    do: find_tag_end(rest, braces, c)

  defp find_tag_end(<<"{", rest::binary>>, braces, nil), do: find_tag_end(rest, braces + 1, nil)

  defp find_tag_end(<<"}", rest::binary>>, braces, nil) when braces > 0,
    do: find_tag_end(rest, braces - 1, nil)

  defp find_tag_end(<<"/>", rest::binary>>, 0, nil), do: {:self_close, rest}
  defp find_tag_end(<<">", rest::binary>>, 0, nil), do: {:open, rest}

  defp find_tag_end(<<_c, rest::binary>>, braces, nil), do: find_tag_end(rest, braces, nil)
end
