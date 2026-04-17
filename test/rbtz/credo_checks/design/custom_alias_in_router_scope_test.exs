defmodule Rbtz.CredoChecks.Design.CustomAliasInRouterScopeTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.CustomAliasInRouterScope

  test "exposes metadata from `use Credo.Check`" do
    assert CustomAliasInRouterScope.id() |> is_binary()
    assert CustomAliasInRouterScope.category() |> is_atom()
    assert CustomAliasInRouterScope.base_priority() |> is_atom()
    assert CustomAliasInRouterScope.explanation() |> is_binary()
    assert CustomAliasInRouterScope.params_defaults() |> is_list()
    assert CustomAliasInRouterScope.params_names() |> is_list()
  end

  test "flags `alias` inside `scope` block" do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      scope "/admin", MyAppWeb.Admin do
        alias MyAppWeb.Admin.Users
        get "/users", Users.IndexController, :index
      end
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(CustomAliasInRouterScope)
    |> assert_issue()
  end

  test "does not flag scope without alias inside" do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      scope "/admin", MyAppWeb.Admin do
        get "/users", Users.IndexController, :index
      end
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(CustomAliasInRouterScope)
    |> refute_issues()
  end

  test "does not flag top-level alias outside scope" do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router
      alias MyAppWeb.SomePlug

      scope "/" do
        get "/", SomeController, :index
      end
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(CustomAliasInRouterScope)
    |> refute_issues()
  end

  test "ignores `scope` with no keyword-list argument" do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      scope "/api"
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(CustomAliasInRouterScope)
    |> refute_issues()
  end

  test "ignores `scope` whose keyword list has no :do" do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      scope "/api", path: "/api"
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(CustomAliasInRouterScope)
    |> refute_issues()
  end

  test "flags `alias` directly (non-block) inside `scope`" do
    """
    defmodule MyAppWeb.Router do
      use Phoenix.Router

      scope "/admin" do
        alias MyAppWeb.Admin
      end
    end
    """
    |> to_source_file("lib/my_app_web/router.ex")
    |> run_check(CustomAliasInRouterScope)
    |> assert_issue()
  end

  test "ignores non-router files" do
    """
    defmodule M do
      def go do
        scope "/admin", MyAppWeb.Admin do
          alias MyAppWeb.Admin.Users
        end
      end
    end
    """
    |> to_source_file("lib/m.ex")
    |> run_check(CustomAliasInRouterScope)
    |> refute_issues()
  end

  test "does not crash on a non-binary filename" do
    src = %Credo.SourceFile{filename: nil, status: :valid, hash: "x"}
    assert CustomAliasInRouterScope.run(src, []) == []
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/my_app_web/router.ex")
    assert CustomAliasInRouterScope.run(src, []) == []
  end
end
