defmodule BluetabConnect.Tempo.RestTest do
  # The client is a named GenServer, so these tests cannot run concurrently.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BluetabConnect.Tempo.Rest

  @api_key "tempo_test_key"

  setup do
    start_supervised!({Rest,
     [
       base_url: "https://tempo.test",
       api_key: @api_key,
       # Req retries 5xx and transport errors with back-off (~7s); the error tests would crawl
       req_options: [plug: {Req.Test, __MODULE__}, retry: false]
     ]})

    :ok
  end

  defp stub(fun), do: Req.Test.stub(__MODULE__, fun)

  defp json_stub(status, body) do
    stub(fn conn -> Req.Test.json(Plug.Conn.put_status(conn, status), body) end)
  end

  describe "list_holidays/1" do
    test "requests /api/v1/holidays with the API key as a bearer token" do
      test = self()

      stub(fn conn ->
        send(
          test,
          {:request, conn.method, conn.request_path, conn.query_string, auth_header(conn)}
        )

        Req.Test.json(conn, %{"items" => [], "total" => 0})
      end)

      assert {:ok, []} = Rest.list_holidays()
      assert_received {:request, "GET", "/api/v1/holidays", "", "Bearer " <> @api_key}
    end

    test "returns the items as sent by Tempo" do
      item = %{
        "calendar_code" => "ESP",
        "date" => "2026-01-01",
        "holiday_code" => "NEW_YEAR",
        "name" => "New Year"
      }

      json_stub(200, %{"items" => [item], "total" => 1})

      assert {:ok, [^item]} = Rest.list_holidays()
    end

    test "sends the filters as query params, formatting dates as ISO 8601" do
      test = self()

      stub(fn conn ->
        send(test, {:query, URI.decode_query(conn.query_string)})
        Req.Test.json(conn, %{"items" => [], "total" => 0})
      end)

      assert {:ok, []} =
               Rest.list_holidays(
                 calendar_code: "ESP",
                 date_from: ~D[2026-01-01],
                 date_to: ~U[2026-12-31 23:59:59Z]
               )

      assert_received {:query,
                       %{
                         "calendar_code" => "ESP",
                         "date_from" => "2026-01-01",
                         "date_to" => "2026-12-31"
                       }}
    end

    test "accepts dates already formatted as strings" do
      test = self()

      stub(fn conn ->
        send(test, {:query, URI.decode_query(conn.query_string)})
        Req.Test.json(conn, %{"items" => [], "total" => 0})
      end)

      assert {:ok, []} = Rest.list_holidays(date_from: "2026-03-01")
      assert_received {:query, %{"date_from" => "2026-03-01"}}
    end

    test "leaves out nil filters and ignores unknown options" do
      test = self()

      stub(fn conn ->
        send(test, {:query, conn.query_string})
        Req.Test.json(conn, %{"items" => [], "total" => 0})
      end)

      assert {:ok, []} = Rest.list_holidays(calendar_code: nil, date_from: nil, bogus: "x")
      assert_received {:query, ""}
    end

    test "encodes special characters in filter values" do
      test = self()

      stub(fn conn ->
        send(test, {:query, URI.decode_query(conn.query_string)})
        Req.Test.json(conn, %{"items" => [], "total" => 0})
      end)

      assert {:ok, []} = Rest.list_holidays(calendar_code: "A&B=C D")
      assert_received {:query, %{"calendar_code" => "A&B=C D"}}
    end

    test "maps 401 to :unauthorized" do
      json_stub(401, %{"error" => "Unauthorized"})

      log = capture_log(fn -> assert {:error, :unauthorized} = Rest.list_holidays() end)
      assert log =~ "Unauthorized listing holidays"
    end

    test "maps 403 to :forbidden and says the key needs the holidays scope" do
      json_stub(403, %{"error" => "Forbidden"})

      log = capture_log(fn -> assert {:error, :forbidden} = Rest.list_holidays() end)
      assert log =~ "holidays scope"
    end

    test "maps 400 to :bad_request" do
      json_stub(400, %{"error" => "Invalid parameter(s): date_from"})

      log = capture_log(fn -> assert {:error, :bad_request} = Rest.list_holidays() end)
      assert log =~ "date_from"
    end

    test "maps other statuses and unexpected bodies to :list_holidays_error" do
      json_stub(500, %{"error" => "boom"})
      capture_log(fn -> assert {:error, :list_holidays_error} = Rest.list_holidays() end)

      json_stub(200, %{"unexpected" => true})
      capture_log(fn -> assert {:error, :list_holidays_error} = Rest.list_holidays() end)
    end

    test "maps transport errors to :list_holidays_error" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      capture_log(fn -> assert {:error, :list_holidays_error} = Rest.list_holidays() end)
    end

    test "does not log the API key" do
      json_stub(403, %{"error" => "Forbidden"})

      log = capture_log(fn -> Rest.list_holidays() end)
      refute log =~ @api_key
    end
  end

  describe "labor_claims_summary/1" do
    @summary_item %{
      "employee_id" => 92,
      "project_id" => 12_345,
      "status" => "approved",
      "total_hours" => 80.0,
      "entry_count" => 10
    }

    # Stubs a 200 and reports the decoded query string of the request to the test process
    defp summary_query_stub do
      test = self()

      stub(fn conn ->
        send(test, {:query, URI.decode_query(conn.query_string)})
        Req.Test.json(conn, %{"items" => []})
      end)
    end

    # A stub that tells the test if Tempo was asked at all
    defp asked_stub do
      test = self()

      stub(fn conn ->
        send(test, :asked)
        Req.Test.json(conn, %{"items" => []})
      end)
    end

    test "requests /api/v1/labor-claims/summary with the key as a bearer token, as JSON:API" do
      test = self()

      stub(fn conn ->
        send(
          test,
          {:request, conn.method, conn.request_path, conn.query_string, auth_header(conn),
           Plug.Conn.get_req_header(conn, "accept")}
        )

        Req.Test.json(conn, %{"items" => []})
      end)

      assert {:ok, []} = Rest.labor_claims_summary()

      assert_received {:request, "GET", "/api/v1/labor-claims/summary", "", "Bearer " <> @api_key,
                       ["application/vnd.api+json"]}
    end

    test "returns the items as sent by Tempo" do
      json_stub(200, %{"items" => [@summary_item]})

      assert {:ok, [@summary_item]} = Rest.labor_claims_summary()
    end

    test "reads the items at the root, under data, or under data.attributes" do
      json_stub(200, %{"data" => %{"items" => [@summary_item]}})
      assert {:ok, [@summary_item]} = Rest.labor_claims_summary()

      json_stub(200, %{"data" => %{"attributes" => %{"items" => [@summary_item]}}})
      assert {:ok, [@summary_item]} = Rest.labor_claims_summary()
    end

    test "sends the dates as ISO 8601, and the grouping comma-separated" do
      summary_query_stub()

      assert {:ok, _} =
               Rest.labor_claims_summary(
                 date_from: ~D[2026-03-01],
                 date_to: "2026-03-31",
                 group_by: [:employee_id, :project_id, :status]
               )

      assert_received {:query,
                       %{
                         "date_from" => "2026-03-01",
                         "date_to" => "2026-03-31",
                         "group_by" => "employee_id,project_id,status"
                       }}
    end

    test "sends one id or a list of ids, comma-separated, and one status" do
      summary_query_stub()

      assert {:ok, _} =
               Rest.labor_claims_summary(
                 employee_id: 92,
                 project_ids: [12_345, 67_890],
                 status: :approved
               )

      assert_received {:query,
                       %{
                         "employee_id" => "92",
                         "project_ids" => "12345,67890",
                         "status" => "approved"
                       }}
    end

    test "leaves out nil filters and empty lists, and ignores unknown options" do
      test = self()

      stub(fn conn ->
        send(test, {:query, conn.query_string})
        Req.Test.json(conn, %{"items" => []})
      end)

      assert {:ok, _} =
               Rest.labor_claims_summary(
                 date_from: nil,
                 employee_ids: [],
                 group_by: [],
                 status: nil,
                 bogus: "x"
               )

      assert_received {:query, ""}
    end

    test "refuses what Tempo would ignore, without asking Tempo" do
      asked_stub()

      capture_log(fn ->
        # Tempo reads an invalid date as no date, and would sum every day
        assert {:error, :bad_request} = Rest.labor_claims_summary(date_from: "2026-06-31")
        assert {:error, :bad_request} = Rest.labor_claims_summary(date_to: "soon")
        assert {:error, :bad_request} = Rest.labor_claims_summary(date_from: 20_260_301)
        # ... and a grouping or a status it does not know as no grouping, or no claim
        assert {:error, :bad_request} = Rest.labor_claims_summary(group_by: [:employee])
        assert {:error, :bad_request} = Rest.labor_claims_summary(group_by: "employee_id")
        assert {:error, :bad_request} = Rest.labor_claims_summary(status: "approvd")
        assert {:error, :bad_request} = Rest.labor_claims_summary(status: ["approved", "draft"])
      end)

      refute_received :asked
    end

    test "maps 401 to :unauthorized" do
      json_stub(401, %{"error" => "Unauthorized"})

      log = capture_log(fn -> assert {:error, :unauthorized} = Rest.labor_claims_summary() end)
      assert log =~ "Unauthorized reading labor claims"
    end

    test "maps 403 to :forbidden and says which scope the key needs" do
      json_stub(403, %{"error" => "Forbidden"})

      log = capture_log(fn -> assert {:error, :forbidden} = Rest.labor_claims_summary() end)
      assert log =~ "labor_claims scope"
    end

    test "maps 400 and 422 to :bad_request" do
      for status <- [400, 422] do
        json_stub(status, %{"error" => "bad"})

        capture_log(fn -> assert {:error, :bad_request} = Rest.labor_claims_summary() end)
      end
    end

    test "maps other statuses, transport errors and an answer that is not the documented one" do
      json_stub(500, %{"error" => "boom"})

      capture_log(fn ->
        assert {:error, :labor_claims_summary_error} = Rest.labor_claims_summary()
      end)

      for body <- [%{"unexpected" => true}, %{"items" => "none"}, %{"data" => "x"}, []] do
        json_stub(200, body)

        capture_log(fn ->
          assert {:error, :labor_claims_summary_error} = Rest.labor_claims_summary()
        end)
      end

      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      capture_log(fn ->
        assert {:error, :labor_claims_summary_error} = Rest.labor_claims_summary()
      end)
    end

    test "does not log the key" do
      json_stub(403, %{"error" => "Forbidden"})

      log = capture_log(fn -> Rest.labor_claims_summary() end)
      refute log =~ @api_key
    end
  end

  describe "labor_claims_date_range/1" do
    test "requests /api/v1/labor-claims/date-range and returns the first and last date" do
      test = self()

      stub(fn conn ->
        send(test, {:request, conn.method, conn.request_path, auth_header(conn)})
        Req.Test.json(conn, %{"min_date" => "2026-01-15", "max_date" => "2026-04-07"})
      end)

      assert {:ok, %{"min_date" => "2026-01-15", "max_date" => "2026-04-07"}} =
               Rest.labor_claims_date_range()

      assert_received {:request, "GET", "/api/v1/labor-claims/date-range", "Bearer " <> @api_key}
    end

    test "answers nil dates when no claim matches, and reads them under data too" do
      json_stub(200, %{"min_date" => nil, "max_date" => nil})
      assert {:ok, %{"min_date" => nil, "max_date" => nil}} = Rest.labor_claims_date_range()

      json_stub(200, %{"data" => %{"min_date" => "2026-01-15", "max_date" => "2026-04-07"}})
      assert {:ok, %{"min_date" => "2026-01-15"}} = Rest.labor_claims_date_range()
    end

    test "sends the filters, and not a grouping" do
      test = self()

      stub(fn conn ->
        send(test, {:query, URI.decode_query(conn.query_string)})
        Req.Test.json(conn, %{"min_date" => nil, "max_date" => nil})
      end)

      assert {:ok, _} =
               Rest.labor_claims_date_range(
                 employee_id: 92,
                 date_to: ~D[2026-04-07],
                 group_by: [:employee_id]
               )

      assert_received {:query, %{"employee_id" => "92", "date_to" => "2026-04-07"} = query}
      refute Map.has_key?(query, "group_by")
    end

    test "refuses an invalid date without asking Tempo" do
      test = self()

      stub(fn conn ->
        send(test, :asked)
        Req.Test.json(conn, %{"min_date" => nil, "max_date" => nil})
      end)

      capture_log(fn ->
        assert {:error, :bad_request} = Rest.labor_claims_date_range(date_from: "2026-02-30")
      end)

      refute_received :asked
    end

    test "maps the errors like the summary does" do
      json_stub(401, %{"error" => "Unauthorized"})
      capture_log(fn -> assert {:error, :unauthorized} = Rest.labor_claims_date_range() end)

      json_stub(403, %{"error" => "Forbidden"})
      capture_log(fn -> assert {:error, :forbidden} = Rest.labor_claims_date_range() end)

      json_stub(500, %{"error" => "boom"})

      capture_log(fn ->
        assert {:error, :labor_claims_date_range_error} = Rest.labor_claims_date_range()
      end)

      json_stub(200, %{"unexpected" => true})

      capture_log(fn ->
        assert {:error, :labor_claims_date_range_error} = Rest.labor_claims_date_range()
      end)
    end
  end

  describe "init/1" do
    test "requires base_url and api_key" do
      Process.flag(:trap_exit, true)

      assert {:error, {%KeyError{key: :api_key}, _}} =
               GenServer.start(Rest, base_url: "https://tempo.test")

      assert {:error, {%KeyError{key: :base_url}, _}} = GenServer.start(Rest, api_key: "k")
    end
  end

  defp auth_header(conn), do: conn |> Plug.Conn.get_req_header("authorization") |> List.first()
end
