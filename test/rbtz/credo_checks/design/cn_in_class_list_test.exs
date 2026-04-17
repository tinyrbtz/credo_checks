defmodule Rbtz.CredoChecks.Design.CnInClassListTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.CnInClassList

  test "exposes metadata from `use Credo.Check`" do
    assert CnInClassList.id() |> is_binary()
    assert CnInClassList.category() |> is_atom()
    assert CnInClassList.base_priority() |> is_atom()
    assert CnInClassList.explanation() |> is_binary()
    assert CnInClassList.params_defaults() |> is_list()
    assert CnInClassList.params_names() |> is_list()
  end

  describe "rule: cn(...) requires an assign" do
    test "flags `cn([...])` when arguments don't include any assign" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def card(assigns) do
          ~H"""
          <div class={cn(["rounded border p-2"])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "nothing to merge"
      end)
    end

    test "flags multi-line `cn([...])` without any assign" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def icon(assigns) do
          ~H"""
          <svg
            class={
              cn([
                "size-4 shrink-0 text-muted-foreground",
                "transition-transform duration-200"
              ])
            }
          />
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "nothing to merge"
      end)
    end

    test "does not flag `cn([..., @class])`" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={cn(["rounded border p-2", @class])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test "does not flag `cn([..., @other_assign])` — any assign satisfies the rule" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :inset, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={cn(["shrink-0", @inset])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test "does not flag `cn(some_var)` (dynamic arg, can't tell)" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def card(assigns) do
          ~H"""
          <div class={cn(build_classes(assigns))}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test "does not flag `cn([..., slot[:class]])` (slot attribute access)" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        slot :tab, required: true do
          attr :class, :any
        end

        def tab_nav(assigns) do
          ~H"""
          <.link
            :for={tab <- @tab}
            class={
              cn([
                "relative inline-flex items-center",
                "transition-colors",
                tab[:class]
              ])
            }
          >x</.link>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end
  end

  describe "rule: bare list with an assign + siblings requires cn(...)" do
    test "flags a bare list with `@class` and siblings" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={[
            "flex w-full flex-1 items-center justify-between rounded-md border",
            "py-4 text-sm font-medium text-foreground",
            "cursor-pointer outline-none transition-all hover:underline",
            @class
          ]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "bare list"
      end)
    end

    test "flags single-line bare list with `@class` and siblings" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={["rounded border p-2", @class]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue()
    end

    test "flags a bare list with a non-`@class` assign and siblings" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :color, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={["rounded border p-2", @color]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "bare list"
      end)
    end

    test "flags a bare list with an assign not last (no Rule 3 ordering message)" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :color, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={[@color, "text-sm"]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "bare list"
        refute issue.message =~ "must come after"
      end)
    end

    test "does not flag a bare list without any assign" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        def card(assigns) do
          ~H"""
          <div class={["rounded border p-2", "text-sm"]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test "does not flag a single-element list `[@class]`" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={[@class]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test "does not flag solo `class={@class}`" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={@class}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test "does not flag an assign used only as a condition in a nested expression" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :compact, :boolean, default: false

        def card(assigns) do
          ~H"""
          <div class={[
            "rounded border",
            "text-sm",
            if(@compact, do: "p-1", else: "p-4")
          ]}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end
  end

  describe "rule: inside cn(...), assigns must come after all literal classes" do
    test ~s|flags `cn([@class, "text-sm"])` (assign first)| do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={cn([@class, "text-sm"])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "must come after"
      end)
    end

    test "flags a literal appearing after an assign inside cn(...)" do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={cn(["rounded border", @class, "p-2"])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> assert_issue(fn issue ->
        assert issue.message =~ "must come after"
      end)
    end

    test ~s|does not flag `cn(["text-sm", @class])` (single assign, last)| do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={cn(["text-sm", @class])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end

    test ~s|does not flag `cn(["text-sm", @class, @color])` (multiple assigns, all last)| do
      ~S'''
      defmodule MyComponent do
        use Phoenix.Component

        attr :class, :string, default: nil
        attr :color, :string, default: nil

        def card(assigns) do
          ~H"""
          <div class={cn(["text-sm", @class, @color])}>x</div>
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(CnInClassList)
      |> refute_issues()
    end
  end

  test "configurable via :helper_name" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={merge(["rounded border p-2"])}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList, helper_name: "merge")
    |> assert_issue()
  end

  test "respects `:helper_name` for the wrap suggestion too" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      attr :class, :string, default: nil

      def card(assigns) do
        ~H"""
        <div class={["rounded border p-2", @class]}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList, helper_name: "merge")
    |> assert_issue(fn issue ->
      assert issue.message =~ "merge"
    end)
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert CnInClassList.run(src, []) == []
  end

  test "ignores a `class={...}` whose contents aren't valid Elixir" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={1 2}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> refute_issues()
  end

  test "flags a remote `Mod.cn(...)` call without any assign" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={Utils.cn(["rounded border p-2"])}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> assert_issue(fn issue ->
      assert issue.message =~ "nothing to merge"
    end)
  end

  test "flags `cn(...)` with numeric, atom, and tuple literals" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={cn([1, :active, {"k", :v}])}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> assert_issue()
  end

  test "flags `cn(...)` with 3+ element tuple literals" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={cn([{:a, :b, "c"}])}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> assert_issue(fn issue ->
      assert issue.message =~ "nothing to merge"
    end)
  end

  test "handles a class expression with nested `{}` and strings" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      attr :class, :string, default: nil

      def card(assigns) do
        ~H"""
        <div class={Map.get(%{foo: "bar"}, :foo, @class)}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> refute_issues()
  end

  test "handles class attr with escape sequences inside a string literal" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={"has \\backslash"}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> refute_issues()
  end

  test "tolerates an unclosed `class={` attribute" do
    ~S'''
    defmodule MyComponent do
      use Phoenix.Component

      def card(assigns) do
        ~H"""
        <div class={unclosed
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(CnInClassList)
    |> refute_issues()
  end
end
