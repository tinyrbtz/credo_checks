defmodule Rbtz.CredoChecks.Warning.UnmatchedRepoUpdateAllTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.UnmatchedRepoUpdateAll

  test "exposes metadata from `use Credo.Check`" do
    assert UnmatchedRepoUpdateAll.id() |> is_binary()
    assert UnmatchedRepoUpdateAll.category() |> is_atom()
    assert UnmatchedRepoUpdateAll.base_priority() |> is_atom()
    assert UnmatchedRepoUpdateAll.explanations()[:check] |> is_binary()
    assert UnmatchedRepoUpdateAll.param_defaults() |> is_list()
    assert UnmatchedRepoUpdateAll.param_names() |> is_list()
  end

  defp run_lib_file(source) do
    source
    |> to_source_file("lib/my_app/posts.ex")
    |> run_check(UnmatchedRepoUpdateAll)
  end

  test "flags a dropped `update_all` statement" do
    """
    defmodule MyApp.Posts do
      def archive(post_id) do
        Post
        |> where(id: ^post_id)
        |> Repo.update_all(set: [archived: true])

        :ok
      end
    end
    """
    |> run_lib_file()
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.update_all"
      assert issue.line_no == 5
    end)
  end

  test "flags unpiped calls on a namespaced Repo" do
    """
    defmodule MyApp.Posts do
      def archive(query) do
        MyApp.Repo.update_all(query, set: [archived: true])
        :ok
      end
    end
    """
    |> run_lib_file()
    |> assert_issue()
  end

  test "flags matches against underscore variables" do
    """
    defmodule MyApp.Posts do
      def archive(query) do
        _ = Repo.update_all(query, set: [archived: true])
        _count = Repo.update_all(query, set: [archived: true])
      end
    end
    """
    |> run_lib_file()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "does not flag matched, assigned, or returned results" do
    """
    defmodule MyApp.Posts do
      def archive(query) do
        {1, nil} = Repo.update_all(query, set: [archived: true])
        {_, nil} = query |> Repo.update_all(set: [archived: true])
        {count, _} = Repo.update_all(query, set: [archived: true])
        result = Repo.update_all(query, set: [archived: true])
        {count, result}
      end

      def bump(query), do: Repo.update_all(query, inc: [views: 1])

      def touch(query) do
        Logger.metadata(query: query)
        Repo.update_all(query, set: [touched: true])
      end
    end
    """
    |> run_lib_file()
    |> refute_issues()
  end

  test "does not flag `update_all` on modules not named Repo" do
    """
    defmodule MyApp.Posts do
      def archive(multi, query) do
        Ecto.Multi.update_all(multi, :archive, query, set: [archived: true])
        multi
      end
    end
    """
    |> run_lib_file()
    |> refute_issues()
  end

  test "does not flag files outside lib/" do
    """
    Repo.update_all(Post, set: [archived: true])
    :ok
    """
    |> to_source_file("test/my_app/posts_test.exs")
    |> run_check(UnmatchedRepoUpdateAll)
    |> refute_issues()
  end
end
