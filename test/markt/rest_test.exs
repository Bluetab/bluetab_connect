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
         Plug.Conn.get_req_header(conn, "content-type"), decode(raw)}
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
                 variables: %{
                   title: "T",
                   message: "M",
                   subtitle: nil,
                   action_url: nil,
                   action_label: nil
                 }
               )

      assert %{"variables" => variables} = sent_body()
      assert variables == %{"title" => "T", "message" => "M"}
    end

    test "sends the message as Markdown text, line breaks included, and the subtitle" do
      request_stub()
      message = "Your claim **#4521** was approved.\nThe payment is on Friday.\n\n- one\n- two"

      assert {:ok, _} =
               Rest.send_email(
                 to: "ana@bluetab.net",
                 variables: %{title: "T", message: message, subtitle: "Labor claims"}
               )

      assert %{"variables" => %{"message" => ^message, "subtitle" => "Labor claims"}} =
               sent_body()
    end

    test "sends rich content as the objects Markt expects, in whichever form it is given" do
      for {given, expected} <- [
            {%{markdown: "Hi **team**"}, %{"markdown" => "Hi **team**"}},
            {%{html: "<p>Hi</p>"}, %{"html" => "<p>Hi</p>"}},
            {%{"html" => "<p>Hi</p>"}, %{"html" => "<p>Hi</p>"}}
          ] do
        request_stub()

        assert {:ok, _} =
                 Rest.send_email(
                   to: "ana@bluetab.net",
                   variables: %{title: "T", message: given}
                 )

        assert %{"variables" => %{"message" => ^expected}} = sent_body()
      end
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

    test "reports a message Markt refuses like any other field, without logging the message" do
      errors = [%{"field" => "variables.message", "message" => "has no content"}]
      json_stub(422, %{"error" => "invalid_request", "errors" => errors})

      log =
        capture_log(fn ->
          assert {:error, {:invalid_request, ^errors}} =
                   Rest.send_email(
                     to: "ana@bluetab.net",
                     variables: %{title: "T", message: "<script>alert(1)</script>"}
                   )
        end)

      assert log =~ "variables.message has no content"
      refute log =~ "alert(1)"
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

  describe "send_email/1 to a group" do
    test "sends the slug of the group instead of recipients" do
      request_stub()

      assert {:ok, _} =
               Rest.send_email(group: "tempo-business-operators", variables: @variables)

      assert %{"group" => "tempo-business-operators", "variables" => %{"title" => _}} =
               body = sent_body()

      refute Map.has_key?(body, "to")
    end

    test "raises when it is given both recipients and a group, without asking Markt" do
      asked_stub()

      assert_raise ArgumentError, ~r/not both/, fn ->
        Rest.send_email(to: "ana@bluetab.net", group: "tempo-business-operators")
      end

      refute_received :asked
    end

    test "raises on a group that is not a slug, without asking Markt" do
      asked_stub()

      for group <- ["", :tempo, ["tempo-business-operators"], 4] do
        assert_raise ArgumentError, ~r/slug/, fn -> Rest.send_email(group: group) end
      end

      refute_received :asked
    end

    test "returns what Markt answers: an item for each email, and the addresses it left out" do
      queued = [
        %{
          "id" => "7db83b7e-3f6a-4504-8666-a165006e837b",
          "to" => "ana@bluetab.net",
          "status" => "pending"
        },
        %{
          "id" => nil,
          "to" => "outsider@gmail.com",
          "status" => "rejected",
          "reason" => "unknown_recipient"
        }
      ]

      json_stub(202, %{"data" => queued})

      assert {:ok, ^queued} =
               Rest.send_email(
                 to: ["ana@bluetab.net", "outsider@gmail.com"],
                 variables: @variables
               )
    end

    test "returns the one email to everyone of a public group, with who it went to" do
      queued = [
        %{
          "id" => "7db83b7e-3f6a-4504-8666-a165006e837b",
          "to" => "ana@bluetab.net",
          "status" => "pending",
          "recipients" => ["ana@bluetab.net", "bob@bluetab.net"]
        }
      ]

      json_stub(202, %{"data" => queued})

      assert {:ok, ^queued} = Rest.send_email(group: "tempo-business-operators")
    end

    test "maps 404 group_not_found to :group_not_found" do
      json_stub(404, %{
        "error" => "group_not_found",
        "message" => "There is no group with that slug that an app owns"
      })

      log =
        capture_log(fn ->
          assert {:error, :group_not_found} = Rest.send_email(group: "nope-nope")
        end)

      assert log =~ "no group"
    end

    test "maps 422 to {:invalid_request, errors}, as for recipients" do
      errors = [%{"field" => "group", "message" => "has no people who can receive email"}]
      json_stub(422, %{"error" => "invalid_request", "errors" => errors})

      capture_log(fn ->
        assert {:error, {:invalid_request, ^errors}} =
                 Rest.send_email(group: "tempo-business-operators")
      end)
    end
  end

  @slug "tempo-business-operators"

  @group %{
    "slug" => @slug,
    "name" => "Tempo business operators",
    "description" => nil,
    "visibility" => "bcc",
    "managed_by" => "Tempo production",
    "member_count" => 1,
    "members" => [%{"email" => "ana@bluetab.net", "name" => "Ana García"}]
  }

  @summary %{"data" => @group, "added" => 1, "removed" => 0, "skipped" => 0, "rejected" => []}

  describe "sync_group/2" do
    test "PUTs /api/v1/groups/:slug as JSON with the API key as a bearer token" do
      request_stub(200, @summary)

      assert {:ok, _} = Rest.sync_group(@slug, name: "Tempo business operators")

      assert_received {:request, "PUT", "/api/v1/groups/tempo-business-operators", "",
                       "Bearer " <> @api_key, ["application/json"],
                       %{"name" => "Tempo business operators"}}
    end

    test "returns what Markt answers, whether it made the group (201) or changed it (200)" do
      for status <- [200, 201] do
        json_stub(status, @summary)
        assert {:ok, @summary} = Rest.sync_group(@slug, members: ["ana@bluetab.net"])
      end
    end

    test "sends the name, the description, the visibility and the members" do
      request_stub(200, @summary)

      assert {:ok, _} =
               Rest.sync_group(@slug,
                 name: "Tempo business operators",
                 description: "People with the Business Operators role in Tempo",
                 visibility: :public,
                 members: ["ana@bluetab.net", "bob@bluetab.net"]
               )

      assert sent_body() == %{
               "name" => "Tempo business operators",
               "description" => "People with the Business Operators role in Tempo",
               "visibility" => "public",
               "members" => ["ana@bluetab.net", "bob@bluetab.net"]
             }
    end

    test "takes the visibility as an atom or as a string" do
      request_stub(200, @summary)

      assert {:ok, _} = Rest.sync_group(@slug, visibility: :bcc)
      assert %{"visibility" => "bcc"} = sent_body()

      assert {:ok, _} = Rest.sync_group(@slug, visibility: "public")
      assert %{"visibility" => "public"} = sent_body()
    end

    test "leaves out what is not given, so Markt keeps it as it is" do
      request_stub(200, @summary)

      assert {:ok, _} = Rest.sync_group(@slug)
      assert sent_body() == %{}

      assert {:ok, _} = Rest.sync_group(@slug, name: "N", visibility: nil, members: nil)
      assert sent_body() == %{"name" => "N"}
    end

    test "sends an empty list of members, which empties the group" do
      request_stub(200, @summary)

      assert {:ok, _} = Rest.sync_group(@slug, members: [])
      assert sent_body() == %{"members" => []}
    end

    test "takes the members as addresses or as anything with an email, and sends addresses" do
      request_stub(200, @summary)

      assert {:ok, _} =
               Rest.sync_group(@slug,
                 members: [
                   "ana@bluetab.net",
                   %{email: "bob@bluetab.net", name: "Bob Ruiz", role: :operator},
                   %{"email" => "eva@bluetab.net"}
                 ]
               )

      assert %{"members" => ["ana@bluetab.net", "bob@bluetab.net", "eva@bluetab.net"]} =
               sent_body()
    end

    test "writes the slug as one segment of the path" do
      request_stub(200, @summary)

      assert {:ok, _} = Rest.sync_group("a/b c")

      assert_received {:request, "PUT", "/api/v1/groups/a%2Fb%20c", _, _, _, _}
    end

    test "raises on what it cannot send, without asking Markt" do
      asked_stub()

      assert_raise ArgumentError, ~r/slug/, fn -> Rest.sync_group("") end
      assert_raise ArgumentError, ~r/slug/, fn -> Rest.sync_group(:tempo) end
      assert_raise ArgumentError, ~r/unknown keys/, fn -> Rest.sync_group(@slug, mebers: []) end

      assert_raise ArgumentError, ~r/list of addresses/, fn ->
        Rest.sync_group(@slug, members: "ana@bluetab.net")
      end

      assert_raise ArgumentError, ~r/with an :email/, fn ->
        Rest.sync_group(@slug, members: [%{name: "Ana"}])
      end

      assert_raise ArgumentError, ~r/with an :email/, fn ->
        Rest.sync_group(@slug, members: [42])
      end

      refute_received :asked
    end

    test "maps 422 to {:invalid_request, errors} with every problem Markt named" do
      errors = [
        %{"field" => "members[0]", "message" => "is not a valid email address"},
        %{"field" => "visibility", "message" => "must be bcc or public"}
      ]

      json_stub(422, %{"error" => "invalid_request", "errors" => errors})

      log =
        capture_log(fn ->
          assert {:error, {:invalid_request, ^errors}} = Rest.sync_group(@slug, members: ["x"])
        end)

      assert log =~ "members[0] is not a valid email address"
      assert log =~ "visibility must be bcc or public"
    end

    test "can be repeated: the client does not force a call not to be retried" do
      # Unlike a send, this one is the same however many times it is made, so what the client was
      # built with (Req retries a PUT only if it was told to) applies
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
             max_retries: 2
           ]
         ]}
      )

      stub(fn conn ->
        send(test, :attempt)
        Req.Test.json(Plug.Conn.put_status(conn, 503), %{"error" => "unavailable"})
      end)

      capture_log(fn -> assert {:error, :sync_group_error} = Rest.sync_group(@slug) end)

      assert_received :attempt
      assert_received :attempt
      assert_received :attempt
    end
  end

  describe "get_group/1" do
    test "GETs /api/v1/groups/:slug and returns the group" do
      request_stub(200, %{"data" => @group})

      assert {:ok, @group} = Rest.get_group(@slug)

      assert_received {:request, "GET", "/api/v1/groups/tempo-business-operators", "",
                       "Bearer " <> @api_key, [], nil}
    end

    test "raises on a slug that is not one, without asking Markt" do
      asked_stub()

      assert_raise ArgumentError, ~r/slug/, fn -> Rest.get_group("") end
      assert_raise ArgumentError, ~r/slug/, fn -> Rest.get_group(nil) end

      refute_received :asked
    end
  end

  describe "add_group_member/2" do
    test "PUTs /api/v1/groups/:slug/members/:email with the @ written as %40" do
      request_stub(200, @summary)

      assert {:ok, @summary} = Rest.add_group_member(@slug, "ana@bluetab.net")

      assert_received {:request, "PUT",
                       "/api/v1/groups/tempo-business-operators/members/ana%40bluetab.net", "",
                       "Bearer " <> @api_key, [], nil}
    end

    test "takes a map with an email too, such as a user" do
      request_stub(200, @summary)

      assert {:ok, _} =
               Rest.add_group_member(@slug, %{email: "ana@bluetab.net", name: "Ana García"})

      assert_received {:request, "PUT",
                       "/api/v1/groups/tempo-business-operators/members/ana%40bluetab.net", _, _,
                       _, _}
    end

    test "tells that the address is not a person of the organization" do
      errors = [%{"field" => "email", "message" => "is not a person in Markt"}]
      json_stub(422, %{"error" => "invalid_request", "errors" => errors})

      capture_log(fn ->
        assert {:error, {:invalid_request, ^errors}} =
                 Rest.add_group_member(@slug, "outsider@gmail.com")
      end)
    end

    test "raises on a member that is not an address, without asking Markt" do
      asked_stub()

      for member <- ["", nil, %{}, %{name: "Ana"}, 42] do
        assert_raise ArgumentError, ~r/with an :email/, fn ->
          Rest.add_group_member(@slug, member)
        end
      end

      assert_raise ArgumentError, ~r/slug/, fn -> Rest.add_group_member("", "ana@bluetab.net") end

      refute_received :asked
    end
  end

  describe "remove_group_member/2" do
    test "DELETEs /api/v1/groups/:slug/members/:email and returns what Markt answers" do
      answer = %{"data" => @group, "removed" => 1}
      request_stub(200, answer)

      assert {:ok, ^answer} = Rest.remove_group_member(@slug, "ana@bluetab.net")

      assert_received {:request, "DELETE",
                       "/api/v1/groups/tempo-business-operators/members/ana%40bluetab.net", "",
                       "Bearer " <> @api_key, _, nil}
    end

    test "raises on a member that is not an address, without asking Markt" do
      asked_stub()

      assert_raise ArgumentError, ~r/with an :email/, fn ->
        Rest.remove_group_member(@slug, "")
      end

      refute_received :asked
    end
  end

  # What every call about groups says when it goes wrong
  defp call_group(:get_group), do: Rest.get_group(@slug)
  defp call_group(:sync_group), do: Rest.sync_group(@slug, members: ["ana@bluetab.net"])
  defp call_group(:add_group_member), do: Rest.add_group_member(@slug, "ana@bluetab.net")
  defp call_group(:remove_group_member), do: Rest.remove_group_member(@slug, "ana@bluetab.net")

  for call <- ~w(get_group sync_group add_group_member remove_group_member)a do
    describe "#{call} errors" do
      test "maps 404 group_not_found to :group_not_found" do
        json_stub(404, %{"error" => "group_not_found", "message" => "There is no group"})

        capture_log(fn ->
          assert {:error, :group_not_found} = call_group(unquote(call))
        end)
      end

      test "maps 403 group_not_managed to :group_not_managed: people made that group in Markt" do
        json_stub(403, %{"error" => "group_not_managed", "message" => "Not managed"})

        capture_log(fn ->
          assert {:error, :group_not_managed} = call_group(unquote(call))
        end)
      end

      test "maps any other 403 to :forbidden and says the key needs the manage_groups scope" do
        json_stub(403, %{"error" => "Forbidden"})

        log =
          capture_log(fn ->
            assert {:error, :forbidden} = call_group(unquote(call))
          end)

        assert log =~ "manage_groups scope"
      end

      test "maps 401 to :unauthorized" do
        json_stub(401, %{"error" => "Unauthorized"})

        capture_log(fn ->
          assert {:error, :unauthorized} = call_group(unquote(call))
        end)
      end

      test "maps 422 to {:invalid_request, errors}" do
        errors = [%{"field" => "members[0]", "message" => "is not a valid email address"}]
        json_stub(422, %{"error" => "invalid_request", "errors" => errors})

        capture_log(fn ->
          assert {:error, {:invalid_request, ^errors}} = call_group(unquote(call))
        end)
      end

      test "maps other statuses, unexpected bodies and transport errors to its own error" do
        error = unquote(:"#{call}_error")

        for {status, body} <- [
              {500, %{"error" => "internal_error"}},
              {404, %{"errors" => %{"detail" => "Not Found"}}},
              {200, %{"unexpected" => true}},
              {422, %{"unexpected" => true}}
            ] do
          json_stub(status, body)
          capture_log(fn -> assert {:error, ^error} = call_group(unquote(call)) end)
        end

        stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
        capture_log(fn -> assert {:error, ^error} = call_group(unquote(call)) end)
      end

      test "logs neither the API key nor the addresses" do
        for {status, body} <- [
              {401, %{"error" => "Unauthorized"}},
              {403, %{"error" => "Forbidden"}},
              {403, %{"error" => "group_not_managed"}},
              {404, %{"error" => "group_not_found"}},
              {500, %{"error" => "internal_error"}},
              {422,
               %{
                 "error" => "invalid_request",
                 "errors" => [%{"field" => "email", "message" => "is not a person in Markt"}]
               }}
            ] do
          json_stub(status, body)

          log = capture_log(fn -> call_group(unquote(call)) end)

          refute log =~ @api_key
          refute log =~ "ana@bluetab.net"
        end
      end
    end
  end

  defp auth_header(conn), do: conn |> Plug.Conn.get_req_header("authorization") |> List.first()

  # A GET or a DELETE has no body
  defp decode(""), do: nil
  defp decode(raw), do: Jason.decode!(raw)
end
