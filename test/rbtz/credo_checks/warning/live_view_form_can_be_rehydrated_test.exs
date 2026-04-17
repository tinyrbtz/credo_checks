defmodule Rbtz.CredoChecks.Warning.LiveViewFormCanBeRehydratedTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.LiveViewFormCanBeRehydrated

  test "exposes metadata from `use Credo.Check`" do
    assert LiveViewFormCanBeRehydrated.id() |> is_binary()
    assert LiveViewFormCanBeRehydrated.category() |> is_atom()
    assert LiveViewFormCanBeRehydrated.base_priority() |> is_atom()
    assert LiveViewFormCanBeRehydrated.explanation() |> is_binary()
    assert LiveViewFormCanBeRehydrated.params_defaults() |> is_list()
    assert LiveViewFormCanBeRehydrated.params_names() |> is_list()
  end

  test "flags `<.form phx-submit>` missing both id and phx-change" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@form} phx-submit="save">
          <.input field={@form[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "flags `<form phx-submit>` missing phx-change" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <form id="login" phx-submit="save">
          <input name="email" />
        </form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "flags multi-line form missing attrs" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form
          for={@form}
          phx-submit="save"
        >
          <.input field={@form[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "does not flag a fully-attributed form" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@form} id="profile" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not flag a form without phx-submit" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@form}>
          <.input field={@form[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not flag templates without forms" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div>
          <p>Hello</p>
        </div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not flag a form whose only phx-* attribute is phx-change" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@form} phx-change="validate">
          <.input field={@form[:name]} />
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "flags an inner form that is missing attrs (nested forms are each inspected)" do
    # Nested forms are invalid HTML but the check should still evaluate both
    # openings and flag the one missing attributes.
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <.form for={@outer} id="outer" phx-submit="save_outer" phx-change="validate_outer">
          <.form for={@inner} phx-submit="save_inner">
            <.input field={@inner[:name]} />
          </.form>
        </.form>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "does not flag forms outside ~H sigils" do
    ~S'''
    defmodule MyHelper do
      def html_string do
        "<form phx-submit=\"save\"><input /></form>"
      end
    end
    '''
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert LiveViewFormCanBeRehydrated.run(src, []) == []
  end

  describe "embed_templates" do
    @tmp Path.join(System.tmp_dir!(), "live_view_form_rehydrate_test")

    setup do
      File.rm_rf!(@tmp)
      File.mkdir_p!(@tmp)

      on_exit(fn -> File.rm_rf!(@tmp) end)

      :ok
    end

    test "flags a form in an embedded template missing phx-change" do
      @tmp
      |> Path.join("show.html.heex")
      |> File.write!(~S'''
      <form id="login" phx-submit="save">
        <input name="email" />
      </form>
      ''')

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

      issues = LiveViewFormCanBeRehydrated.run(src, [])
      assert length(issues) == 1
    end

    test "ignores embedded templates that cannot be read" do
      path = Path.join(@tmp, "bad.html.heex")
      File.write!(path, ~s(<form phx-submit="save"></form>))
      File.chmod!(path, 0o000)

      src =
        Credo.SourceFile.parse(
          """
          defmodule MyLive do
            use Phoenix.Component
            embed_templates "bad"
          end
          """,
          Path.join(@tmp, "my_live.ex")
        )

      assert LiveViewFormCanBeRehydrated.run(src, []) == []
    after
      path = Path.join(@tmp, "bad.html.heex")
      if File.exists?(path), do: File.chmod!(path, 0o644)
    end
  end
end
