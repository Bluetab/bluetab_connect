defmodule BluetabConnect.Gedes.RestTest do
  # The client is a named GenServer, so these tests cannot run concurrently.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BluetabConnect.Gedes.Rest

  @api_key "gedes_test_key"

  setup do
    start_supervised!({Rest,
     [
       base_url: "https://gedes.test",
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

  defp page(items, total \\ nil),
    do: %{"items" => items, "total" => total || length(items), "limit" => 500, "offset" => 0}

  # Serves `all` the way Gedes does: `limit`/`offset` slice, `total` is the whole list.
  defp paged_stub(all, test \\ self()) do
    stub(fn conn ->
      query = URI.decode_query(conn.query_string)
      limit = String.to_integer(query["limit"])
      offset = String.to_integer(query["offset"])
      send(test, {:page, query})

      Req.Test.json(conn, %{
        "items" => all |> Enum.drop(offset) |> Enum.take(limit),
        "total" => length(all),
        "limit" => limit,
        "offset" => offset
      })
    end)
  end

  defp auth_header(conn), do: conn |> Plug.Conn.get_req_header("authorization") |> List.first()

  @person_filters [
    user_id: "11111111-1111-1111-1111-111111111111",
    user_email: "ann@example.com",
    period_id: 3,
    evaluator_id: "22222222-2222-2222-2222-222222222222",
    evaluator_email: "bob@example.com",
    status: :acknowledged
  ]

  # {function, path, resource, error, API key scope it needs, a sample of the filters it takes}
  for {fun, path, resource, error, scope, filters} <- [
        {:list_briefings, "/api/v1/briefings", "briefings", :list_briefings_error, "briefings",
         @person_filters},
        {:list_evaluations, "/api/v1/evaluations", "evaluations", :list_evaluations_error,
         "evaluations", @person_filters},
        {:list_careers, "/api/v1/careers", "careers", :list_careers_error, "careers", []},
        {:list_categories, "/api/v1/categories", "categories", :list_categories_error, "careers",
         [career_id: 3]}
      ] do
    describe "#{fun}/1" do
      test "requests #{path} with the API key as a bearer token" do
        test = self()

        stub(fn conn ->
          send(test, {:request, conn.method, conn.request_path, auth_header(conn)})
          Req.Test.json(conn, page([]))
        end)

        assert {:ok, []} = apply(Rest, unquote(fun), [])
        assert_received {:request, "GET", unquote(path), "Bearer " <> @api_key}
      end

      test "returns the items as sent by Gedes" do
        item = %{"id" => "6f1c", "status" => "published", "user" => %{"email" => "a@b.c"}}
        json_stub(200, page([item]))

        assert {:ok, [^item]} = apply(Rest, unquote(fun), [])
      end

      if filters != [] do
        test "sends the filters as query params" do
          test = self()

          stub(fn conn ->
            send(test, {:query, URI.decode_query(conn.query_string)})
            Req.Test.json(conn, page([]))
          end)

          assert {:ok, []} = apply(Rest, unquote(fun), [unquote(filters)])

          expected =
            unquote(filters)
            |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
            |> Map.merge(%{"limit" => "500", "offset" => "0"})

          assert_received {:query, ^expected}
        end

        test "leaves out nil and blank filters" do
          test = self()

          stub(fn conn ->
            send(test, {:query, URI.decode_query(conn.query_string)})
            Req.Test.json(conn, page([]))
          end)

          keys = Keyword.keys(unquote(filters))
          nils = Enum.map(keys, &{&1, nil})
          blanks = Enum.map(keys, &{&1, "  "})

          assert {:ok, []} = apply(Rest, unquote(fun), [nils])
          assert {:ok, []} = apply(Rest, unquote(fun), [blanks])

          for _ <- 1..2 do
            assert_received {:query, query}
            assert Map.keys(query) |> Enum.sort() == ["limit", "offset"]
          end
        end

        test "encodes special characters in filter values" do
          test = self()

          stub(fn conn ->
            send(test, {:query, URI.decode_query(conn.query_string)})
            Req.Test.json(conn, page([]))
          end)

          [{key, _} | _] = unquote(filters)

          assert {:ok, []} = apply(Rest, unquote(fun), [[{key, "a&b=c d@example.com"}]])
          assert_received {:query, query}
          assert query[to_string(key)] == "a&b=c d@example.com"
        end

        test "keeps the filters on every page" do
          paged_stub(for(n <- 1..3, do: %{"id" => n}))
          [{key, _} | _] = unquote(filters)

          assert {:ok, [_, _, _]} = apply(Rest, unquote(fun), [[{key, 7}, {:page_size, 1}]])

          for offset <- ["0", "1", "2"] do
            assert_received {:page, %{"offset" => ^offset} = query}
            assert query[to_string(key)] == "7"
          end
        end
      end

      test "raises on an unknown option instead of fetching everything" do
        test = self()

        stub(fn conn ->
          send(test, :requested)
          Req.Test.json(conn, page([]))
        end)

        assert_raise ArgumentError, ~r/user_idd/, fn ->
          apply(Rest, unquote(fun), [[user_idd: "11111111-1111-1111-1111-111111111111"]])
        end

        refute_received :requested
      end

      test "rejects a page_size outside 1..500" do
        for bad <- [0, -1, 501, "10", 1.5] do
          assert_raise ArgumentError, ~r/page_size/, fn ->
            apply(Rest, unquote(fun), [[page_size: bad]])
          end
        end
      end

      test "follows the pages and returns every item in order" do
        items = for n <- 1..5, do: %{"id" => "item-#{n}"}
        paged_stub(items)

        assert {:ok, ^items} = apply(Rest, unquote(fun), [[page_size: 2]])

        assert_received {:page, %{"limit" => "2", "offset" => "0"}}
        assert_received {:page, %{"limit" => "2", "offset" => "2"}}
        assert_received {:page, %{"limit" => "2", "offset" => "4"}}
        refute_received {:page, _}
      end

      test "does one request when everything fits in a page" do
        paged_stub([%{"id" => 1}, %{"id" => 2}])

        assert {:ok, [_, _]} = apply(Rest, unquote(fun), [])

        assert_received {:page, %{"offset" => "0"}}
        refute_received {:page, _}
      end

      test "advances by what the server returned when it applies a smaller limit" do
        test = self()
        items = for n <- 1..5, do: %{"id" => n}

        stub(fn conn ->
          query = URI.decode_query(conn.query_string)
          offset = String.to_integer(query["offset"])
          send(test, {:offset, offset})

          Req.Test.json(conn, %{
            "items" => items |> Enum.drop(offset) |> Enum.take(2),
            "total" => 5,
            "limit" => 2,
            "offset" => offset
          })
        end)

        assert {:ok, ^items} = apply(Rest, unquote(fun), [])
        assert [0, 2, 4] = collect_offsets()
      end

      test "stops on an empty page even if the total says there is more" do
        # Something was deleted while we were paging.
        paged_stub_with_total(first_page: [%{"id" => 1}], total: 3)

        assert {:ok, [%{"id" => 1}]} = apply(Rest, unquote(fun), [[page_size: 1]])
      end

      test "a failure on a later page is an error, never a partial list" do
        stub(fn conn ->
          case URI.decode_query(conn.query_string) do
            %{"offset" => "0"} ->
              Req.Test.json(conn, %{"items" => [%{"id" => 1}], "total" => 2})

            _ ->
              conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
          end
        end)

        capture_log(fn ->
          assert {:error, unquote(error)} = apply(Rest, unquote(fun), [[page_size: 1]])
        end)
      end

      test "maps 401 to :unauthorized" do
        json_stub(401, %{"error" => "Unauthorized"})

        log =
          capture_log(fn -> assert {:error, :unauthorized} = apply(Rest, unquote(fun), []) end)

        assert log =~ "Unauthorized listing #{unquote(resource)}"
      end

      test "maps 403 to :forbidden and says the key needs the #{scope} scope" do
        json_stub(403, %{"error" => "Forbidden"})

        log = capture_log(fn -> assert {:error, :forbidden} = apply(Rest, unquote(fun), []) end)
        assert log =~ "needs the #{unquote(scope)} scope"
      end

      test "maps 400 to :bad_request and logs Gedes's reason" do
        json_stub(400, %{"error" => "Invalid parameter(s): period_id"})

        log = capture_log(fn -> assert {:error, :bad_request} = apply(Rest, unquote(fun), []) end)
        assert log =~ "period_id"
      end

      test "maps other statuses and unexpected bodies to :#{error}" do
        json_stub(500, %{"error" => "boom"})
        capture_log(fn -> assert {:error, unquote(error)} = apply(Rest, unquote(fun), []) end)

        json_stub(200, %{"unexpected" => true})
        capture_log(fn -> assert {:error, unquote(error)} = apply(Rest, unquote(fun), []) end)
      end

      test "maps transport errors to :#{error}" do
        stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

        capture_log(fn -> assert {:error, unquote(error)} = apply(Rest, unquote(fun), []) end)
      end

      test "does not log the API key or any response body" do
        for {status, body} <- [
              {403, %{"error" => "Forbidden"}},
              {500, %{"error" => "boom", "detail" => "SECRET-EVALUATION-TEXT"}},
              {200, %{"rationale" => "SECRET-EVALUATION-TEXT"}}
            ] do
          json_stub(status, body)
          log = capture_log(fn -> apply(Rest, unquote(fun), []) end)

          refute log =~ @api_key
          refute log =~ "SECRET-EVALUATION-TEXT"
        end
      end
    end
  end

  describe "catalog lists" do
    test "list_careers/1 takes no filters, so a person filter raises" do
      test = self()

      stub(fn conn ->
        send(test, :requested)
        Req.Test.json(conn, page([]))
      end)

      assert_raise ArgumentError, ~r/user_id/, fn ->
        Rest.list_careers(user_id: "11111111-1111-1111-1111-111111111111")
      end

      assert_raise ArgumentError, ~r/career_id/, fn -> Rest.list_careers(career_id: 1) end
      refute_received :requested
    end

    test "list_categories/1 takes career_id only, so a person filter raises" do
      test = self()

      stub(fn conn ->
        send(test, :requested)
        Req.Test.json(conn, page([]))
      end)

      for opts <- [[user_id: "x"], [period_id: 1], [status: "published"]] do
        assert_raise ArgumentError, fn -> Rest.list_categories(opts) end
      end

      refute_received :requested
    end

    test "list_categories/1 returns each category with its expected competency levels" do
      category = %{
        "id" => 4,
        "career_id" => 1,
        "name" => "Senior",
        "category_codes" => ["A1"],
        "delegatable" => true,
        "competency_levels" => [
          %{
            "id" => 31,
            "competency" => %{"id" => 7, "name" => "Communication"},
            "level" => %{"id" => 3, "name" => "Senior"}
          }
        ]
      }

      json_stub(200, page([category]))

      assert {:ok, [^category]} = Rest.list_categories(career_id: 1)
    end

    test "list_careers/1 and list_categories/1 map failures to their own error" do
      json_stub(500, %{"error" => "boom"})

      capture_log(fn ->
        assert {:error, :list_careers_error} = Rest.list_careers()
        assert {:error, :list_categories_error} = Rest.list_categories()
      end)
    end
  end

  describe "init/1" do
    test "requires base_url and api_key" do
      Process.flag(:trap_exit, true)

      assert {:error, {%KeyError{key: :api_key}, _}} =
               GenServer.start(Rest, base_url: "https://gedes.test")

      assert {:error, {%KeyError{key: :base_url}, _}} = GenServer.start(Rest, api_key: "k")
    end
  end

  defp collect_offsets(acc \\ []) do
    receive do
      {:offset, offset} -> collect_offsets([offset | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # First request returns `first_page`, any later one is empty, `total` claims more.
  defp paged_stub_with_total(first_page: first_page, total: total) do
    stub(fn conn ->
      items = if conn.query_string =~ "offset=0", do: first_page, else: []
      Req.Test.json(conn, %{"items" => items, "total" => total})
    end)
  end
end
