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
    segments = filename |> Path.expand() |> Path.split()
    String.ends_with?(filename, "_test.exs") or "test" in segments
  end

  def test_file?(_), do: false
end
