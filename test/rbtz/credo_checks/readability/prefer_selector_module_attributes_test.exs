defmodule Rbtz.CredoChecks.Readability.PreferSelectorModuleAttributesTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferSelectorModuleAttributes

  test "exposes metadata from `use Credo.Check`" do
    assert PreferSelectorModuleAttributes.id() |> is_binary()
    assert PreferSelectorModuleAttributes.category() |> is_atom()
    assert PreferSelectorModuleAttributes.base_priority() |> is_atom()
    assert PreferSelectorModuleAttributes.explanations()[:check] |> is_binary()
    assert PreferSelectorModuleAttributes.param_defaults() |> is_list()
    assert PreferSelectorModuleAttributes.param_names() |> is_list()
  end

  defp run_test_file(source, params \\ []) do
    source
    |> to_source_file("test/my_app_web/settings_live_test.exs")
    |> run_check(PreferSelectorModuleAttributes, params)
  end

  test "flags inline selectors, piped or not" do
    """
    defmodule MyAppWeb.SettingsLiveTest do
      test "saves", %{view: view, html: html} do
        view |> element("#save") |> render_click()
        assert has_element?(view, ".flash-notice", "Saved")
        assert html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=title]")
        assert get_text(html, by_test_id("title")) == "Settings"
      end
    end
    """
    |> run_test_file()
    |> assert_issues(fn issues ->
      assert issues |> Enum.map(& &1.trigger) |> Enum.sort() ==
               ["#save", ".flash-notice", "[data-role=title]", "title"]
    end)
  end

  test "does not flag module attributes, bare tag names, or computed selectors" do
    ~S"""
    defmodule MyAppWeb.SettingsLiveTest do
      @save_button "#save"
      @title by_test_id("title")

      test "saves", %{view: view, html: html} do
        view |> element(@save_button) |> render_click()
        assert get_text(html, "h1") == "Settings"
        assert get_text(html, @title) == "Settings"
        assert has_element?(view, "#row-#{id}")
        assert has_element?(view, selector)
        assert element(view, @save_button, "Save")
      end
    end
    """
    |> run_test_file()
    |> refute_issues()
  end

  test "uses the configured functions" do
    """
    find_node(html, "#save")
    has_element?(view, "#save")
    """
    |> run_test_file(functions: [find_node: 1])
    |> assert_issue(fn issue -> assert issue.trigger == "#save" end)
  end

  test "uses the configured selector builders" do
    """
    test_selector("save")
    by_test_id("save")
    """
    |> run_test_file(selector_builders: [:test_selector])
    |> assert_issue(fn issue -> assert issue.trigger == "save" end)
  end

  test "does not flag test/support or files outside test/" do
    for path <- ["test/support/dom_helpers.ex", "lib/my_app_web/live/settings_live.ex"] do
      """
      has_element?(view, "#save")
      """
      |> to_source_file(path)
      |> run_check(PreferSelectorModuleAttributes)
      |> refute_issues()
    end
  end
end
