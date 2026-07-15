defmodule Rbtz.CredoChecks.TestSource do
  @moduledoc """
  Shared helpers for Credo checks that only want to run against test files.

  A path counts as a test file when its basename ends in `_test.exs` or when
  any path segment is `test` (covers `test/`, `apps/*/test/`, etc.).
  """

  @doc """
  Returns `true` when `filename` looks like a test file.
  """
  def test_file?(filename) when is_binary(filename) do
    String.ends_with?(filename, "_test.exs") or has_test_segment?(filename)
  end

  def test_file?(_), do: false

  defp has_test_segment?(filename) do
    filename |> Path.expand() |> Path.split() |> Enum.member?("test")
  end
end
