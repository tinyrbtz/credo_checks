defmodule Rbtz.CredoChecks.Readability.AwkwardPipeTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.AwkwardPipe

  defp issues_for(source) do
    source
    |> to_source_file()
    |> run_check(AwkwardPipe)
  end

  defp assert_has_trigger(issues, trigger) do
    assert Enum.any?(issues, &(&1.trigger == trigger)),
           "expected a #{trigger} issue, got triggers: " <>
             inspect(Enum.map(issues, & &1.trigger))

    issues
  end

  defp refute_has_trigger(issues, trigger) do
    refute Enum.any?(issues, &(&1.trigger == trigger)),
           "unexpected #{trigger} issue; got: " <>
             inspect(Enum.map(issues, &{&1.trigger, &1.line_no}))

    issues
  end

  test "exposes metadata from `use Credo.Check`" do
    assert AwkwardPipe.id() |> is_binary()
    assert AwkwardPipe.category() == :readability
    assert AwkwardPipe.base_priority() |> is_atom()
    assert AwkwardPipe.explanation() |> is_binary()
    assert AwkwardPipe.params_defaults() |> is_list()
    assert AwkwardPipe.params_names() |> is_list()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert AwkwardPipe.run(src, []) == []
  end

  describe "Rule 1 — pipe on either operand of `&&` / `||`" do
    test "flags `&&` with a pipe on both sides" do
      """
      defmodule M do
        def a(x, y) do
          if x |> String.trim() && y |> String.trim(), do: :ok
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("&&")
    end

    test "flags `||` with a pipe on both sides" do
      """
      defmodule M do
        def a(x, y), do: _other = x |> String.trim() || y |> String.trim()
      end
      """
      |> issues_for()
      |> assert_has_trigger("||")
    end

    test "flags `&&` with only one operand piped" do
      """
      defmodule M do
        def a(x, y), do: _other = (x |> String.trim()) && y
        def b(x, y), do: _other = x && (y |> String.trim())
      end
      """
      |> issues_for()
      |> assert_has_trigger("&&")
    end

    test "flags `||` with only one operand piped" do
      """
      defmodule M do
        def a(x, y), do: _other = (x |> String.trim()) || y
      end
      """
      |> issues_for()
      |> assert_has_trigger("||")
    end

    test "flags a multi-line `||` chain where each pipe is single-line" do
      """
      defmodule M do
        def a(x, y) do
          check?(x) ||
            x |> String.match?(~r/\\d/) ||
            y |> String.match?(~r/\\d/)
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("||")
    end
  end

  describe "Rule 2 — pipe as operand of `++` / `<>` / `in` / `and` / `or`" do
    test "flags `<>` with a pipe on either side" do
      """
      defmodule M do
        def a(base_url, url), do: base_url |> String.trim_trailing("/") <> url
      end
      """
      |> issues_for()
      |> assert_has_trigger("<>")
    end

    test "flags `in` with a pipe on either side" do
      """
      defmodule M do
        def a(user), do: user |> role() in [:admin, :owner]
      end
      """
      |> issues_for()
      |> assert_has_trigger("in")
    end

    test "flags `and` with a pipe on either side" do
      """
      defmodule M do
        def a(x, y), do: _other = (x |> foo()) and y
      end
      """
      |> issues_for()
      |> assert_has_trigger("and")
    end

    test "flags `++` with a pipe on either side" do
      """
      defmodule M do
        def a(xs, ys), do: xs |> Enum.reverse() ++ ys
      end
      """
      |> issues_for()
      |> assert_has_trigger("++")
    end

    test "does not flag plain function-call forms" do
      """
      defmodule M do
        def a(base_url, url), do: String.trim_trailing(base_url, "/") <> url
        def b(user), do: role(user) in [:admin]
        def c(xs, ys), do: Enum.reverse(xs) ++ ys
      end
      """
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "Rule 3 — pipe into `Kernel.` operator form" do
    test "flags `|> Kernel.||([])`" do
      """
      defmodule M do
        def a(attrs), do: attrs |> Map.get(:items) |> Kernel.||([])
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.||")
    end

    test "flags `|> Kernel.++([])`" do
      """
      defmodule M do
        def a(xs), do: xs |> Enum.to_list() |> Kernel.++([])
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.++")
    end

    test "flags `|> Kernel.&&(other)` (logical)" do
      """
      defmodule M do
        def a(x, y), do: x |> String.trim() |> Kernel.&&(y)
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.&&")
    end

    test "flags `|> Kernel.and(other)` (logical word-form)" do
      """
      defmodule M do
        def a(x, y), do: x |> String.trim() |> Kernel.and(y)
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.and")
    end

    test "flags `|> Kernel.-(1)` (arithmetic)" do
      """
      defmodule M do
        def a(list), do: list |> length() |> Kernel.-(1)
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.-")
    end

    test "flags `|> Kernel.==(other)` (equality)" do
      """
      defmodule M do
        def a(x, y), do: x |> String.trim() |> Kernel.==(y)
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.==")
    end

    test "flags `|> Kernel.<(other)` (comparison)" do
      """
      defmodule M do
        def a(x, y), do: x |> length() |> Kernel.<(y)
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.<")
    end

    test "flags `|> Kernel.in(list)` (membership)" do
      """
      defmodule M do
        def a(role), do: role |> String.to_atom() |> Kernel.in([:admin, :owner])
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.in")
    end

    test "flags `|> Kernel.!()` (unary)" do
      """
      defmodule M do
        def a(x), do: x |> is_nil() |> Kernel.!()
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.!")
    end

    test "does not flag `a || []` without a pipe" do
      """
      defmodule M do
        def a(attrs), do: Map.get(attrs, :items) || []
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag a pipe into a non-operator Kernel function" do
      """
      defmodule M do
        def a(list), do: list |> Enum.reverse() |> Kernel.length()
      end
      """
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "Rule 4 — single-step pipe inside tuple literal" do
    test "flags `{:ok, socket |> assign(...)}`" do
      issues =
        """
        defmodule M do
          def a(socket), do: {:ok, socket |> assign(page_title: "Invite")}
        end
        """
        |> issues_for()

      assert Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end

    test "flags a single-step pipe inside a 3-tuple literal" do
      issues =
        """
        defmodule M do
          def a(x, y, z), do: {:triple, x |> foo(), y, z}
        end
        """
        |> issues_for()

      assert Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end

    test "does not flag multi-step chain inside a tuple literal" do
      """
      defmodule M do
        def a(socket, user) do
          {:ok, socket |> assign(:user, user) |> assign(:page_title, "Invite")}
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag a pipe in a keyword list entry" do
      issues =
        """
        defmodule M do
          def a(socket), do: assign(socket, user: socket |> fetch_user())
        end
        """
        |> issues_for()

      # The pipe is inside a keyword-list value in a non-first-arg position
      # (Rule 6 flags it with message mentioning "non-first argument"). Rule 4
      # must NOT flag the keyword-list entry as a tuple literal.
      refute Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end
  end

  describe "Rule 5 — single-step pipe inside string interpolation" do
    test "flags single-step pipe in double-quoted interpolation" do
      ~S'''
      defmodule M do
        def a(data), do: "<ol>#{data |> list_items_html()}</ol>"
      end
      '''
      |> issues_for()
      |> assert_issue()
    end

    test "flags single-step pipe inside ~s sigil interpolation" do
      ~S'''
      defmodule M do
        def a(data), do: ~s[<ol>#{data |> list_items_html()}</ol>]
      end
      '''
      |> issues_for()
      |> assert_issue()
    end

    test "does not flag multi-step chain inside interpolation" do
      ~S'''
      defmodule M do
        def a(data), do: "<ol>#{data |> Enum.sort() |> list_items_html()}</ol>"
      end
      '''
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag interpolation of a plain call" do
      ~S'''
      defmodule M do
        def a(data), do: "<ol>#{list_items_html(data)}</ol>"
      end
      '''
      |> issues_for()
      |> refute_issues()
    end

    test "flags single-step pipe inside multi-line heredoc interpolation" do
      ~S'''
      defmodule M do
        def a(data) do
          """
          items:
            #{data |> Enum.sort()}
          """
        end
      end
      '''
      |> issues_for()
      |> assert_issue()
    end

    test "does not flag interpolation containing a pipe with multi-line LHS" do
      ~S'''
      defmodule M do
        def a do
          "value: #{"""
          heredoc
          """ |> String.trim()}"
        end
      end
      '''
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "Rule 6 — single-step pipe as non-first argument" do
    test "flags a single-step pipe in the 2nd arg of an unpiped call" do
      issues =
        """
        defmodule M do
          def a(map, name) do
            Map.put(map, :slug, name |> String.downcase())
          end
        end
        """
        |> issues_for()

      assert Enum.any?(issues, &String.contains?(&1.message, "non-first argument"))
    end

    test "flags a single-step pipe in explicit arg of a piped call" do
      # When the outer call is piped, the piped-in value occupies position 0
      # implicitly, so the explicit arg is at effective position >= 1.
      issues =
        """
        defmodule M do
          def a(map, name) do
            map |> Map.put(:slug, name |> String.downcase())
          end
        end
        """
        |> issues_for()

      assert Enum.any?(issues, &String.contains?(&1.message, "non-first argument"))
    end

    test "does not flag a multi-step chain in non-first arg" do
      """
      defmodule M do
        def a(map, name) do
          Map.put(map, :slug, name |> String.downcase() |> URI.encode())
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag a pipe in first-arg position of an unpiped call" do
      issues =
        """
        defmodule M do
          def a(list), do: Kernel.length(list |> Enum.reverse())
        end
        """
        |> issues_for()

      refute Enum.any?(issues, &String.contains?(&1.message, "non-first argument"))
    end

    test "does not flag a case-clause body that is a pipe" do
      # `->` clauses are not function calls — the body must not be treated
      # as a "non-first arg" of the `->` node.
      """
      defmodule M do
        def a(list) do
          case list do
            [_ | _] -> list |> hd()
            [] -> nil
          end
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag a for-comprehension generator RHS in plain `.ex`" do
      # Rule 9 covers HEEx templates only; plain `for x <- expr` in `.ex`
      # is out of scope.
      """
      defmodule M do
        def a(items), do: for x <- items |> Enum.sort(), do: x
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag pipes on either side of a comparison operator" do
      # `==`, `!=`, `<`, `>`, etc. are binary comparison operators, not
      # function calls — their operands must not be treated as call args.
      """
      defmodule M do
        def a(x, y), do: x |> Enum.sort() == y |> Enum.sort()
        def b(x, y), do: x |> length() != y |> length()
        def c(x, y), do: x |> length() < y |> length()
        def d(x, y), do: x |> String.trim() =~ y |> to_string()
      end
      """
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "Rule 7 — pipe joined in `if` / `unless` / `cond` condition" do
    test "flags an `if` condition with `&&`-joined pipes" do
      """
      defmodule M do
        def a(attrs) do
          if attrs |> has_class?("component") && attrs |> has_class?("image"), do: :ok
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("if")
    end

    test "flags an `unless` condition with a pipe joined via `or`" do
      """
      defmodule M do
        def a(user, resource) do
          unless user |> authorized?() or resource |> public?(), do: :deny
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("unless")
    end

    test "flags a `cond` clause with a pipe joined via `or`" do
      """
      defmodule M do
        def a(user, resource) do
          cond do
            user |> authorized?() or resource |> public?() -> :allow
            true -> :deny
          end
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("cond")
    end

    test "flags an `if` condition where only one side is a pipe (unified)" do
      # Under the unified Rule 7, ANY pipe joined by &&/||/and/or fires.
      """
      defmodule M do
        def a(attrs, other) do
          if attrs |> has_class?("component") && other, do: :ok
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("if")
    end

    test "does not flag a single pipe in condition with no binary op" do
      """
      defmodule M do
        def a(attrs) do
          if attrs |> has_class?("wp-caption"), do: :ok
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    # Exercises the `Macro.traverse` post-callback depth decrement when a
    # condition contains a join-op but no pipe beneath it.
    test "does not flag a joined condition with no pipes" do
      """
      defmodule M do
        def a(x, y) do
          if x && y, do: :ok
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "Rule 8 — pipe inside single-line anonymous function" do
    test "flags `fn x -> x |> f() end` on a single line" do
      """
      defmodule M do
        def a(items), do: Enum.map(items, fn x -> x |> String.trim() end)
      end
      """
      |> issues_for()
      |> assert_has_trigger("fn")
    end

    test "flags `&(x |> f(&1))` on a single line" do
      """
      defmodule M do
        def a(items, text), do: Enum.any?(items, &(text |> String.contains?(&1)))
      end
      """
      |> issues_for()
      |> assert_has_trigger("&")
    end

    test "does not flag a multi-line `fn` body" do
      """
      defmodule M do
        def a(items) do
          Enum.map(items, fn x ->
            x |> String.trim()
          end)
        end
      end
      """
      |> issues_for()
      |> refute_has_trigger("fn")
    end

    test "does not flag a multi-step chain inside a single-line body" do
      """
      defmodule M do
        def a(items, text) do
          Enum.any?(items, &(text |> String.trim() |> String.contains?(&1)))
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "does not flag an arity-form capture" do
      """
      defmodule M do
        def a(items), do: Enum.map(items, &String.trim/1)
      end
      """
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "Rule 9 — pipe on `<-` RHS in HEEx `:for=` / `for`" do
    test "flags a single-step pipe on the RHS of `:for={ … <- … }`" do
      ~S'''
      defmodule M do
        use Phoenix.Component
        def list(assigns) do
          ~H"""
          <ul>
            <li :for={{item, idx} <- @items |> Enum.with_index()}>
              {item} #{idx}
            </li>
          </ul>
          """
        end
      end
      '''
      |> issues_for()
      |> assert_has_trigger("<-")
    end

    test "flags a single-step pipe on the RHS of `<%= for … %>`" do
      ~S'''
      defmodule M do
        use Phoenix.Component
        def list(assigns) do
          ~H"""
          <ul>
            <%= for item <- @items |> Enum.sort_by(& &1.name) do %>
              <li>{item.name}</li>
            <% end %>
          </ul>
          """
        end
      end
      '''
      |> issues_for()
      |> assert_has_trigger("<-")
    end

    test "does not flag a multi-step chain on the RHS" do
      ~S'''
      defmodule M do
        use Phoenix.Component
        def list(assigns) do
          ~H"""
          <ul>
            <li :for={{item, idx} <- @items |> Enum.filter(& &1.active?) |> Enum.with_index()}>
              {item}
            </li>
          </ul>
          """
        end
      end
      '''
      |> issues_for()
      |> refute_has_trigger("<-")
    end

    test "flags a pipe on RHS of `<-` where the line has no closing brace or `do %>`" do
      # A multi-line comprehension: the `<-` and the `|>` live on a line that
      # ends with `,` (before `do %>` on the next line). The Rule 9 regex
      # falls to the no-terminator branch and treats the remainder of the
      # line as the RHS.
      ~S'''
      defmodule M do
        use Phoenix.Component
        def list(assigns) do
          ~H"""
          <ul>
            <%= for item <- @items |> Enum.sort(),
                    item.visible? do %>
              <li>{item.name}</li>
            <% end %>
          </ul>
          """
        end
      end
      '''
      |> issues_for()
      |> assert_has_trigger("<-")
    end

    test "does not flag a plain call on the RHS" do
      ~S'''
      defmodule M do
        use Phoenix.Component
        def list(assigns) do
          ~H"""
          <ul>
            <li :for={{item, idx} <- Enum.with_index(@items)}>{item}</li>
          </ul>
          """
        end
      end
      '''
      |> issues_for()
      |> refute_issues()
    end
  end

  describe "AST shapes" do
    test "walks into map literals with atom keys without flagging them as tuples" do
      # `%{a: x |> f()}` has AST `{:%{}, _, [{:a, pipe}]}`. The inner 2-tuple
      # is a map entry, not a tuple literal — Rule 4 must not fire.
      issues =
        """
        defmodule M do
          def a(x), do: %{a: x |> foo(:b)}
        end
        """
        |> issues_for()

      refute Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end

    test "walks into maps with non-atom keys" do
      """
      defmodule M do
        def a(x), do: %{"k" => x |> foo(:b)}
      end
      """
      |> issues_for()
      |> refute_has_trigger("||")
    end

    test "walks into map-update expressions" do
      # `%{m | a: x |> f()}` uses the `:|` special form inside `:%{}`, which
      # exercises the map-update entry fallback.
      """
      defmodule M do
        def a(m, x), do: %{m | a: x |> foo(:b)}
      end
      """
      |> issues_for()
      |> refute_has_trigger("||")
    end

    test "walks into struct literals" do
      """
      defmodule M do
        def a(x), do: %URI{path: x |> foo(:b)}
      end
      """
      |> issues_for()
      |> refute_has_trigger("||")
    end

    test "does not crash when piping into a variable" do
      # `x |> some_fun_var.()` goes through the dot-call branch of
      # `walk_piped/2`, while `x |> y` (rare, but legal AST) exercises the
      # non-call fallback.
      """
      defmodule M do
        def a(x, f), do: x |> f.()
      end
      """
      |> issues_for()
      |> refute_has_trigger("||")
    end

    test "walk_piped accepts a non-call RHS without flagging" do
      # `x |> y` where `y` is a bare variable — the parser produces
      # `{:|>, _, [x, {:y, _, Elixir}]}` (atom third element, not a list),
      # which falls to the non-call fallback in `walk_piped/2`.
      issues =
        """
        defmodule M do
          def a(x, y), do: x |> y
        end
        """
        |> issues_for()

      assert issues == []
    end

    test "flags single-step pipe inside a 1-tuple literal" do
      # 1-tuple `{expr}` is `{:{}, _, [expr]}` — exercises the 3+-tuple
      # branch even though there's only one element.
      issues =
        """
        defmodule M do
          def a(x), do: {x |> foo(:b)}
        end
        """
        |> issues_for()

      assert Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end
  end

  describe "multi-line gate" do
    test "Rule 6 — does not flag a pipe arg whose LHS is itself multi-line" do
      # Pipe operator spans multiple lines because its LHS (a keyword list)
      # does. That's structurally unavoidable — the rule should skip.
      """
      defmodule M do
        def fetch(opts \\\\ []) do
          Task.async_stream(
            @items,
            @fun,
            [
              timeout: @timeout,
              max_concurrency: @max_concurrency
            ]
            |> Keyword.merge(opts)
          )
        end
      end
      """
      |> issues_for()
      |> refute_issues()
    end

    test "Rule 1 — flags a multi-line `&&` whose pipe operands are each single-line" do
      """
      defmodule M do
        def a(x, y) do
          _ = x |> String.trim() &&
                y |> String.trim()
          :ok
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("&&")
    end

    test "Rule 2 — flags a multi-line `<>` whose pipe operand is single-line" do
      """
      defmodule M do
        def a(base, url) do
          base |> String.trim_trailing("/") <>
            url
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("<>")
    end

    test "Rule 3 — flags a multi-line pipe chain ending in `Kernel.||`" do
      """
      defmodule M do
        def a(attrs) do
          attrs
          |> Map.get(:items)
          |> Kernel.||([])
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("Kernel.||")
    end

    test "Rule 4 — flags a single-line pipe inside a multi-line tuple" do
      issues =
        """
        defmodule M do
          def a(x, y) do
            {:triple,
             x |> String.trim(),
             y}
          end
        end
        """
        |> issues_for()

      assert Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end

    test "Rule 4 — does not flag a tuple element whose pipe LHS is multi-line" do
      issues =
        ~S'''
        defmodule M do
          def a do
            {:ok,
             """
             heredoc
             """
             |> String.trim()}
          end
        end
        '''
        |> issues_for()

      refute Enum.any?(issues, &String.contains?(&1.message, "tuple literal"))
    end

    test "Rule 7 — flags a multi-line `if` condition with joined pipes" do
      """
      defmodule M do
        def a(x, y) do
          if x |> String.trim() &&
               y |> String.trim() do
            :ok
          end
        end
      end
      """
      |> issues_for()
      |> assert_has_trigger("if")
    end
  end

  describe "dedup" do
    test "emits at most one issue per {line, column}" do
      # `if x |> f() && y |> g()` fires Rule 1 (both operands are pipes)
      # *and* Rule 7 (if-condition contains a joined pipe). They target
      # different triggers at different columns, so both remain — but
      # neither rule should fire twice on the same position.
      issues =
        """
        defmodule M do
          def a(x, y) do
            if x |> foo() && y |> bar(), do: :ok
          end
        end
        """
        |> issues_for()

      positions = Enum.map(issues, fn i -> {i.line_no, i.column} end)
      assert positions == Enum.uniq(positions)
    end
  end
end
