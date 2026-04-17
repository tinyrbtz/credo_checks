defmodule Rbtz.CredoChecks.Design.RawHtmlElementsInHeexTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.RawHtmlElementsInHeex

  test "exposes metadata from `use Credo.Check`" do
    assert RawHtmlElementsInHeex.id() |> is_binary()
    assert RawHtmlElementsInHeex.category() |> is_atom()
    assert RawHtmlElementsInHeex.base_priority() |> is_atom()
    assert RawHtmlElementsInHeex.explanation() |> is_binary()
    assert RawHtmlElementsInHeex.params_defaults() |> is_list()
    assert RawHtmlElementsInHeex.params_names() |> is_list()
  end

  test "flags raw `<button>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <button type="submit">Save</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawHtmlElementsInHeex)
    |> assert_issue()
  end

  test "flags raw `<input>`, `<select>`, `<textarea>`, `<a>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <input name="email" />
        <select name="role"></select>
        <textarea name="bio"></textarea>
        <a href="/">Home</a>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawHtmlElementsInHeex)
    |> assert_issues(4)
  end

  test "does not flag component forms" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.button type="submit">Save</.button>
        <.input field={@form[:email]} />
        <.link navigate={~p"/"}>Home</.link>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawHtmlElementsInHeex)
    |> refute_issues()
  end

  test "does not flag namespaced component calls like `<Form.button>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <Form.button type="submit">Save</Form.button>
        <Form.input field={@form[:email]} />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawHtmlElementsInHeex)
    |> refute_issues()
  end

  test "does not flag tags whose names just start with `a` etc." do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <article>
          <aside>side</aside>
        </article>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(RawHtmlElementsInHeex)
    |> refute_issues()
  end

  describe "embed_templates" do
    @tmp Path.join(System.tmp_dir!(), "no_raw_html_elements_in_heex_test")

    setup do
      File.rm_rf!(@tmp)
      File.mkdir_p!(@tmp)

      on_exit(fn -> File.rm_rf!(@tmp) end)

      :ok
    end

    # Regression: issuing against a `.html.heex` line beyond the `.ex` file's
    # line count used to crash Credo's `add_line_no_options/3` with a
    # `MatchError: nil`. The check now always reports against the line of the
    # `embed_templates` call.
    test "reports issues from an embed_templates file at the call line" do
      heex_path = Path.join(@tmp, "show.html.heex")

      File.write!(
        heex_path,
        "<div>\n<div>\n<div>\n<div>\n<div>\n<div>\n<button>deep</button>\n</div>\n</div>\n</div>\n</div>\n</div>\n</div>"
      )

      src =
        Credo.SourceFile.parse(
          """
          defmodule MyHTML do
            use Phoenix.Component
            embed_templates "*"
          end
          """,
          Path.join(@tmp, "my_html.ex")
        )

      issues = RawHtmlElementsInHeex.run(src, [])

      assert [issue] = issues
      assert issue.trigger == "<button"
      # Line 3 is the `embed_templates` call — the `.ex` source has 4 lines
      # total, so any higher line number would crash `format_issue`.
      assert issue.line_no == 3
    end
  end
end
