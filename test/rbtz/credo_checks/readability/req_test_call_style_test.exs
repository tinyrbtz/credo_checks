defmodule Rbtz.CredoChecks.Readability.ReqTestCallStyleTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.ReqTestCallStyle

  test "exposes metadata from `use Credo.Check`" do
    assert ReqTestCallStyle.id() |> is_binary()
    assert ReqTestCallStyle.category() |> is_atom()
    assert ReqTestCallStyle.base_priority() |> is_atom()
    assert ReqTestCallStyle.explanations()[:check] |> is_binary()
    assert ReqTestCallStyle.param_defaults() |> is_list()
    assert ReqTestCallStyle.param_names() |> is_list()
  end

  defp run_test_file(source) do
    source
    |> to_source_file("test/m_test.exs")
    |> run_check(ReqTestCallStyle)
  end

  test "flags piped `Req.Test.expect`" do
    """
    MyStub
    |> Req.Test.expect(&Req.Test.json(&1, %{"ok" => true}))
    """
    |> run_test_file()
    |> assert_issue(fn issue ->
      assert issue.trigger == "Req.Test.expect"
      assert issue.line_no == 2
    end)
  end

  test "flags piped `Req.Test.stub`" do
    """
    MyStub |> Req.Test.stub(&Req.Test.json(&1, %{"ok" => true}))
    """
    |> run_test_file()
    |> assert_issue(fn issue -> assert issue.trigger == "Req.Test.stub" end)
  end

  test "flags every call in a piped chain" do
    """
    MyStub
    |> Req.Test.expect(&Req.Test.json(&1, %{"page" => 1}))
    |> Req.Test.expect(&Req.Test.json(&1, %{"page" => 2}))
    """
    |> run_test_file()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "does not flag unpiped calls" do
    """
    Req.Test.expect(MyStub, &Req.Test.json(&1, %{"ok" => true}))
    Req.Test.stub(MyStub, fn conn -> conn |> Req.Test.json(%{"ok" => true}) end)
    """
    |> run_test_file()
    |> refute_issues()
  end

  test "does not flag files outside test/" do
    """
    MyStub |> Req.Test.stub(&Req.Test.json(&1, %{"ok" => true}))
    """
    |> to_source_file("lib/m.ex")
    |> run_check(ReqTestCallStyle)
    |> refute_issues()
  end
end
