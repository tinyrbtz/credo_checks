defmodule Rbtz.CredoChecks.Readability.MimicCallStyleTest do
  use Credo.Test.Case, async: false

  alias Rbtz.CredoChecks.Readability.MimicCallStyle

  test "exposes metadata from `use Credo.Check`" do
    assert MimicCallStyle.id() |> is_binary()
    assert MimicCallStyle.category() |> is_atom()
    assert MimicCallStyle.base_priority() |> is_atom()
    assert MimicCallStyle.explanations()[:check] |> is_binary()
    assert MimicCallStyle.param_defaults() |> is_list()
    assert MimicCallStyle.param_names() |> is_list()
  end

  defp run_test_file(source) do
    source
    |> to_source_file("test/m_test.exs")
    |> run_check(MimicCallStyle, detect_dependency: false)
  end

  test "flags unpiped `expect(Module, :fun, ...)`" do
    """
    expect(File, :read, fn _ -> {:ok, "contents"} end)
    """
    |> run_test_file()
    |> assert_issue(fn issue ->
      assert issue.trigger == "expect"
      assert issue.line_no == 1
    end)
  end

  test "flags unpiped `stub(Module, :fun, ...)`" do
    """
    stub(File, :exists?, fn _ -> true end)
    """
    |> run_test_file()
    |> assert_issue(fn issue -> assert issue.trigger == "stub" end)
  end

  test "flags unpiped `expect` with a call count" do
    """
    expect(File, :read, 2, fn _ -> {:ok, "contents"} end)
    """
    |> run_test_file()
    |> assert_issue()
  end

  test "flags `Mimic.`-qualified unpiped calls" do
    """
    Mimic.stub(File, :exists?, fn _ -> true end)
    """
    |> run_test_file()
    |> assert_issue(fn issue -> assert issue.trigger == "stub" end)
  end

  test "flags unpiped calls on `__MODULE__` and Erlang modules" do
    """
    expect(__MODULE__, :read, fn _ -> :ok end)
    stub(:crypto, :strong_rand_bytes, fn _ -> <<0>> end)
    """
    |> run_test_file()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "flags piped `reject(:fun, arity)`" do
    """
    File |> reject(:write, 2)
    """
    |> run_test_file()
    |> assert_issue(fn issue -> assert issue.trigger == "reject" end)
  end

  test "flags `reject(Module, :fun, arity)`" do
    """
    reject(File, :write, 2)
    """
    |> run_test_file()
    |> assert_issue(fn issue -> assert issue.trigger == "reject" end)
  end

  test "flags `Mimic.reject(Module, :fun, arity)`" do
    """
    Mimic.reject(File, :write, 2)
    """
    |> run_test_file()
    |> assert_issue()
  end

  test "does not flag piped and chained `expect` / `stub`" do
    """
    File
    |> stub(:exists?, fn _ -> true end)
    |> expect(:read, 2, fn _ -> {:ok, "contents"} end)
    """
    |> run_test_file()
    |> refute_issues()
  end

  test "does not flag `reject` with a function capture" do
    """
    reject(&File.write/2)
    Mimic.reject(&File.write/2)
    """
    |> run_test_file()
    |> refute_issues()
  end

  test "does not flag `stub(Module)`" do
    """
    stub(File)
    """
    |> run_test_file()
    |> refute_issues()
  end

  test "does not flag same-named calls whose first argument isn't a module" do
    """
    expect(value, :read, fn _ -> :ok end)
    reject(value, :write, 2)
    """
    |> run_test_file()
    |> refute_issues()
  end

  test "does not flag files outside test/" do
    """
    expect(File, :read, fn _ -> {:ok, "contents"} end)
    """
    |> to_source_file("lib/m.ex")
    |> run_check(MimicCallStyle, detect_dependency: false)
    |> refute_issues()
  end

  @tag :tmp_dir
  test "runs when the project's mix.exs lists :mimic in any env", %{tmp_dir: tmp_dir} do
    tmp_dir
    |> Path.join("mix.exs")
    |> File.write!("""
    defmodule MimicCallStyleFixture.MixProject do
      use Mix.Project

      def project do
        [app: :mimic_call_style_fixture, version: "0.1.0", deps: [{:mimic, "~> 2.0", only: :test}]]
      end
    end
    """)

    Mix.Project.in_project(:mimic_call_style_fixture, tmp_dir, fn _ ->
      """
      expect(File, :read, fn _ -> {:ok, "contents"} end)
      """
      |> to_source_file("test/m_test.exs")
      |> run_check(MimicCallStyle)
      |> assert_issue()
    end)
  end

  test "runs when the Mimic module is loadable" do
    Code.compile_string("defmodule Mimic do\nend")

    try do
      """
      expect(File, :read, fn _ -> {:ok, "contents"} end)
      """
      |> to_source_file("test/m_test.exs")
      |> run_check(MimicCallStyle)
      |> assert_issue()
    after
      :code.delete(Mimic)
      :code.purge(Mimic)
    end
  end

  test "does nothing when the project doesn't depend on Mimic" do
    """
    expect(File, :read, fn _ -> {:ok, "contents"} end)
    """
    |> to_source_file("test/m_test.exs")
    |> run_check(MimicCallStyle)
    |> refute_issues()
  end
end
