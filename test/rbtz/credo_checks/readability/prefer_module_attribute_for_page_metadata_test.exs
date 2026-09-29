defmodule Rbtz.CredoChecks.Readability.PreferModuleAttributeForPageMetadataTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferModuleAttributeForPageMetadata

  test "exposes metadata from `use Credo.Check`" do
    assert PreferModuleAttributeForPageMetadata.id() |> is_binary()
    assert PreferModuleAttributeForPageMetadata.category() |> is_atom()
    assert PreferModuleAttributeForPageMetadata.base_priority() |> is_atom()
    assert PreferModuleAttributeForPageMetadata.explanations()[:check] |> is_binary()
    assert PreferModuleAttributeForPageMetadata.param_defaults() |> is_list()
    assert PreferModuleAttributeForPageMetadata.param_names() |> is_list()
  end

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(PreferModuleAttributeForPageMetadata, params)
  end

  defp lines_and_triggers(issues),
    do: issues |> Enum.map(&{&1.line_no, &1.trigger}) |> Enum.sort()

  test "flags string literals in keyword, map, and key/value assigns" do
    """
    defmodule MyAppWeb.SettingsLive do
      def mount(_params, _session, socket) do
        socket = assign(socket, page_title: "Settings", page_description: "Your settings")
        socket = socket |> assign(%{page_title: "Settings"})
        {:ok, Phoenix.Component.assign(socket, :page_title, "Settings")}
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert lines_and_triggers(issues) == [
               {3, "page_description"},
               {3, "page_title"},
               {4, "page_title"},
               {5, "page_title"}
             ]
    end)
  end

  test "flags controller assigns and render assigns" do
    """
    defmodule MyAppWeb.PageController do
      def about(conn, _params) do
        conn
        |> assign(:page_title, "About")
        |> render(:about, page_title: "About")
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert lines_and_triggers(issues) == [{4, "page_title"}, {5, "page_title"}]
    end)
  end

  test "does not flag module attributes, interpolation, or computed values" do
    ~S"""
    defmodule MyAppWeb.SettingsLive do
      @page_title "Settings"

      def mount(_params, _session, socket) do
        socket = assign(socket, page_title: @page_title)
        socket = assign(socket, page_title: "#{socket.assigns.user.name} settings")
        socket = assign(socket, page_title: gettext("Settings"))
        {:ok, assign(socket, :page_title, title)}
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "does not flag other keys or other calls" do
    """
    defmodule MyAppWeb.SettingsLive do
      def mount(_params, _session, socket) do
        socket = assign(socket, heading: "Settings")
        socket = assign(socket, :heading, "Settings")
        Map.put(socket, :page_title, "Settings")
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "uses the configured keys" do
    """
    assign(socket, heading: "Settings", page_title: "Settings")
    """
    |> run(keys: [:heading])
    |> assert_issue(fn issue -> assert issue.trigger == "heading" end)
  end
end
