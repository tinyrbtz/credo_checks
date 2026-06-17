defmodule Rbtz.CredoChecks.Readability.AtomHttpStatusCodesTest do
  use Credo.Test.Case, async: true

  alias Rbtz.CredoChecks.Readability.AtomHttpStatusCodes

  test "exposes metadata from `use Credo.Check`" do
    assert AtomHttpStatusCodes.id() |> is_binary()
    assert AtomHttpStatusCodes.category() |> is_atom()
    assert AtomHttpStatusCodes.base_priority() |> is_atom()
    assert AtomHttpStatusCodes.explanation() |> is_binary()
    assert AtomHttpStatusCodes.params_defaults() |> is_list()
    assert AtomHttpStatusCodes.params_names() |> is_list()
  end

  test "flags `put_status(conn, 404)`" do
    """
    defmodule MyController do
      def show(conn, _) do
        conn |> put_status(404)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `send_resp(conn, 200, body)`" do
    """
    defmodule MyController do
      def show(conn, body) do
        send_resp(conn, 200, body)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags piped `send_resp` with multiple explicit args" do
    # Piped form: the `conn` is the pipe LHS, so the RHS args are `[200, body]`
    # — this locks in the `pos - 1` adjustment in `maybe_flag/5`.
    """
    defmodule MyController do
      def show(conn, body) do
        conn |> send_resp(200, body)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `Plug.Conn.resp(conn, 500, msg)`" do
    """
    defmodule MyController do
      def show(conn, msg) do
        Plug.Conn.resp(conn, 500, msg)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags piped `json_response(200)`" do
    """
    defmodule MyControllerTest do
      test "status" do
        conn
        |> get(~p"/status")
        |> json_response(200)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `json_response(conn, 200)`" do
    """
    defmodule MyControllerTest do
      test "status" do
        json_response(conn, 200)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `json_response` nested in an assert" do
    """
    defmodule MyControllerTest do
      test "status" do
        assert json_response(conn, 200) == %{}
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `html_response(conn, 200)`" do
    """
    defmodule MyControllerTest do
      test "status" do
        html_response(conn, 200)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `response(conn, 200)`" do
    """
    defmodule MyControllerTest do
      test "status" do
        response(conn, 200)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "flags `redirected_to(conn, 302)`" do
    """
    defmodule MyControllerTest do
      test "redirect" do
        redirected_to(conn, 302)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> assert_issue()
  end

  test "does not flag atom status codes" do
    """
    defmodule MyController do
      def show(conn, body) do
        conn |> put_status(:not_found)
        send_resp(conn, :ok, body)
        json_response(conn, :ok)
        redirected_to(conn, :found)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> refute_issues()
  end

  test "does not flag `redirected_to(conn)` with no status arg" do
    """
    defmodule MyControllerTest do
      test "redirect" do
        redirected_to(conn)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> refute_issues()
  end

  test "does not flag integers outside HTTP range" do
    """
    defmodule M do
      def go, do: send_resp(:conn, 99, "")
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> refute_issues()
  end

  test "walks past anonymous function calls without flagging them" do
    """
    defmodule M do
      def go(f, conn) do
        f.(conn, 200)
      end
    end
    """
    |> to_source_file()
    |> run_check(AtomHttpStatusCodes)
    |> refute_issues()
  end

  test "returns no issues when source cannot be parsed" do
    src = Credo.SourceFile.parse("defmodule X do", "lib/x.ex")
    assert AtomHttpStatusCodes.run(src, []) == []
  end
end
