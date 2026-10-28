defmodule BluetabConnect.Px.RestTest do
  # The client is a named GenServer, so these tests cannot run concurrently.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BluetabConnect.Px.Rest

  @token "px_test_token"

  setup do
    start_supervised!({Rest,
     [
       base_url: "https://px.test",
       bearer_token: @token,
       # Req retries 5xx and transport errors with back-off (~7s); the error tests would crawl
       req_options: [plug: {Req.Test, __MODULE__}, retry: false]
     ]})

    :ok
  end

  defp stub(fun), do: Req.Test.stub(__MODULE__, fun)

  defp json_stub(status, body) do
    stub(fn conn -> Req.Test.json(Plug.Conn.put_status(conn, status), body) end)
  end

  # Stubs a 200 and reports the decoded query string of the request to the test process
  defp query_stub do
    test = self()

    stub(fn conn ->
      send(test, {:query, URI.decode_query(conn.query_string)})
      Req.Test.json(conn, %{"planned_hours" => [], "total" => 0})
    end)
  end

  describe "list_planned_hours/1" do
    test "requests /api/planned-hours with the token as a bearer token" do
      test = self()

      stub(fn conn ->
        send(
          test,
          {:request, conn.method, conn.request_path, conn.query_string, auth_header(conn)}
        )

        Req.Test.json(conn, %{"planned_hours" => [], "total" => 0})
      end)

      assert {:ok, %{"planned_hours" => [], "total" => 0}} = Rest.list_planned_hours()
      assert_received {:request, "GET", "/api/planned-hours", "", "Bearer " <> @token}
    end

    test "returns the planned hours and the total as sent by PX" do
      items = [
        %{
          "employee_number" => 10_001,
          "doc_num" => 12_345,
          "project_name" => "Example Project",
          "month" => "2026-03",
          "hours" => 80.0
        },
        %{
          "employee_number" => 10_001,
          "doc_num" => 12_345,
          "project_name" => "Example Project",
          "month" => "2026-04",
          "hours" => 40.5
        }
      ]

      json_stub(200, %{"planned_hours" => items, "total" => 2})

      assert {:ok, %{"planned_hours" => ^items, "total" => 2}} = Rest.list_planned_hours()
    end

    test "sends single filters as query params" do
      query_stub()

      assert {:ok, _} = Rest.list_planned_hours(employee_number: 10_001, doc_num: 12_345)

      assert_received {:query, %{"employee_number" => "10001", "doc_num" => "12345"} = query}
      refute Map.has_key?(query, "months")
    end

    test "sends list filters comma-separated" do
      query_stub()

      assert {:ok, _} =
               Rest.list_planned_hours(
                 employee_number: [10_001, 10_002],
                 doc_num: [12_345, 67_890],
                 months: ["2026-03", "2026-04"]
               )

      assert_received {:query,
                       %{
                         "employee_number" => "10001,10002",
                         "doc_num" => "12345,67890",
                         "months" => "2026-03,2026-04"
                       }}
    end

    test "formats dates as YYYY-MM months" do
      query_stub()

      assert {:ok, _} =
               Rest.list_planned_hours(
                 months: [~D[2026-03-15], ~N[2026-04-01 10:00:00], ~U[2026-05-31 23:59:59Z]]
               )

      assert_received {:query, %{"months" => "2026-03,2026-04,2026-05"}}

      assert {:ok, _} = Rest.list_planned_hours(months: ~D[2026-06-30])
      assert_received {:query, %{"months" => "2026-06"}}
    end

    test "leaves out nil filters and ignores unknown options" do
      test = self()

      stub(fn conn ->
        send(test, {:query, conn.query_string})
        Req.Test.json(conn, %{"planned_hours" => [], "total" => 0})
      end)

      assert {:ok, _} = Rest.list_planned_hours(employee_number: nil, months: nil, bogus: "x")
      assert_received {:query, ""}
    end

    test "encodes the filter values" do
      test = self()

      stub(fn conn ->
        send(test, {:raw_query, conn.query_string})
        Req.Test.json(conn, %{"planned_hours" => [], "total" => 0})
      end)

      assert {:ok, _} = Rest.list_planned_hours(months: ["2026-03", "2026-04"])
      assert_received {:raw_query, "months=2026-03%2C2026-04"}
    end

    test "returns an empty result without requesting PX when a filter is an empty list" do
      test = self()

      stub(fn conn ->
        send(test, :requested)
        Req.Test.json(conn, %{"planned_hours" => [%{}], "total" => 1})
      end)

      assert {:ok, %{"planned_hours" => [], "total" => 0}} =
               Rest.list_planned_hours(employee_number: [])

      assert {:ok, %{"planned_hours" => [], "total" => 0}} =
               Rest.list_planned_hours(employee_number: 10_001, months: [])

      refute_received :requested
    end

    test "maps 401 to :unauthorized" do
      json_stub(401, %{"error" => "Unauthorized"})

      log = capture_log(fn -> assert {:error, :unauthorized} = Rest.list_planned_hours() end)
      assert log =~ "Unauthorized listing planned hours"
    end

    test "maps 400 to :bad_request and logs the reason" do
      json_stub(400, %{"error" => "Invalid parameter(s): months"})

      log =
        capture_log(fn ->
          assert {:error, :bad_request} = Rest.list_planned_hours(months: "2026-13")
        end)

      assert log =~ "Invalid parameter(s): months"
    end

    test "maps other statuses and unexpected bodies to :list_planned_hours_error" do
      json_stub(500, %{"error" => "boom"})

      capture_log(fn ->
        assert {:error, :list_planned_hours_error} = Rest.list_planned_hours()
      end)

      json_stub(200, %{"unexpected" => true})

      capture_log(fn ->
        assert {:error, :list_planned_hours_error} = Rest.list_planned_hours()
      end)
    end

    test "maps transport errors to :list_planned_hours_error" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      capture_log(fn ->
        assert {:error, :list_planned_hours_error} = Rest.list_planned_hours()
      end)
    end

    test "does not log the token" do
      json_stub(401, %{"error" => "Unauthorized"})

      log = capture_log(fn -> Rest.list_planned_hours() end)
      refute log =~ @token
    end
  end

  describe "init/1" do
    test "requires base_url and bearer_token" do
      Process.flag(:trap_exit, true)

      assert {:error, {%KeyError{key: :bearer_token}, _}} =
               GenServer.start(Rest, base_url: "https://px.test")

      assert {:error, {%KeyError{key: :base_url}, _}} =
               GenServer.start(Rest, bearer_token: "t")
    end
  end

  defp auth_header(conn), do: conn |> Plug.Conn.get_req_header("authorization") |> List.first()
end
