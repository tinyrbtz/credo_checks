defmodule Rbtz.CredoChecks.Design.BareScriptInHeexTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.BareScriptInHeex

  test "exposes metadata from `use Credo.Check`" do
    assert BareScriptInHeex.id() |> is_binary()
    assert BareScriptInHeex.category() |> is_atom()
    assert BareScriptInHeex.base_priority() |> is_atom()
    assert BareScriptInHeex.explanation() |> is_binary()
    assert BareScriptInHeex.params_defaults() |> is_list()
    assert BareScriptInHeex.params_names() |> is_list()
  end

  test "flags raw `<script>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <script>console.log("hi")</script>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> assert_issue()
  end

  test "flags `<script type=...>`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <script type="module">import foo from "./foo.js";</script>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> assert_issue()
  end

  test "does not flag colocated hook declarations (`<script :type={...}>`)" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Filter">
          export default { mounted() { /* ... */ } }
        </script>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> refute_issues()
  end

  test "does not flag colocated hook declarations split across lines" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <script
          :type={Phoenix.LiveView.ColocatedHook}
          name=".Filter"
        >
          export default { mounted() { /* ... */ } }
        </script>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> refute_issues()
  end

  test ~s(does not flag external `<script src="...">` tags) do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <script defer src="https://accounts.google.com/gsi/client"></script>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> refute_issues()
  end

  test "does not flag elements that merely contain the substring `script`" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div data-script="ignored">x</div>
        <p>JavaScript is allowed in prose</p>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> refute_issues()
  end

  test "does not flag templates with no script tags" do
    ~S'''
    defmodule MyLive do
      def render(assigns) do
        ~H"""
        <div id="root">hello</div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(BareScriptInHeex)
    |> refute_issues()
  end
end
