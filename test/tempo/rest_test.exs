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
