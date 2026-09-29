defmodule Rbtz.CredoChecks.Design.OneModulePerFileTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Design.OneModulePerFile

  test "exposes metadata from `use Credo.Check`" do
    assert OneModulePerFile.id() |> is_binary()
    assert OneModulePerFile.category() |> is_atom()
    assert OneModulePerFile.base_priority() |> is_atom()
    assert OneModulePerFile.explanations()[:check] |> is_binary()
    assert OneModulePerFile.param_defaults() |> is_list()
    assert OneModulePerFile.param_names() |> is_list()
  end

  defp run_lib_file(source) do
    source
    |> to_source_file("lib/my_app/parser.ex")
    |> run_check(OneModulePerFile)
  end

  test "flags a nested module with functions" do
    """
    defmodule MyApp.Parser do
      def parse(input), do: Tokenizer.tokenize(input)

      defmodule Tokenizer do
        def tokenize(input), do: String.split(input)
      end
    end
    """
    |> run_lib_file()
    |> assert_issue(fn issue ->
      assert issue.trigger == "Tokenizer"
      assert issue.line_no == 4
    end)
  end

  test "flags sibling modules after the first" do
    """
    defmodule MyApp.Parser do
      def parse(input), do: String.split(input)
    end

    defmodule MyApp.Lexer do
      def lex(input), do: String.graphemes(input)
    end
    """
    |> run_lib_file()
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Lexer" end)
  end

  test "flags modules nested at any depth" do
    """
    defmodule MyApp.Parser do
      defmodule Tokenizer do
        defmodule Cursor do
          def new, do: 0
        end
      end
    end
    """
    |> run_lib_file()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "flags a struct module that also defines other functions" do
    """
    defmodule MyApp.Parser do
      defmodule Token do
        defstruct [:value]

        def new(value), do: %__MODULE__{value: value}
      end
    end
    """
    |> run_lib_file()
    |> assert_issue()
  end

  test "does not flag nested struct and exception modules" do
    """
    defmodule MyApp.Parser do
      defmodule Token do
        @enforce_keys [:value]
        defstruct [:value]
      end

      defmodule Error do
        defexception [:reason]

        def new(reason), do: %__MODULE__{reason: reason}
      end

      defmodule Empty, do: defstruct([])
    end
    """
    |> run_lib_file()
    |> refute_issues()
  end

  test "does not flag modules generated inside `quote`" do
    """
    defmodule MyApp.Parser do
      defmacro __using__(_opts) do
        quote do
          defmodule Helpers do
            def trim(input), do: String.trim(input)
          end
        end
      end
    end
    """
    |> run_lib_file()
    |> refute_issues()
  end

  test "does not flag a single module" do
    """
    defmodule MyApp.Parser do
      def parse(input), do: String.split(input)
    end
    """
    |> run_lib_file()
    |> refute_issues()
  end

  test "does not flag files outside lib/" do
    """
    defmodule MyApp.ParserTest do
      defmodule FakeTokenizer do
        def tokenize(input), do: [input]
      end
    end
    """
    |> to_source_file("test/my_app/parser_test.exs")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end
end
