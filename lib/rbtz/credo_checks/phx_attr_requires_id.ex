defmodule Rbtz.CredoChecks.PhxAttrRequiresId do
  @moduledoc """
  Shared scan for the `phx_*_without_id` checks.

  `offending_tag_lines/2` returns the source line of every tag in the HEEx
  templates of `source_file` that matches `detect_attr.(text)` but does not
  carry an `id=` attribute. Each concrete check supplies its own attribute
  detector and wraps these line numbers in a formatted issue.

  Detection of open tags is intentionally restricted to standard and Phoenix
  component tags (`<Tag>`, `<.component>`); closing tags (`</...`) and HEEx
  interpolation (`<%`) are skipped because neither `/` nor `%` can follow `<`
  in the required shape.
  """

  alias Rbtz.CredoChecks.HeexSource

  @any_tag_regex ~r/<\.?[A-Za-z][A-Za-z0-9._-]*/

  def offending_tag_lines(source_file, detect_attr) when is_function(detect_attr, 1) do
    source_file
    |> HeexSource.templates()
    |> Enum.flat_map(&scan_template(&1, detect_attr))
  end

  defp scan_template(template, detect_attr) do
    template
    |> HeexSource.walk_tags(
      &detect_any_tag/1,
      id: &HeexSource.has_id?/1,
      attr: detect_attr
    )
    |> Enum.filter(fn {_open, _trigger, p} -> p.attr and not p.id end)
    |> Enum.map(fn {open, _trigger, _p} -> open end)
  end

  defp detect_any_tag(line) do
    case Regex.run(@any_tag_regex, line, return: :index) do
      [{start, len}] -> {"<", String.slice(line, (start + len)..-1//1)}
      _ -> nil
    end
  end
end
