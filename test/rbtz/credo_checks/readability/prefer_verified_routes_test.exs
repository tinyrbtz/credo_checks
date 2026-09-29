defmodule Rbtz.CredoChecks.Readability.PreferVerifiedRoutesTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.PreferVerifiedRoutes

  test "exposes metadata from `use Credo.Check`" do
    assert PreferVerifiedRoutes.id() |> is_binary()
    assert PreferVerifiedRoutes.category() |> is_atom()
    assert PreferVerifiedRoutes.base_priority() |> is_atom()
    assert PreferVerifiedRoutes.explanations()[:check] |> is_binary()
    assert PreferVerifiedRoutes.param_defaults() |> is_list()
    assert PreferVerifiedRoutes.param_names() |> is_list()
  end

  defp triggers(issues), do: issues |> Enum.map(& &1.trigger) |> Enum.sort()

  test "flags raw paths in navigation calls, piped or not" do
    """
    defmodule MyAppWeb.SettingsLive do
      def handle_event("save", _params, socket) do
        socket = push_patch(socket, to: "/settings/profile")
        socket |> push_navigate(to: "/settings")
      end

      def index(conn, _params), do: redirect(conn, to: "/login")
    end
    """
    |> to_source_file("lib/my_app_web/live/settings_live.ex")
    |> run_check(PreferVerifiedRoutes)
    |> assert_issues(fn issues ->
      assert triggers(issues) == ["/login", "/settings", "/settings/profile"]
    end)
  end

  test "flags raw paths in HEEx `navigate` / `patch` attributes" do
    ~S'''
    defmodule MyAppWeb.Nav do
      use Phoenix.Component

      def nav(assigns) do
        ~H"""
        <.link navigate="/settings">Settings</.link>
        <.link patch="/users?page=2">Next</.link>
        <.link href="https://example.com">Docs</.link>
        <.link navigate={~p"/home"}>Home</.link>
        """
      end
    end
    '''
    |> to_source_file("lib/my_app_web/components/nav.ex")
    |> run_check(PreferVerifiedRoutes)
    |> assert_issues(fn issues ->
      assert issues |> Enum.map(&{&1.line_no, &1.trigger}) |> Enum.sort() == [
               {6, "/settings"},
               {7, "/users?page=2"}
             ]
    end)
  end

  test "flags raw paths in test requests and redirect assertions" do
    """
    defmodule MyAppWeb.UsersTest do
      use MyAppWeb.ConnCase

      test "lists users", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/users")
        conn |> post("/users", user: %{})
        assert_patch(view, "/users?page=2")
        assert_redirect(view, "/login")
        assert redirected_to(conn) == "/home"
        assert conn |> redirected_to(302) == "/welcome"
        assert "/signup" == redirected_to(conn)
        assert redirected_to(conn) == path
      end
    end
    """
    |> to_source_file("test/my_app_web/users_test.exs")
    |> run_check(PreferVerifiedRoutes)
    |> assert_issues(fn issues ->
      assert triggers(issues) ==
               ["/home", "/login", "/signup", "/users", "/users", "/users?page=2", "/welcome"]
    end)
  end

  test "does not flag paths with escape sequences, which `~p` doesn't unescape" do
    ~S"""
    get(conn, "/articles/the-story\n")
    get(conn, "/articles/tab\tstory")
    """
    |> to_source_file("test/my_app_web/articles_test.exs")
    |> run_check(PreferVerifiedRoutes)
    |> refute_issues()
  end

  test "does not flag request helpers outside test files" do
    """
    defmodule MyApp.Client do
      def fetch(client), do: get(client, "/status")
    end
    """
    |> to_source_file("lib/my_app/client.ex")
    |> run_check(PreferVerifiedRoutes)
    |> refute_issues()
  end

  test "does not flag `~p`, external URLs, protocol-relative URLs, or computed paths" do
    """
    defmodule MyAppWeb.SettingsLive do
      def handle_event("save", _params, socket) do
        socket = push_navigate(socket, to: ~p"/settings")
        socket = redirect(socket, external: "https://example.com")
        socket = redirect(socket, to: "//cdn.example.com/file")
        socket = push_patch(socket, to: path)
        push_patch(socket, replace: true)
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/settings_live.ex")
    |> run_check(PreferVerifiedRoutes)
    |> refute_issues()
  end

  test "does not flag `~p` or computed paths in tests" do
    """
    defmodule MyAppWeb.UsersTest do
      use MyAppWeb.ConnCase

      test "lists users", %{conn: conn} do
        {:ok, _view, _html} = live(conn, ~p"/users")
        conn |> get(path)
        assert user.home_path == "/home"
      end
    end
    """
    |> to_source_file("test/my_app_web/users_test.exs")
    |> run_check(PreferVerifiedRoutes)
    |> refute_issues()
  end

  test "does not flag router.ex" do
    """
    defmodule MyAppWeb.Router do
      get "/old", Redirect, to: "/new"
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(PreferVerifiedRoutes)
    |> refute_issues()
  end

  test "skips tests tagged with an `ignore_tags` tag" do
    """
    defmodule MyAppWeb.ApiTest do
      use MyAppWeb.ConnCase

      @tag :with_api_host
      test "bare path on the api host", %{conn: conn} do
        conn |> get("/status")
      end

      test "app path", %{conn: conn} do
        conn |> get("/app-status")
      end

      describe "api host" do
        @describetag with_api_host: true

        test "first", %{conn: conn}, do: get(conn, "/first")

        test "second", %{conn: conn}, do: get(conn, "/second")
      end
    end

    defmodule MyAppWeb.ApiHostTest do
      use MyAppWeb.ConnCase

      @moduletag :with_api_host

      test "status", %{conn: conn}, do: get(conn, "/status")
    end
    """
    |> to_source_file("test/my_app_web/api_test.exs")
    |> run_check(PreferVerifiedRoutes, ignore_tags: [:with_api_host])
    |> assert_issue(fn issue -> assert issue.trigger == "/app-status" end)
  end

  test "checks tagged tests when the tag isn't ignored" do
    """
    defmodule MyAppWeb.ApiTest do
      use MyAppWeb.ConnCase

      @tag :slow
      test "bare path", %{conn: conn} do
        conn |> get("/status")
      end
    end
    """
    |> to_source_file("test/my_app_web/api_test.exs")
    |> run_check(PreferVerifiedRoutes, ignore_tags: [:with_api_host])
    |> assert_issue()
  end
end
