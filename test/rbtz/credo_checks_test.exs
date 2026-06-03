defmodule Rbtz.CredoChecksTest do
  use ExUnit.Case, async: true

  alias Rbtz.CredoChecks

  defp modules(checks), do: Enum.map(checks, &elem(&1, 0))

  describe "all/0" do
    test "returns a non-empty list of {check_module, opts} tuples" do
      checks = CredoChecks.all()

      assert checks != []
      assert Enum.all?(checks, fn {mod, opts} -> is_atom(mod) and is_list(opts) end)
    end

    test "every returned module is a Credo check" do
      for {mod, _opts} <- CredoChecks.all() do
        assert function_exported?(mod, :run, 2)

        behaviours =
          mod.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

        assert Credo.Check in behaviours
      end
    end

    test "defaults every check to empty options" do
      assert Enum.all?(CredoChecks.all(), fn {_mod, opts} -> opts == [] end)
    end

    test "includes checks across all categories, including PreferNilEquality" do
      modules = modules(CredoChecks.all())

      assert Rbtz.CredoChecks.Design.BareScriptInHeex in modules
      assert Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering in modules
      assert Rbtz.CredoChecks.Readability.PreferNilEquality in modules
      assert Rbtz.CredoChecks.Refactor.RedundantThen in modules
      assert Rbtz.CredoChecks.Warning.UnnamedOtpProcess in modules
    end

    test "excludes helper modules and the mix project" do
      modules = modules(CredoChecks.all())

      refute Rbtz.CredoChecks.HeexSource in modules
      refute Rbtz.CredoChecks.MigrationSource in modules
      refute Rbtz.CredoChecks.PhxAttrRequiresId in modules
      refute Rbtz.CredoChecks.MixProject in modules
    end

    test "is sorted by module name" do
      modules = modules(CredoChecks.all())

      assert modules == Enum.sort(modules)
    end

    test "all() == all_replacing([])" do
      assert CredoChecks.all() == CredoChecks.all_replacing([])
    end
  end

  describe "all_replacing/1" do
    test "replaces options for the matching check, leaving others untouched" do
      result =
        CredoChecks.all_replacing([
          {Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering, exclude: ["utf8"]}
        ])

      assert {Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering, [exclude: ["utf8"]]} in result
      assert {Rbtz.CredoChecks.Design.BareScriptInHeex, []} in result
    end

    test "disables a check when options are false" do
      result = CredoChecks.all_replacing([{Rbtz.CredoChecks.Design.PreferLogsterInLib, false}])

      assert {Rbtz.CredoChecks.Design.PreferLogsterInLib, false} in result
    end

    test "applies multiple replacements" do
      result =
        CredoChecks.all_replacing([
          {Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering, exclude: ["utf8"]},
          {Rbtz.CredoChecks.Design.PreferLogsterInLib, false}
        ])

      assert {Rbtz.CredoChecks.Readability.SnakeCaseVariableNumbering, [exclude: ["utf8"]]} in result
      assert {Rbtz.CredoChecks.Design.PreferLogsterInLib, false} in result
    end

    test "preserves the overall length and order of the check list" do
      base = CredoChecks.all()
      replaced = CredoChecks.all_replacing([{Rbtz.CredoChecks.Design.PreferLogsterInLib, false}])

      assert length(base) == length(replaced)
      assert modules(base) == modules(replaced)
    end

    test "raises when a replacement names an unknown check" do
      assert_raise ArgumentError, ~r/unknown check/, fn ->
        CredoChecks.all_replacing([{Rbtz.CredoChecks.Readability.Nope, []}])
      end
    end

    test "the raised error names the offending module" do
      assert_raise ArgumentError, ~r/Rbtz\.CredoChecks\.Readability\.Nope/, fn ->
        CredoChecks.all_replacing([{Rbtz.CredoChecks.Readability.Nope, []}])
      end
    end
  end
end
