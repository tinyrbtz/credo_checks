defmodule Rbtz.CredoChecks.Warning.PhxHookComponentWithoutStableIdTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.PhxHookComponentWithoutStableId

  test "exposes metadata from `use Credo.Check`" do
    assert PhxHookComponentWithoutStableId.id() |> is_binary()
    assert PhxHookComponentWithoutStableId.category() |> is_atom()
    assert PhxHookComponentWithoutStableId.base_priority() |> is_atom()
    assert PhxHookComponentWithoutStableId.explanation() |> is_binary()
    assert PhxHookComponentWithoutStableId.params_defaults() |> is_list()
    assert PhxHookComponentWithoutStableId.params_names() |> is_list()
  end

  test "flags component with phx-hook missing any stable id attr" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook=".PhoneNumber" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "flags when `attr :id, :string, default: nil` (nil default isn't stable)" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, default: nil
      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "flags when id attr type is not `:string`" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :any, required: true

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "does not flag when `attr :id, :string, required: true` is declared" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true
      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook=".PhoneNumber" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag when opts order differs" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, doc: "DOM id", required: true

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag when attr has a different name but a binary default" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :clear_button_id, :string, default: "search-clear-button"
      attr :class, :string, default: nil

      def clear_button(assigns) do
        ~H"""
        <button
          id={@clear_button_id}
          phx-hook="InputClearButton"
          phx-update="ignore"
          class={@class}
        >x</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag when attr has a different name but is required" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :input_id, :string, required: true

      def input(assigns) do
        ~H"""
        <input id={@input_id} phx-hook=".Input" />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag when the phx-hook element has a literal id" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div id="phone-number" phx-hook=".PhoneNumber" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag when id uses a single-quoted literal" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div id='phone-number' phx-hook=".PhoneNumber" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "flags when phx-hook element has no id attribute at all" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def widget(assigns) do
        ~H"""
        <div phx-hook=".Widget" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "flags when id binding contains nested braces (complex)" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :opts, :map, required: true

      def widget(assigns) do
        ~H"""
        <div id={%{k: "v"}[:k]} phx-hook=".Widget">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "does not flag a derived id that references only stable attrs" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true

      def trigger(assigns) do
        ~H"""
        <button id={@id <> "-trigger"} phx-hook=".Trigger">x</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "flags when a derived id references an unstable (undeclared) assign" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true

      def widget(assigns) do
        ~H"""
        <div id={@id <> "-" <> @variant} phx-hook=".Widget">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "flags when a complex id expression references no assigns" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def widget(assigns) do
        ~H"""
        <div id={Ecto.UUID.generate()} phx-hook=".Widget" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "flags when `id={@name}` references an undeclared attr" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def widget(assigns) do
        ~H"""
        <div id={@widget_id} phx-hook=".Widget" class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "does not flag when multiple phx-hook elements each bind to a stable attr" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :a_id, :string, required: true
      attr :b_id, :string, default: "default-b"

      def pair(assigns) do
        ~H"""
        <div id={@a_id} phx-hook=".A">a</div>
        <div id={@b_id} phx-hook=".B">b</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag a component whose template has no phx-hook" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "does not flag a def with no preceding attrs (e.g. LiveView render)" do
    ~S'''
    defmodule MyLive do
      use Phoenix.LiveView

      def render(assigns) do
        ~H"""
        <div id="phone" phx-hook=".PhoneNumber">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "attrs declared for one component don't carry over to the next" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true

      def with_hook(assigns) do
        ~H"""
        <div id={@id} phx-hook=".A">x</div>
        """
      end

      def without_hook(assigns) do
        ~H"""
        <div>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "flags only the component that is missing the stable id attr" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true

      def ok_component(assigns) do
        ~H"""
        <div id={@id} phx-hook=".A">x</div>
        """
      end

      attr :class, :string, default: nil

      def bad_component(assigns) do
        ~H"""
        <div id={@id} phx-hook=".B">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue(&(&1.trigger == "bad_component"))
  end

  test "handles a module whose body is a single statement (not a block)" do
    ~S'''
    defmodule MyComponents do
      def lonely(assigns), do: ~H"<div>x</div>"
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "ignores private `defp` declarations between attrs and defs" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      defp helper(x), do: x

      attr :id, :string, required: true

      def with_hook(assigns) do
        ~H"""
        <div id={@id} phx-hook=".A">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "ignores `def` with a `rescue` clause (non-standard shape)" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true

      def risky(assigns) do
        ~H"""
        <div id={@id} phx-hook=".A">x</div>
        """
      rescue
        _ -> nil
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "handles component defs with a `when` guard" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def guarded(assigns) when is_map(assigns) do
        ~H"""
        <div id={@id} phx-hook=".A">x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue(&(&1.trigger == "guarded"))
  end

  test "flags when `phx-hook` value is interpolated from an assign" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook={@hook} class={@class}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue()
  end

  test "does not flag when interpolated `phx-hook` is paired with required id attr" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :id, :string, required: true
      attr :hook, :string, required: true

      def phone_number(assigns) do
        ~H"""
        <div id={@id} phx-hook={@hook}>x</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert PhxHookComponentWithoutStableId.run(src, []) == []
  end

  test "reports only once when a function has multiple phx-hook usages" do
    ~S'''
    defmodule MyComponents do
      use Phoenix.Component

      attr :class, :string, default: nil

      def noisy(assigns) do
        ~H"""
        <div id={@id} phx-hook=".A" class={@class}>a</div>
        <div id={@id} phx-hook=".B" class={@class}>b</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(PhxHookComponentWithoutStableId)
    |> assert_issue(&(&1.trigger == "noisy"))
  end
end
