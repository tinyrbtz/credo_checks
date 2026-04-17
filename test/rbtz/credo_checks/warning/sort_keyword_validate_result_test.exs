defmodule Rbtz.CredoChecks.Warning.SortKeywordValidateResultTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.SortKeywordValidateResult

  test "exposes metadata from `use Credo.Check`" do
    assert SortKeywordValidateResult.id() |> is_binary()
    assert SortKeywordValidateResult.category() |> is_atom()
    assert SortKeywordValidateResult.base_priority() |> is_atom()
    assert SortKeywordValidateResult.explanation() |> is_binary()
    assert SortKeywordValidateResult.params_defaults() |> is_list()
    assert SortKeywordValidateResult.params_names() |> is_list()
  end

  test "flags `[a: a, b: b] = Keyword.validate!(opts, defs)`" do
    ~S'''
    defmodule MyMod do
      def go(opts) do
        [foo: foo, bar: bar] = Keyword.validate!(opts, foo: 1, bar: 2)
        {foo, bar}
      end
    end
    '''
    |> to_source_file()
    |> run_check(SortKeywordValidateResult)
    |> assert_issue()
  end

  test "flags binding to a var name" do
    ~S'''
    defmodule MyMod do
      def go(opts) do
        validated = Keyword.validate!(opts, foo: 1)
        validated
      end
    end
    '''
    |> to_source_file()
    |> run_check(SortKeywordValidateResult)
    |> assert_issue()
  end

  test "flags `<-` binding in `with`" do
    ~S'''
    defmodule MyMod do
      def go(opts) do
        with [foo: foo, bar: bar] <- Keyword.validate!(opts, foo: 1, bar: 2) do
          {foo, bar}
        end
      end
    end
    '''
    |> to_source_file()
    |> run_check(SortKeywordValidateResult)
    |> assert_issue()
  end

  test "does not flag bare call (no binding)" do
    ~S'''
    defmodule MyMod do
      def go(opts) do
        Keyword.validate!(opts, [:foo, :bar])
        :ok
      end
    end
    '''
    |> to_source_file()
    |> run_check(SortKeywordValidateResult)
    |> refute_issues()
  end

  test "does not flag when piped through Enum.sort" do
    ~S'''
    defmodule MyMod do
      def go(opts) do
        [bar: bar, foo: foo] = opts |> Keyword.validate!(foo: 1, bar: 2) |> Enum.sort()
        {foo, bar}
      end
    end
    '''
    |> to_source_file()
    |> run_check(SortKeywordValidateResult)
    |> refute_issues()
  end

  test "does not flag calls through an aliased `Keyword` (known limitation)" do
    # The check only matches fully-qualified `Keyword.validate!` because the
    # AST carries `{:__aliases__, _, [:Keyword]}`. Aliasing the module
    # silently bypasses the check — unusual enough in practice that we live
    # with the gap.
    ~S'''
    defmodule MyMod do
      alias Keyword, as: K

      def go(opts) do
        [foo: foo, bar: bar] = K.validate!(opts, foo: 1, bar: 2)
        {foo, bar}
      end
    end
    '''
    |> to_source_file()
    |> run_check(SortKeywordValidateResult)
    |> refute_issues()
  end
end
