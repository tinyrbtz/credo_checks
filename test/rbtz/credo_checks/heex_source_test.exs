defmodule Rbtz.CredoChecks.HeexSourceTest do
  use ExUnit.Case, async: true

  alias Rbtz.CredoChecks.HeexSource

  test "extracts ~H sigil templates with a line resolver" do
    src = ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <p>Hello, <%= @name %></p>
        """
      end
    end
    '''

    templates = src |> Credo.SourceFile.parse("lib/my_live.ex") |> HeexSource.templates()

    assert [{heex, line_fn}] = templates
    assert String.contains?(heex, "Hello")
    assert is_function(line_fn, 1)
    assert line_fn.(0) == 3
    assert line_fn.(2) == 5
  end

  test "returns [] when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert HeexSource.templates(src) == []
  end

  describe "embed_templates" do
    @tmp Path.join(System.tmp_dir!(), "heex_source_test")

    setup do
      File.rm_rf!(@tmp)
      File.mkdir_p!(@tmp)

      on_exit(fn -> File.rm_rf!(@tmp) end)

      :ok
    end

    test "reads files matched by embed_templates and returns their contents" do
      @tmp |> Path.join("show.html.heex") |> File.write!("<p>line 1</p>\n<p>line 2</p>")

      src =
        Credo.SourceFile.parse(
          """
          defmodule MyLive do
            use Phoenix.Component
            embed_templates "*"
          end
          """,
          Path.join(@tmp, "my_live.ex")
        )

      assert [{contents, line_fn}] = HeexSource.templates(src)
      assert contents == "<p>line 1</p>\n<p>line 2</p>"
      # For embed_templates, every offset resolves to the `embed_templates`
      # call line so Credo's `format_issue` never references a line beyond
      # the `.ex` source file.
      assert line_fn.(0) == 3
      assert line_fn.(1) == 3
      assert line_fn.(999) == 3
    end

    test "skips files that cannot be read" do
      # embed_templates references a pattern that matches nothing;
      # no files are opened so no crash, but we also exercise the glob path
      # returning an empty list.
      src =
        Credo.SourceFile.parse(
          """
          defmodule MyLive do
            use Phoenix.Component
            embed_templates "does_not_exist_*"
          end
          """,
          Path.join(@tmp, "my_live.ex")
        )

      assert HeexSource.templates(src) == []
    end

    test "skips unreadable files matched by the glob" do
      path = Path.join(@tmp, "unreadable.html.heex")
      File.write!(path, "<p>x</p>")
      File.chmod!(path, 0o000)

      src =
        Credo.SourceFile.parse(
          """
          defmodule MyLive do
            use Phoenix.Component
            embed_templates "unreadable"
          end
          """,
          Path.join(@tmp, "my_live.ex")
        )

      # Path.wildcard finds the file but File.read returns an error tuple —
      # the `_` branch in the case preserves acc unchanged.
      assert HeexSource.templates(src) == []
    after
      # restore perms so cleanup can remove the file
      path = Path.join(@tmp, "unreadable.html.heex")
      if File.exists?(path), do: File.chmod!(path, 0o644)
    end
  end

  describe "capture_interpolation/1" do
    test "captures a simple body" do
      assert HeexSource.capture_interpolation("hello}") == {:ok, "hello"}
    end

    test "tracks nested braces" do
      assert HeexSource.capture_interpolation("a{b{c}d}e}rest") == {:ok, "a{b{c}d}e"}
    end

    test "treats braces inside strings as literal" do
      assert HeexSource.capture_interpolation(~S(a"}{"b}rest)) == {:ok, ~S(a"}{"b)}
    end

    test "honours backslash escapes inside strings" do
      assert HeexSource.capture_interpolation(~S(a"\""b}rest)) == {:ok, ~S(a"\""b)}
    end

    test "returns :unterminated on missing close" do
      assert HeexSource.capture_interpolation("abc") == :unterminated
    end
  end

  describe "capture_string/1" do
    test "captures a simple body" do
      assert HeexSource.capture_string(~S(hello"rest)) == {:ok, "hello"}
    end

    test "preserves escape sequences verbatim" do
      assert HeexSource.capture_string(~S(a\"b"rest)) == {:ok, ~S(a\"b)}
    end

    test "returns :unterminated on missing close" do
      assert HeexSource.capture_string("no close") == :unterminated
    end
  end

  describe "count_newlines/1" do
    test "returns 0 for a string with no newlines" do
      assert HeexSource.count_newlines("abc") == 0
    end

    test "counts every `\\n` byte" do
      assert HeexSource.count_newlines("a\nb\nc") == 2
      assert HeexSource.count_newlines("\n\n\n") == 3
    end

    test "returns 0 for an empty string" do
      assert HeexSource.count_newlines("") == 0
    end
  end

  describe "has_id?/1" do
    test "matches `id=` with an equals sign" do
      assert HeexSource.has_id?(~s(id="foo"))
      assert HeexSource.has_id?(~s(class="x" id="foo"))
    end

    test "matches `id={...}` interpolation" do
      assert HeexSource.has_id?("id={@id}")
    end

    test "matches bare `id` followed by whitespace" do
      assert HeexSource.has_id?(" id foo")
    end

    test "matches `id=` at the start of a continuation line (leading whitespace)" do
      assert HeexSource.has_id?(~s(  id="foo"))
    end

    test "does not match `id=` as the tail of a hyphenated attribute" do
      refute HeexSource.has_id?(~s(data-id="foo"))
      refute HeexSource.has_id?(~s(aria-labelledby="x"))
    end

    test "does not match `id` as a substring of another word" do
      refute HeexSource.has_id?(~s(class="grid-size"))
      refute HeexSource.has_id?(~s(data-identifier="x"))
    end
  end

  describe "walk_tags/3" do
    test "records every open tag with attribute presence" do
      template =
        {~s(<div id="a" phx-hook="X">\n<span phx-hook="Y">\n), &(&1 + 10)}

      records =
        HeexSource.walk_tags(
          template,
          fn line ->
            case Regex.run(~r/<[A-Za-z][A-Za-z0-9._-]*/, line, return: :index) do
              [{s, l}] -> {"<", String.slice(line, (s + l)..-1//1) || ""}
              _ -> nil
            end
          end,
          id: &String.contains?(&1, "id="),
          hook: &String.contains?(&1, "phx-hook")
        )

      assert records == [
               {10, "<", %{id: true, hook: true}},
               {11, "<", %{id: false, hook: true}}
             ]
    end

    test "accumulates attributes across lines of a single tag" do
      template = {~s(<div\n  id="a"\n  phx-hook="X"\n>), &(&1 + 1)}

      records =
        HeexSource.walk_tags(
          template,
          fn
            "<div" -> {"<div", ""}
            _ -> nil
          end,
          id: &String.contains?(&1, "id="),
          hook: &String.contains?(&1, "phx-hook")
        )

      assert records == [{1, "<div", %{id: true, hook: true}}]
    end

    test "returns [] when no opens are detected" do
      template = {"no tags here\n", &(&1 + 1)}
      assert HeexSource.walk_tags(template, fn _ -> nil end, []) == []
    end

    # Pins the documented limitation: `>` inside an attribute string on one
    # line prematurely closes a multi-line tag, so attributes on later lines
    # are invisible to walk_tags.
    test "treats `>` inside an attribute string as tag close on multi-line tags" do
      template = {~s(<div data-content="1 > 0"\n  id="a"\n>), &(&1 + 1)}

      records =
        HeexSource.walk_tags(
          template,
          fn
            "<div" <> rest -> {"<div", rest}
            _ -> nil
          end,
          id: &String.contains?(&1, "id=")
        )

      # `id="a"` lives on line 2, after the tag was prematurely closed by the
      # `>` inside `"1 > 0"` on line 1 — so `id` presence is reported as false.
      assert records == [{1, "<div", %{id: false}}]
    end
  end
end
