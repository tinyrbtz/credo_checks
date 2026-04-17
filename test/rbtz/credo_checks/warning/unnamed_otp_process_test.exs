defmodule Rbtz.CredoChecks.Warning.UnnamedOtpProcessTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Warning.UnnamedOtpProcess

  test "exposes metadata from `use Credo.Check`" do
    assert UnnamedOtpProcess.id() |> is_binary()
    assert UnnamedOtpProcess.category() |> is_atom()
    assert UnnamedOtpProcess.base_priority() |> is_atom()
    assert UnnamedOtpProcess.explanation() |> is_binary()
    assert UnnamedOtpProcess.params_defaults() |> is_list()
    assert UnnamedOtpProcess.params_names() |> is_list()
  end

  test "flags bare `DynamicSupervisor`" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [DynamicSupervisor]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> assert_issue()
  end

  test "flags `{Registry, keys: :unique}` without name" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [{Registry, keys: :unique}]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> assert_issue()
  end

  test "does not flag `{DynamicSupervisor, name: ...}`" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [{DynamicSupervisor, name: MyApp.Sup}]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> refute_issues()
  end

  test "does not flag non-Registry/DynamicSupervisor entries in a child_spec list" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [MyApp.Worker, {MyApp.Cache, ttl: 60}]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> refute_issues()
  end

  test "does not flag `{Registry, keys: :unique, name: ...}`" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [{Registry, keys: :unique, name: MyApp.Reg}]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> refute_issues()
  end

  test "does not flag `{DynamicSupervisor, [name: MyApp.Sup]}` (list-form opts)" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [{DynamicSupervisor, [name: MyApp.Sup, strategy: :one_for_one]}]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> refute_issues()
  end

  test "flags `{DynamicSupervisor, name: nil}`" do
    """
    defmodule MyApp.Application do
      def start(_type, _args) do
        children = [{DynamicSupervisor, name: nil}]
        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnnamedOtpProcess)
    |> assert_issue()
  end
end
