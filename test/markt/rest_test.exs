defmodule BluetabConnect.Markt.RestTest do
  # The client is a named GenServer, so these tests cannot run concurrently.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BluetabConnect.Markt.Rest

  @api_key "markt_test_key"

  @queued [
    %{
      "id" => "7db83b7e-3f6a-4504-8666-a165006e837b",
      "to" => "ana@bluetab.net",
      "status" => "pending"
    }
  ]

  setup do
    start_supervised!({Rest,
     [
       base_url: "https://markt.test",
       api_key: @api_key,
       # Req retries 5xx and transport errors with back-off; the error tests would crawl
       req_options: [plug: {Req.Test, __MODULE__}, retry: false]
     ]})

    :ok
  end

  defp stub(fun), do: Req.Test.stub(__MODULE__, fun)

  defp json_stub(status, body) do
    stub(fn conn -> Req.Test.json(Plug.Conn.put_status(conn, status), body) end)
  end

  # Answers 202 and tells the test process what Markt would have received.
  defp request_stub(status \\ 202, body \\ %{"data" => @queued}) do
    test = self()

    stub(fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:request, conn.method, conn.request_path, conn.query_string, auth_header(conn),
         Plug.Conn.get_req_header(conn, "content-type"), Jason.decode!(raw)}
      )

      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  # A stub that tells the test if Markt was asked at all
  defp asked_stub do
    test = self()

    stub(fn conn ->
      send(test, :asked)
      Req.Test.json(Plug.Conn.put_status(conn, 202), %{"data" => []})
    end)
  end

  defp sent_body do
    assert_received {:request, _method, _path, _query, _auth, _type, body}
    body
  end

  @variables %{title: "Labor claim approved", message: "Your claim was approved."}

  describe "send_email/1" do
    test "POSTs /api/v1/emails as JSON with the API key as a bearer token" do
      request_stub()

      assert {:ok, _} = Rest.send_email(to: "ana@bluetab.net", variables: @variables)

      assert_received {:request, "POST", "/api/v1/emails", "", "Bearer " <> @api_key,
                       ["application/json"], %{"to" => "ana@bluetab.net"}}
    end

    test "returns the queued emails as sent by Markt" do
      json_stub(202, %{"data" => @queued})

      assert {:ok, @queued} = Rest.send_email(to: "ana@bluetab.net", variables: @variables)
    end

    test "sends the variables with string keys" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(
                 to: "ana@bluetab.net",
                 variables: %{title: "T", message: "M", app_name: "Tempo"}
               )

      assert %{"variables" => %{"title" => "T", "message" => "M", "app_name" => "Tempo"}} =
               sent_body()
    end

    test "takes the variables as a keyword list too" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(to: "ana@bluetab.net", variables: [title: "T", message: "M"])

      assert %{"variables" => %{"title" => "T", "message" => "M"}} = sent_body()
    end

    test "leaves out the variables that are nil, so an optional one can be passed along" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(
                 to: "ana@bluetab.net",
                 variables: %{title: "T", message: "M", action_url: nil, action_label: nil}
               )

      assert %{"variables" => variables} = sent_body()
      assert variables == %{"title" => "T", "message" => "M"}
    end

    test "keeps the variables' values as they are, so Markt can tell numbers from text" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(
                 to: "ana@bluetab.net",
                 variables: %{title: "T", message: "M", count: 3}
               )

      assert %{"variables" => %{"count" => 3}} = sent_body()
    end

    test "sends the template and the subject when given" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(
                 to: "ana@bluetab.net",
                 template: "welcome",
                 subject: "Welcome, {{name}}",
                 variables: %{}
               )

      assert %{"template" => "welcome", "subject" => "Welcome, {{name}}"} = sent_body()
    end

    test "leaves out everything that is not given" do
      request_stub()

      assert {:ok, _} = Rest.send_email(to: "ana@bluetab.net")

      assert sent_body() == %{"to" => "ana@bluetab.net"}
    end

    test "does not ask Markt about a nil template or subject" do
      request_stub()

      assert {:ok, _} = Rest.send_email(to: "ana@bluetab.net", template: nil, subject: nil)

      assert sent_body() == %{"to" => "ana@bluetab.net"}
    end
  end

  describe "send_email/1 recipients" do
    test "a single address is sent as a single address, a list as a list" do
      request_stub()
      assert {:ok, _} = Rest.send_email(to: "ana@bluetab.net")
      assert %{"to" => "ana@bluetab.net"} = sent_body()

      request_stub()
      assert {:ok, _} = Rest.send_email(to: ["ana@bluetab.net", "bob@bluetab.net"])
      assert %{"to" => ["ana@bluetab.net", "bob@bluetab.net"]} = sent_body()
    end

    test "sends \"Name <address>\" as it is, for Markt to read" do
      request_stub()

      assert {:ok, _} = Rest.send_email(to: ["Ana García <ana@bluetab.net>"])

      assert %{"to" => ["Ana García <ana@bluetab.net>"]} = sent_body()
    end

    test "takes maps with atom or string keys, and tuples, as address with name" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(
                 to: [
                   %{email: "ana@bluetab.net", name: "Ana García"},
                   %{"email" => "bob@bluetab.net", "name" => "Bob Ruiz"},
                   {"Carla Nieto", "carla@bluetab.net"}
                 ]
               )

      assert %{
               "to" => [
                 %{"email" => "ana@bluetab.net", "name" => "Ana García"},
                 %{"email" => "bob@bluetab.net", "name" => "Bob Ruiz"},
                 %{"email" => "carla@bluetab.net", "name" => "Carla Nieto"}
               ]
             } = sent_body()
    end

    test "a single map or tuple is a single recipient" do
      request_stub()
      assert {:ok, _} = Rest.send_email(to: %{email: "ana@bluetab.net", name: "Ana"})
      assert %{"to" => %{"email" => "ana@bluetab.net", "name" => "Ana"}} = sent_body()

      request_stub()
      assert {:ok, _} = Rest.send_email(to: {"Bob", "bob@bluetab.net"})
      assert %{"to" => %{"email" => "bob@bluetab.net", "name" => "Bob"}} = sent_body()
    end

    test "a map without a name is just the address" do
      request_stub()

      assert {:ok, _} = Rest.send_email(to: [%{email: "ana@bluetab.net", name: nil}])

      assert %{"to" => [%{"email" => "ana@bluetab.net"} = recipient]} = sent_body()
      refute Map.has_key?(recipient, "name")
    end

    test "raises on a recipient that is none of those, without asking Markt" do
      asked_stub()

      for bad <- [42, %{name: "No address"}, %{email: 42}, {"Ana", nil}, [:ana]] do
        assert_raise ArgumentError, ~r/:to takes addresses/, fn -> Rest.send_email(to: bad) end
      end

      refute_received :asked
    end

    test "when :to is missing Markt is asked and answers it" do
      request_stub(422, %{
        "error" => "invalid_request",
        "errors" => [%{"field" => "to", "message" => "is required"}]
      })

      capture_log(fn ->
        assert {:error, {:invalid_request, [%{"field" => "to", "message" => "is required"}]}} =
                 Rest.send_email(variables: @variables)
      end)

      refute Map.has_key?(sent_body(), "to")
    end
  end

  describe "send_email/1 options" do
    test "raises on an unknown option rather than ignoring it, without asking Markt" do
      asked_stub()

      assert_raise ArgumentError, ~r/unknown keys \[:varibles\]/, fn ->
        Rest.send_email(to: "ana@bluetab.net", varibles: @variables)
      end

      assert_raise ArgumentError, fn -> Rest.send_email(tos: "ana@bluetab.net") end

      refute_received :asked
    end
  end

  describe "send_email/1 errors" do
    test "maps 422 to {:invalid_request, errors} with every problem Markt named" do
      errors = [
        %{"field" => "to[0]", "message" => "is not a valid email address"},
        %{"field" => "variables.message", "message" => "is required by the template"}
      ]

      json_stub(422, %{"error" => "invalid_request", "errors" => errors})

      log =
        capture_log(fn ->
          assert {:error, {:invalid_request, ^errors}} =
                   Rest.send_email(to: ["nope"], variables: %{title: "T"})
        end)

      assert log =~ "to[0] is not a valid email address"
      assert log =~ "variables.message is required by the template"
    end

    test "maps 404 template_not_found to :template_not_found" do
      json_stub(404, %{
        "error" => "template_not_found",
        "message" => "There is no template with that slug"
      })

      capture_log(fn ->
        assert {:error, :template_not_found} =
                 Rest.send_email(to: "ana@bluetab.net", template: "nope")
      end)
    end

    test "a 404 that is not template_not_found (a wrong base URL) is a plain error" do
      json_stub(404, %{"errors" => %{"detail" => "Not Found"}})

      capture_log(fn ->
        assert {:error, :send_email_error} = Rest.send_email(to: "ana@bluetab.net")
      end)
    end

    test "maps 401 to :unauthorized" do
      json_stub(401, %{"error" => "Unauthorized"})

      log =
        capture_log(fn ->
          assert {:error, :unauthorized} = Rest.send_email(to: "ana@bluetab.net")
        end)

      assert log =~ "Unauthorized sending an email"
    end

    test "maps 403 to :forbidden and says the key needs the send_email scope" do
      json_stub(403, %{"error" => "Forbidden"})

      log =
        capture_log(fn ->
          assert {:error, :forbidden} = Rest.send_email(to: "ana@bluetab.net")
        end)

      assert log =~ "send_email scope"
    end

    test "maps other statuses and unexpected bodies to :send_email_error" do
      json_stub(500, %{"error" => "internal_error"})

      capture_log(fn ->
        assert {:error, :send_email_error} = Rest.send_email(to: "ana@bluetab.net")
      end)

      json_stub(202, %{"unexpected" => true})

      capture_log(fn ->
        assert {:error, :send_email_error} = Rest.send_email(to: "ana@bluetab.net")
      end)

      json_stub(422, %{"unexpected" => true})

      capture_log(fn ->
        assert {:error, :send_email_error} = Rest.send_email(to: "ana@bluetab.net")
      end)
    end

    test "maps transport errors to :send_email_error" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      capture_log(fn ->
        assert {:error, :send_email_error} = Rest.send_email(to: "ana@bluetab.net")
      end)
    end

    test "logs neither the API key, the recipients nor the variables" do
      for {status, body} <- [
            {401, %{"error" => "Unauthorized"}},
            {403, %{"error" => "Forbidden"}},
            {500, %{"error" => "internal_error"}},
            {422,
             %{
               "error" => "invalid_request",
               "errors" => [%{"field" => "to[0]", "message" => "is not a valid email address"}]
             }}
          ] do
        json_stub(status, body)

        log =
          capture_log(fn ->
            Rest.send_email(
              to: "secret.person@bluetab.net",
              variables: %{title: "T", message: "confidential message text"}
            )
          end)

        refute log =~ @api_key
        refute log =~ "secret.person"
        refute log =~ "confidential"
      end
    end
  end

  describe "send_email/1 retries" do
    test "never retries a failed send, even if the client was built to retry everything" do
      # An email retried after a lost answer would arrive twice.
      stop_supervised!(Rest)
      test = self()

      start_supervised!(
        {Rest,
         [
           base_url: "https://markt.test",
           api_key: @api_key,
           req_options: [
             plug: {Req.Test, __MODULE__},
             retry: :transient,
             retry_delay: 1,
             max_retries: 3
           ]
         ]}
      )

      stub(fn conn ->
        send(test, :attempt)
        Req.Test.json(Plug.Conn.put_status(conn, 503), %{"error" => "unavailable"})
      end)

      capture_log(fn ->
        assert {:error, :send_email_error} = Rest.send_email(to: "ana@bluetab.net")
      end)

      assert_received :attempt
      refute_received :attempt
    end
  end

  defp auth_header(conn), do: conn |> Plug.Conn.get_req_header("authorization") |> List.first()
end
