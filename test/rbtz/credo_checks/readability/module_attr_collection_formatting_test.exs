defmodule Rbtz.CredoChecks.Readability.ModuleAttrCollectionFormattingTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.ModuleAttrCollectionFormatting

  test "exposes metadata from `use Credo.Check`" do
    assert ModuleAttrCollectionFormatting.id() |> is_binary()
    assert ModuleAttrCollectionFormatting.category() |> is_atom()
    assert ModuleAttrCollectionFormatting.base_priority() |> is_atom()
    assert ModuleAttrCollectionFormatting.explanations()[:check] |> is_binary()
    assert ModuleAttrCollectionFormatting.param_defaults() |> is_list()
    assert ModuleAttrCollectionFormatting.param_names() |> is_list()
  end

  describe "flags multi-line collections with multiple items on a line" do
    test "~w word sigil" do
      """
      defmodule MyMod do
        @allowed_extensions ~w[
          .png .jpg .jpeg
          .gif .webp
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue(fn issue ->
        assert issue.message =~ "one item per line"
        assert issue.trigger =~ ".png"
      end)
    end

    test "~W word sigil" do
      """
      defmodule MyMod do
        @flags ~W(
          alpha beta
          gamma
        )
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end

    test "list literal" do
      """
      defmodule MyMod do
        @supported_locales [
          "en-US", "en-GB",
          "fr-FR"
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end

    test "keyword list" do
      """
      defmodule MyMod do
        @defaults [
          timeout: 5_000, retries: 3,
          backoff: 100
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end

    test "map" do
      """
      defmodule MyMod do
        @labels %{
          ok: "OK", error: "Error",
          pending: "Pending"
        }
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end

    test "tuple" do
      """
      defmodule MyMod do
        @range {
          1, 2,
          3
        }
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end

    test "struct with a dotted alias" do
      """
      defmodule MyMod do
        @config %MyApp.Config{
          host: "localhost", port: 4000,
          scheme: :http
        }
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end

    test "nested lists sharing a line" do
      """
      defmodule MyMod do
        @matrix [
          [1, 2], [3, 4],
          [5, 6]
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> assert_issue()
    end
  end

  describe "does not flag single-line collections" do
    test "list with many items" do
      """
      defmodule MyMod do
        @supported_locales ["en-US", "en-GB", "fr-FR", "de-DE"]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "~w sigil with many words" do
      """
      defmodule MyMod do
        @allowed_extensions ~w[.png .jpg .jpeg .gif]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end
  end

  describe "does not flag multi-line collections already one item per line" do
    test "list" do
      """
      defmodule MyMod do
        @supported_locales [
          "en-US",
          "en-GB",
          "fr-FR"
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "~w sigil" do
      """
      defmodule MyMod do
        @allowed_extensions ~w[
          .png
          .jpg
          .jpeg
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "map" do
      """
      defmodule MyMod do
        @labels %{
          ok: "OK",
          error: "Error"
        }
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "first item shares the opening-bracket line, rest one per line" do
      """
      defmodule MyMod do
        @pair ["a",
               "b"]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "nested single-line lists, one per outer line" do
      """
      defmodule MyMod do
        @matrix [
          [1, 2],
          [3, 4]
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end
  end

  describe "scope" do
    test "does not flag non-collection module attributes" do
      """
      defmodule MyMod do
        @count 5
        @name "widget"
        @moduledoc "A module."
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "does not flag a multi-line collection that is not a module attribute" do
      """
      defmodule MyMod do
        def langs do
          [
            "a", "b",
            "c"
          ]
        end
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end

    test "does not flag an interpolated ~w sigil" do
      ~S"""
      defmodule MyMod do
        @things ~w[
          #{prefix()} alpha
          beta
        ]
      end
      """
      |> to_source_file()
      |> run_check(ModuleAttrCollectionFormatting)
      |> refute_issues()
    end
  end

  test "reports the issue on the first offending line" do
    """
    defmodule MyMod do
      @supported_locales [
        "en-US",
        "en-GB", "fr-FR"
      ]
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttrCollectionFormatting)
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.trigger =~ "en-GB"
    end)
  end

  test "flags every offending attribute independently" do
    """
    defmodule MyMod do
      @nums [
        1, 2,
        3
      ]

      @flags ~w[
        x y
        z
      ]
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttrCollectionFormatting)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  describe "malformed input" do
    test "does not crash on a struct attribute without a body" do
      src = Credo.SourceFile.parse("defmodule MyMod do\n  @config %Config\nend", "lib/x.ex")
      assert ModuleAttrCollectionFormatting.run(src, []) == []
    end

    test "does not crash on an unterminated collection" do
      src = Credo.SourceFile.parse("defmodule MyMod do\n  @a [1,\n  2", "lib/x.ex")
      assert ModuleAttrCollectionFormatting.run(src, []) == []
    end
  end
end
