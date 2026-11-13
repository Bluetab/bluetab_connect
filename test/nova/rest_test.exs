defmodule BluetabConnect.Nova.RestTest do
  # The client is a named GenServer, so these tests cannot run concurrently.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BluetabConnect.Nova.Rest

  # Something of the app that has the keys of a requirement and of a person, and is not a map
  defmodule Entry do
    defstruct [:technology, :sap_id, :email]
  end

  @api_key "nova_test_key"

  # What no log may ever show: the position, the people, what Nova answered, the key.
  @description "SECRET-POSITION: a senior engineer for the Santander account"
  @reference "SECRET-REFERENCE-4711"
  @sap_id 9_876_543
  @email "secret.person@bluetab.net"
  @answer_text "SECRET-ANSWER-TEXT"

  @answer %{
    "match_id" => "0b5d6c1e-3f6a-4504-8666-a165006e837b",
    "ranking_version" => 2,
    "weights_version" => 2,
    "reference" => "REQ-1042",
    "requirements" => [
      %{
        "technology" => %{"id" => "t1", "name" => "Elixir"},
        "importance" => "must",
        "min_level" => 3,
        "years" => 2.0,
        "mention" => "Elixir",
        "source" => "given"
      }
    ],
    "unmatched" => ["Cobol"],
    "unknown_people" => [%{"sap_id" => 4242}],
    "candidates" => [
      %{
        "score" => 0.82,
        "person" => %{
          "id" => "u1",
          "sap_id" => 1234,
          "name" => "Ana García",
          "email" => "ana@bluetab.net",
          "profile" => "/users/u1"
        },
        "matched" => 1,
        "missing" => [],
        "coverage" => "stated",
        "technologies_known" => 14,
        "breakdown" => [
          %{
            "technology" => "Elixir",
            "importance" => "must",
            "satisfaction" => 0.82,
            "weight" => 0.9,
            "proficiency" => 4,
            "confidence" => 0.8,
            "years" => 3.0,
            "recency" => 1.0,
            "sources" => ["self", "course"],
            "via" => nil
          }
        ]
      }
    ]
  }

  @technologies [
    %{
      "id" => "t1",
      "name" => "Event Hubs",
      "aliases" => ["Azure Event Hubs"],
      "category" => "cloud",
      "parents" => [%{"id" => "t2", "name" => "Azure"}],
      "people" => 7
    },
    %{
      "id" => "t3",
      "name" => "Elixir",
      "aliases" => [],
      "category" => nil,
      "parents" => [],
      "people" => 12
    }
  ]

  @course %{
    "id" => "6f1c0a52-7f0e-4d57-8f7b-5d1a3c0a9e11",
    "type" => "mooc",
    "name" => "Elixir for the impatient",
    "description" => "A fast tour of the language",
    "image" => nil,
    "language" => "en",
    "external_url" => "https://example.com/elixir",
    "publish_date" => "2026-03-01",
    "subject" => "Programming",
    "tags" => ["elixir"],
    "code" => 17,
    "duration" => 12.0,
    "real_cost" => 0.0,
    "reason" => "It is how we start every Elixir project.",
    "certification" => false,
    "title" => nil,
    "video" => nil,
    "creator_id" => "c0ffee00-0000-4000-8000-000000000001",
    "published" => true,
    "inserted_at" => "2026-03-01T09:30:00Z",
    "updated_at" => "2026-03-01T09:30:00Z"
  }

  @learning_object Map.merge(@course, %{"code" => nil, "published" => false})

  setup do
    start_supervised!({Rest,
     [
       base_url: "https://nova.test",
       api_key: @api_key,
       # Req retries the 5xx and the transport errors of a GET with back-off; the error tests
       # would crawl
       req_options: [plug: {Req.Test, __MODULE__}, retry: false]
     ]})

    :ok
  end

  defp stub(fun), do: Req.Test.stub(__MODULE__, fun)

  defp json_stub(status, body) do
    stub(fn conn -> Req.Test.json(Plug.Conn.put_status(conn, status), body) end)
  end

  # Answers `status` with `body` and tells the test process what Nova would have received.
  defp request_stub(status, body) do
    test = self()

    stub(fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:request,
         %{
           method: conn.method,
           path: conn.request_path,
           query: URI.decode_query(conn.query_string),
           auth: conn |> Plug.Conn.get_req_header("authorization") |> List.first(),
           accept: Plug.Conn.get_req_header(conn, "accept"),
           content_type: Plug.Conn.get_req_header(conn, "content-type"),
           body: decode(raw)
         }}
      )

      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  # A stub that tells the test if Nova was asked at all
  defp asked_stub do
    test = self()

    stub(fn conn ->
      send(test, :asked)
      Req.Test.json(conn, %{"items" => [], "total" => 0})
    end)
  end

  defp received do
    assert_received {:request, request}
    request
  end

  # A GET has no body
  defp decode(""), do: nil
  defp decode(raw), do: Jason.decode!(raw)

  # {the call, HTTP method, path, status of success, body of success, what to look for in the log
  # of a 403}: the four calls and what each answers, so that what they share is tested for each.
  @functions ~w(match_people list_technologies search_courses create_learning_object)a

  @endpoints %{
    match_people: {"POST", "/api/matches"},
    list_technologies: {"GET", "/api/technologies"},
    search_courses: {"GET", "/api/learning_objects/moocs/search"},
    create_learning_object: {"POST", "/api/learning_objects"}
  }

  @forbidden_in_the_log %{
    match_people: ["matching scope", "match_people permission"],
    list_technologies: ["matching scope", "match_people permission"],
    search_courses: ["learning_objects scope"],
    create_learning_object: ["learning_objects scope", "manage_learning_objects"]
  }

  defp ok_status(:create_learning_object), do: 201
  defp ok_status(_function), do: 200

  defp ok_body(:match_people), do: @answer
  defp ok_body(:list_technologies), do: %{"items" => @technologies, "total" => 2}
  defp ok_body(:search_courses), do: %{"items" => [@course], "total" => 1}
  defp ok_body(:create_learning_object), do: @learning_object

  defp call(:match_people), do: Rest.match_people(description: "Elixir developer")
  defp call(:list_technologies), do: Rest.list_technologies()
  defp call(:search_courses), do: Rest.search_courses(q: "elixir")

  defp call(:create_learning_object),
    do: Rest.create_learning_object(type: :mooc, name: "Elixir for the impatient")

  # The same call with everything that must never be logged: the position, the people, the key's
  # user is the one that asks.
  defp call_with_secrets(:match_people) do
    Rest.match_people(
      description: @description,
      requirements: [%{technology: "Elixir"}],
      people: [%{sap_id: @sap_id}, %{email: @email}],
      reference: @reference
    )
  end

  defp call_with_secrets(:list_technologies), do: Rest.list_technologies()

  defp call_with_secrets(:search_courses),
    do: Rest.search_courses(q: @description, external_url: "https://example.com/" <> @reference)

  defp call_with_secrets(:create_learning_object) do
    Rest.create_learning_object(
      type: :mooc,
      name: @reference,
      description: @description,
      external_url: "https://example.com/" <> @email,
      details: %{reason: @description}
    )
  end

  describe "match_people/1" do
    test "POSTs /api/matches as JSON with the API key as a bearer token, asking for JSON" do
      request_stub(200, @answer)

      assert {:ok, _} = Rest.match_people(description: "Elixir developer")

      assert %{
               method: "POST",
               path: "/api/matches",
               query: query,
               auth: "Bearer " <> @api_key,
               accept: ["application/json"],
               content_type: ["application/json"]
             } = received()

      assert query == %{}
    end

    test "returns the whole answer as Nova sends it, with string keys" do
      json_stub(200, @answer)

      assert {:ok, answer} = Rest.match_people(description: "Elixir developer")
      assert answer == @answer
    end

    test "sends the options as the fields Nova reads" do
      request_stub(200, @answer)

      assert {:ok, _} =
               Rest.match_people(
                 description: "A backend engineer with 3+ years of Elixir. Kafka is a plus.",
                 requirements: [%{technology: "Elixir"}],
                 people: [%{sap_id: 1234}, %{email: "ana@bluetab.net"}],
                 reference: "REQ-1042",
                 limit: 10,
                 min_score: 0.1
               )

      assert received().body == %{
               "description" => "A backend engineer with 3+ years of Elixir. Kafka is a plus.",
               "requirements" => [%{"technology" => "Elixir"}],
               "people" => [%{"sap_id" => 1234}, %{"email" => "ana@bluetab.net"}],
               "reference" => "REQ-1042",
               "limit" => 10,
               "min_score" => 0.1
             }
    end

    test "leaves out what is not given, so Nova applies its defaults" do
      request_stub(200, @answer)

      assert {:ok, _} = Rest.match_people(description: "Elixir developer")
      assert received().body == %{"description" => "Elixir developer"}

      assert {:ok, _} =
               Rest.match_people(
                 description: "Elixir developer",
                 requirements: nil,
                 people: nil,
                 reference: nil,
                 limit: nil,
                 min_score: nil
               )

      assert received().body == %{"description" => "Elixir developer"}
    end

    test "sends an empty list of people as an empty list: it ranks no one, and leaving it out ranks everyone" do
      request_stub(200, @answer)

      assert {:ok, _} = Rest.match_people(requirements: [%{technology: "Elixir"}], people: [])

      assert received().body == %{"requirements" => [%{"technology" => "Elixir"}], "people" => []}
    end

    test "takes the people with atom or string keys, and sends the number or the address only" do
      request_stub(200, @answer)

      assert {:ok, _} =
               Rest.match_people(
                 description: "Elixir developer",
                 people: [
                   %{sap_id: 1234},
                   %{"sap_id" => "5678"},
                   %{email: "ana@bluetab.net", name: "Ana García", team: "Data"},
                   %{"email" => "Bob@bluetab.net", "role" => "Engineer"}
                 ]
               )

      # exactly these, so that what else a person of the app has is not sent
      assert received().body["people"] == [
               %{"sap_id" => 1234},
               %{"sap_id" => "5678"},
               %{"email" => "ana@bluetab.net"},
               %{"email" => "Bob@bluetab.net"}
             ]
    end

    test "passes the values of the people on as they are: whether they name a person is Nova's to say" do
      request_stub(400, %{"error" => "people entry 1 must name one person, by sap_id or by email"})

      people = [
        # both of them, a number that is not one, null (Nova reads it as not given)
        %{sap_id: 1234, email: "ana@bluetab.net"},
        %{sap_id: "abc"},
        %{sap_id: nil, email: "bob@bluetab.net"}
      ]

      capture_log(fn ->
        assert {:error, :bad_request} = Rest.match_people(description: "x", people: people)
      end)

      assert received().body == %{
               "description" => "x",
               "people" => [
                 %{"sap_id" => 1234, "email" => "ana@bluetab.net"},
                 %{"sap_id" => "abc"},
                 %{"sap_id" => nil, "email" => "bob@bluetab.net"}
               ]
             }
    end

    test "takes the requirements with atom or string keys and sends each as it is" do
      request_stub(200, @answer)

      assert {:ok, _} =
               Rest.match_people(
                 requirements: [
                   %{technology: "Elixir", importance: :must, min_level: 3, years: 2.5},
                   %{"technology" => "Kafka", "importance" => "nice"},
                   # a key that Nova may learn tomorrow is not the client's to refuse
                   %{technology: "Go", something_new: true}
                 ]
               )

      assert received().body == %{
               "requirements" => [
                 %{
                   "technology" => "Elixir",
                   "importance" => "must",
                   "min_level" => 3,
                   "years" => 2.5
                 },
                 %{"technology" => "Kafka", "importance" => "nice"},
                 %{"technology" => "Go", "something_new" => true}
               ]
             }
    end

    test "does not check what Nova checks: sizes, ranges and texts are for Nova to refuse" do
      request_stub(200, @answer)

      assert {:ok, _} =
               Rest.match_people(
                 description: "",
                 reference: String.duplicate("x", 500),
                 limit: 100_000,
                 min_score: 7,
                 people: [%{sap_id: "not a number"}, %{email: "not an address"}],
                 requirements: [
                   %{technology: nil, importance: "whatever", min_level: 9, years: -3}
                 ]
               )

      assert received().body == %{
               "description" => "",
               "reference" => String.duplicate("x", 500),
               "limit" => 100_000,
               "min_score" => 7,
               "people" => [%{"sap_id" => "not a number"}, %{"email" => "not an address"}],
               "requirements" => [
                 %{
                   "technology" => nil,
                   "importance" => "whatever",
                   "min_level" => 9,
                   "years" => -3
                 }
               ]
             }
    end

    test "raises on an unknown option rather than ignoring it, without asking Nova" do
      asked_stub()

      assert_raise ArgumentError, ~r/unknown keys \[:descripton\]/, fn ->
        Rest.match_people(descripton: "Elixir developer")
      end

      assert_raise ArgumentError, ~r/unknown keys \[:query\]/, fn ->
        Rest.match_people(description: "Elixir developer", query: "x")
      end

      refute_received :asked
    end

    test "names the keys that are wrong and never shows a value: they are people" do
      asked_stub()

      error =
        assert_raise ArgumentError, ~r/unknown keys \[:varibles\]/, fn ->
          Rest.match_people(
            description: @description,
            reference: @reference,
            people: [%{sap_id: @sap_id}, %{email: @email}],
            varibles: %{}
          )
        end

      assert error.message =~ ":description"

      for secret <- [@description, @reference, @email, to_string(@sap_id)] do
        refute error.message =~ secret
      end

      refute_received :asked
    end

    test "raises on options that are not a keyword list, without asking Nova" do
      asked_stub()

      assert_raise ArgumentError, ~r/keyword list/, fn -> Rest.match_people(["Elixir"]) end

      assert_raise ArgumentError, ~r/keyword list/, fn ->
        Rest.match_people([{"description", "x"}])
      end

      refute_received :asked
    end

    test "raises on requirements that are not a list of maps with a technology, without asking Nova" do
      asked_stub()

      for bad <- ["Elixir", %{technology: "Elixir"}, 42] do
        assert_raise ArgumentError, ~r/:requirements takes a list/, fn ->
          Rest.match_people(requirements: bad)
        end
      end

      # a struct is not a map of the form: it could even have the keys, and not be encodable
      bad_entries = [
        ["Elixir"],
        [42],
        [nil],
        [%{importance: "must"}],
        [~D[2026-03-01]],
        [%Entry{technology: "Elixir"}]
      ]

      for bad <- bad_entries do
        assert_raise ArgumentError,
                     ~r/:requirements entry 1 must be a map with a :technology/,
                     fn ->
                       Rest.match_people(requirements: bad)
                     end
      end

      assert_raise ArgumentError, ~r/:requirements entry 2/, fn ->
        Rest.match_people(requirements: [%{technology: "Elixir"}, "Kafka"])
      end

      refute_received :asked
    end

    test "raises on people that are not a list of maps with a sap_id or an email, without asking Nova" do
      asked_stub()

      for bad <- [%{sap_id: 1234}, "ana@bluetab.net", 1234] do
        assert_raise ArgumentError, ~r/:people takes a list/, fn ->
          Rest.match_people(description: "x", people: bad)
        end
      end

      # a person of the app is not one of the two forms, even if it has a `sap_id` and an `email`:
      # which of them names the person is the caller's to say
      entries = [
        42,
        "ana@bluetab.net",
        %{id: 7},
        %{},
        {1234},
        nil,
        ~D[2026-03-01],
        [sap_id: 1234],
        %Entry{sap_id: 1234, email: "ana@bluetab.net"}
      ]

      for bad <- entries do
        assert_raise ArgumentError,
                     ~r/:people entry 1 must be a map with a :sap_id or an :email/,
                     fn ->
                       Rest.match_people(description: "x", people: [bad])
                     end
      end

      assert_raise ArgumentError, ~r/:people entry 3/, fn ->
        Rest.match_people(
          description: "x",
          people: [%{sap_id: 1}, %{email: "a@b.c"}, %{name: "Ana"}]
        )
      end

      refute_received :asked
    end

    test "says which entry is wrong and not what it holds" do
      asked_stub()

      error =
        assert_raise ArgumentError, ~r/:people entry 2/, fn ->
          Rest.match_people(description: "x", people: [%{sap_id: 1}, @email])
        end

      refute error.message =~ @email

      error =
        assert_raise ArgumentError, ~r/:people entry 1/, fn ->
          Rest.match_people(description: "x", people: [%{name: @email, id: @sap_id}])
        end

      refute error.message =~ @email
      refute error.message =~ to_string(@sap_id)

      refute_received :asked
    end

    test "maps 422 to {:invalid_request, errors}: the position names no technology of the map" do
      errors = %{
        "description" => [
          "does not name a technology the map has, and no requirement was given that it has"
        ]
      }

      json_stub(422, %{"errors" => errors})

      log =
        capture_log(fn ->
          assert {:error, {:invalid_request, ^errors}} =
                   Rest.match_people(description: "Someone who knows Cobol")
        end)

      assert log =~ "description does not name a technology the map has"
    end

    test "maps a 400 to :bad_request and logs Nova's reason, which says which parameter" do
      json_stub(400, %{"error" => "limit must be a number from 1 to 100"})

      log =
        capture_log(fn ->
          assert {:error, :bad_request} = Rest.match_people(description: "x", limit: 1000)
        end)

      assert log =~ "limit must be a number from 1 to 100"
    end
  end

  describe "list_technologies/1" do
    test "GETs /api/technologies with the API key as a bearer token, asking for JSON" do
      request_stub(200, %{"items" => @technologies, "total" => 2})

      assert {:ok, _} = Rest.list_technologies()

      assert %{
               method: "GET",
               path: "/api/technologies",
               query: query,
               auth: "Bearer " <> @api_key,
               accept: ["application/json"],
               content_type: [],
               body: nil
             } = received()

      assert query == %{}
    end

    test "returns the items as Nova sends them, with no paging" do
      json_stub(200, %{"items" => @technologies, "total" => 2})

      assert {:ok, technologies} = Rest.list_technologies()
      assert technologies == @technologies

      json_stub(200, %{"items" => [], "total" => 0})
      assert {:ok, []} = Rest.list_technologies([])
    end

    test "takes no options: one raises, without asking Nova" do
      asked_stub()

      assert_raise ArgumentError, ~r/unknown keys \[:limit\].*takes no options/, fn ->
        Rest.list_technologies(limit: 5)
      end

      assert_raise ArgumentError, ~r/unknown keys \[:page_size\]/, fn ->
        Rest.list_technologies(page_size: 100)
      end

      refute_received :asked
    end
  end

  describe "search_courses/1" do
    test "GETs the search with the text, the address and the limit as query params" do
      request_stub(200, %{"items" => [@course], "total" => 1})

      assert {:ok, _} =
               Rest.search_courses(
                 q: "elixir",
                 external_url: "https://example.com/elixir",
                 limit: 5
               )

      assert %{
               method: "GET",
               path: "/api/learning_objects/moocs/search",
               query: query,
               auth: "Bearer " <> @api_key,
               accept: ["application/json"],
               body: nil
             } = received()

      assert query == %{
               "q" => "elixir",
               "external_url" => "https://example.com/elixir",
               "limit" => "5"
             }
    end

    test "returns the courses as Nova sends them" do
      json_stub(200, %{"items" => [@course], "total" => 1})

      assert {:ok, courses} = Rest.search_courses(q: "elixir")
      assert courses == [@course]
    end

    test "leaves out a nil value" do
      request_stub(200, %{"items" => [], "total" => 0})

      assert {:ok, []} = Rest.search_courses(q: "elixir", external_url: nil, limit: nil)
      assert received().query == %{"q" => "elixir"}

      assert {:ok, []} = Rest.search_courses(external_url: "https://example.com/elixir", q: nil)
      assert received().query == %{"external_url" => "https://example.com/elixir"}
    end

    test "writes a text as it is, special characters included" do
      request_stub(200, %{"items" => [], "total" => 0})

      for text <- ["100%_done", "a&b=c d", "ñandú #1 + más?", "https://example.com/a?b=1&c=2"] do
        assert {:ok, []} = Rest.search_courses(q: text, external_url: text)
        assert %{query: %{"q" => ^text, "external_url" => ^text}} = received()
      end
    end

    test "does not check what Nova checks: a call with nothing to look for, a blank text, a limit" do
      request_stub(200, %{"items" => [], "total" => 0})

      assert {:ok, []} = Rest.search_courses([])
      assert received().query == %{}

      assert {:ok, []} = Rest.search_courses(q: "  ", limit: 9999)
      assert received().query == %{"q" => "  ", "limit" => "9999"}

      assert {:ok, []} = Rest.search_courses(limit: "ten")
      assert received().query == %{"limit" => "ten"}
    end

    test "raises on an unknown option, and on :query, the alias Nova takes only when q is absent" do
      asked_stub()

      assert_raise ArgumentError, ~r/unknown keys \[:query\]/, fn ->
        Rest.search_courses(query: "elixir")
      end

      assert_raise ArgumentError, ~r/unknown keys \[:externalurl\]/, fn ->
        Rest.search_courses(q: "elixir", externalurl: "https://example.com")
      end

      assert_raise ArgumentError, ~r/allowed keys are: \[:q, :external_url, :limit\]/, fn ->
        Rest.search_courses(page: 2)
      end

      refute_received :asked
    end

    test "maps Nova's 422 for a search with nothing to look for, a single text, to {:invalid_request, errors}" do
      json_stub(422, %{"error" => "provide q or external_url"})

      log =
        capture_log(fn ->
          assert {:error, {:invalid_request, %{"base" => ["provide q or external_url"]}}} =
                   Rest.search_courses(q: "")
        end)

      assert log =~ "provide q or external_url"
    end

    test "maps a 400 for a limit that is not a number to :bad_request, and logs Nova's reason" do
      json_stub(400, %{"error" => "limit must be a number"})

      log =
        capture_log(fn ->
          assert {:error, :bad_request} = Rest.search_courses(q: "elixir", limit: "ten")
        end)

      assert log =~ "limit must be a number"
    end
  end

  describe "create_learning_object/1" do
    @mooc [
      type: :mooc,
      name: "Elixir for the impatient",
      description: "A fast tour of the language",
      image: "https://example.com/elixir.png",
      language: "en",
      external_url: "https://example.com/elixir",
      publish_date: ~D[2026-03-01],
      subject: "Programming",
      tags: ["elixir", "beginner"],
      details: %{duration: 12, real_cost: 0, reason: "It is how we start every Elixir project."}
    ]

    @mooc_body %{
      "type" => "mooc",
      "name" => "Elixir for the impatient",
      "description" => "A fast tour of the language",
      "image" => "https://example.com/elixir.png",
      "language" => "en",
      "external_url" => "https://example.com/elixir",
      "publish_date" => "2026-03-01",
      "subject" => "Programming",
      "tags" => ["elixir", "beginner"],
      "details" => %{
        "duration" => 12,
        "real_cost" => 0,
        "reason" => "It is how we start every Elixir project."
      }
    }

    test "POSTs /api/learning_objects as JSON with the API key as a bearer token, asking for JSON" do
      request_stub(201, @learning_object)

      assert {:ok, _} = Rest.create_learning_object(@mooc)

      assert %{
               method: "POST",
               path: "/api/learning_objects",
               query: query,
               auth: "Bearer " <> @api_key,
               accept: ["application/json"],
               content_type: ["application/json"]
             } = received()

      assert query == %{}
    end

    test "sends the learning object under learning_object, with string keys, atoms and dates as text" do
      request_stub(201, @learning_object)

      assert {:ok, _} = Rest.create_learning_object(@mooc)

      assert received().body == %{"learning_object" => @mooc_body}
    end

    test "takes a map with atom keys, or with string keys, or a keyword list, the same" do
      request_stub(201, @learning_object)

      assert {:ok, _} = Rest.create_learning_object(Map.new(@mooc))
      assert received().body == %{"learning_object" => @mooc_body}

      strings = Map.new(@mooc, fn {key, value} -> {Atom.to_string(key), value} end)
      assert {:ok, _} = Rest.create_learning_object(strings)
      assert received().body == %{"learning_object" => @mooc_body}

      assert {:ok, _} = Rest.create_learning_object(@mooc)
      assert received().body == %{"learning_object" => @mooc_body}
    end

    test "returns the learning object as Nova sends it on a 201" do
      json_stub(201, @learning_object)

      assert {:ok, learning_object} = Rest.create_learning_object(@mooc)
      assert learning_object == @learning_object
    end

    test "only a 201 is a learning object made" do
      json_stub(200, @learning_object)

      capture_log(fn ->
        assert {:error, :create_learning_object_error} = Rest.create_learning_object(@mooc)
      end)
    end

    test "leaves out what is not given or is nil" do
      request_stub(201, @learning_object)

      assert {:ok, _} =
               Rest.create_learning_object(
                 type: :talk,
                 name: "A talk",
                 description: nil,
                 tags: nil
               )

      assert received().body == %{"learning_object" => %{"type" => "talk", "name" => "A talk"}}

      assert {:ok, _} = Rest.create_learning_object([])
      assert received().body == %{"learning_object" => %{}}
    end

    test "sends an empty list of tags and the details of a talk and of a path as they are" do
      request_stub(201, @learning_object)

      assert {:ok, _} =
               Rest.create_learning_object(
                 type: "talk",
                 name: "A talk",
                 tags: [],
                 details: %{subtype: :lightning_talk, speakers: ["u1", "u2"], video_url: nil}
               )

      assert received().body == %{
               "learning_object" => %{
                 "type" => "talk",
                 "name" => "A talk",
                 "tags" => [],
                 "details" => %{
                   "subtype" => "lightning_talk",
                   "speakers" => ["u1", "u2"],
                   "video_url" => nil
                 }
               }
             }

      assert {:ok, _} =
               Rest.create_learning_object(
                 type: :path,
                 name: "A path",
                 details: %{steps: ["c1", "c2"]}
               )

      assert received().body == %{
               "learning_object" => %{
                 "type" => "path",
                 "name" => "A path",
                 "details" => %{"steps" => ["c1", "c2"]}
               }
             }
    end

    test "does not check what Nova checks: a missing type, a long name, details that are not a map" do
      request_stub(201, @learning_object)

      assert {:ok, _} =
               Rest.create_learning_object(
                 type: :blog,
                 name: String.duplicate("n", 1000),
                 details: "not a map",
                 tags: "not a list"
               )

      assert received().body == %{
               "learning_object" => %{
                 "type" => "blog",
                 "name" => String.duplicate("n", 1000),
                 "details" => "not a map",
                 "tags" => "not a list"
               }
             }
    end

    test "raises on a field that is not one of its own, instead of making a learning object without it" do
      asked_stub()

      assert_raise ArgumentError, ~r/unknown keys \[:descripton\]/, fn ->
        Rest.create_learning_object(type: :mooc, name: "x", descripton: "A course")
      end

      assert_raise ArgumentError, ~r/unknown keys \[:descripton\]/, fn ->
        Rest.create_learning_object(%{type: :mooc, name: "x", descripton: "A course"})
      end

      assert_raise ArgumentError, ~r/unknown keys \["descripton"\]/, fn ->
        Rest.create_learning_object(%{
          "type" => "mooc",
          "name" => "x",
          "descripton" => "A course"
        })
      end

      refute_received :asked
    end

    test "raises on creator_id and hidden_at: Nova ignores them, so a call that names them is a mistake" do
      asked_stub()

      assert_raise ArgumentError, ~r/unknown keys \[:creator_id\]/, fn ->
        Rest.create_learning_object(type: :mooc, name: "x", creator_id: "u1")
      end

      assert_raise ArgumentError, ~r/unknown keys \["hidden_at"\]/, fn ->
        Rest.create_learning_object(%{"type" => "mooc", "name" => "x", "hidden_at" => "now"})
      end

      refute_received :asked
    end

    test "raises on what is not a keyword list, without asking Nova" do
      asked_stub()

      assert_raise ArgumentError, ~r/keyword list/, fn ->
        Rest.create_learning_object(["mooc"])
      end

      assert_raise ArgumentError, ~r/unknown keys \[1\]/, fn ->
        Rest.create_learning_object(%{1 => "mooc"})
      end

      refute_received :asked
    end

    test "maps 422 to {:invalid_request, errors}, nested as Nova nests them, and logs the fields" do
      errors = %{
        "name" => ["is required"],
        "details" => %{"duration" => ["is required"], "reason" => ["is required"]}
      }

      json_stub(422, %{"errors" => errors})

      log =
        capture_log(fn ->
          assert {:error, {:invalid_request, ^errors}} =
                   Rest.create_learning_object(type: :mooc)
        end)

      assert log =~ "name is required"
      assert log =~ "details.duration is required"
      assert log =~ "details.reason is required"
    end

    test "maps a course with an address that is taken to {:invalid_request, errors}" do
      errors = %{"external_url" => ["a course with this address already exists"]}
      json_stub(422, %{"errors" => errors})

      capture_log(fn ->
        assert {:error, {:invalid_request, ^errors}} = Rest.create_learning_object(@mooc)
      end)
    end
  end

  describe "init/1" do
    test "requires base_url and api_key" do
      Process.flag(:trap_exit, true)

      assert {:error, {%KeyError{key: :api_key}, _}} =
               GenServer.start(Rest, base_url: "https://nova.test")

      assert {:error, {%KeyError{key: :base_url}, _}} = GenServer.start(Rest, api_key: "k")
    end
  end

  # What the four calls say when it goes wrong
  for fun <- @functions do
    {method, path} = Map.fetch!(@endpoints, fun)
    error = :"#{fun}_error"

    describe "#{fun} errors" do
      test "#{method} #{path} with the API key as a bearer token, asking for JSON" do
        request_stub(ok_status(unquote(fun)), ok_body(unquote(fun)))

        assert {:ok, _} = call(unquote(fun))

        assert %{method: unquote(method), path: unquote(path), auth: "Bearer " <> @api_key} =
                 request = received()

        assert request.accept == ["application/json"]
      end

      test "maps 400 to :bad_request and logs Nova's reason" do
        json_stub(400, %{"error" => "limit must be a number from 1 to 100"})

        log = capture_log(fn -> assert {:error, :bad_request} = call(unquote(fun)) end)

        assert log =~ "Bad request"
        assert log =~ "limit must be a number from 1 to 100"
      end

      test "maps 401 to :unauthorized" do
        json_stub(401, %{"error" => "unauthorized"})

        log = capture_log(fn -> assert {:error, :unauthorized} = call(unquote(fun)) end)

        assert log =~ "Unauthorized"
      end

      test "maps 403 to :forbidden, and the log names every cause: Nova answers the same for both" do
        json_stub(403, %{"error" => "Forbidden"})

        log = capture_log(fn -> assert {:error, :forbidden} = call(unquote(fun)) end)

        assert log =~ "Forbidden"

        for cause <- unquote(Map.fetch!(@forbidden_in_the_log, fun)) do
          assert log =~ cause
        end
      end

      test "maps 422 to {:invalid_request, errors} when Nova files the errors under their fields" do
        errors = %{"name" => ["is required"], "details" => %{"duration" => ["is invalid"]}}
        json_stub(422, %{"errors" => errors})

        log =
          capture_log(fn ->
            assert {:error, {:invalid_request, ^errors}} = call(unquote(fun))
          end)

        assert log =~ "name is required"
        assert log =~ "details.duration is invalid"
      end

      test "maps 422 to {:invalid_request, errors} when Nova says it with one text" do
        json_stub(422, %{"error" => "provide q or external_url"})

        log =
          capture_log(fn ->
            assert {:error, {:invalid_request, %{"base" => ["provide q or external_url"]}}} =
                     call(unquote(fun))
          end)

        assert log =~ "provide q or external_url"
      end

      test "maps other statuses and unexpected bodies to :#{error}" do
        ok = ok_status(unquote(fun))

        for {status, body} <- [
              {500, %{"error" => "Internal Server Error"}},
              {404, %{"errors" => %{"detail" => "Not Found"}}},
              {406, %{"error" => "Not Acceptable"}},
              {422, %{"unexpected" => true}},
              {ok, %{"unexpected" => true}},
              {ok, ["not", "a", "map"]}
            ] do
          json_stub(status, body)

          capture_log(fn -> assert {:error, unquote(error)} = call(unquote(fun)) end)
        end

        # An answer that is not JSON, such as the page of a proxy
        stub(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.send_resp(502, "<html>Bad Gateway</html>")
        end)

        capture_log(fn -> assert {:error, unquote(error)} = call(unquote(fun)) end)
      end

      test "maps transport errors to :#{error}" do
        stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

        capture_log(fn -> assert {:error, unquote(error)} = call(unquote(fun)) end)
      end

      test "logs the HTTP status and Nova's error text of a failure" do
        json_stub(503, %{"error" => "the map is being rebuilt"})

        log = capture_log(fn -> call(unquote(fun)) end)

        assert log =~ "HTTP 503 the map is being rebuilt"
      end

      test "logs neither the API key, nor the position, nor the people, nor anything Nova answered" do
        # Nova's own text may be logged. Everything else of an answer may not, whether the status
        # is a failure or a success that does not look like one.
        sensitive = %{
          "detail" => @answer_text,
          "candidates" => "not a list: #{@answer_text}",
          "person" => %{"email" => @email, "sap_id" => @sap_id, "name" => @answer_text},
          "description" => @description,
          "reference" => @reference,
          "echo" => %{"people" => [%{"email" => @email}, %{"sap_id" => @sap_id}]}
        }

        for {status, body} <- [
              {400, Map.put(sensitive, "error", "description is not text")},
              {401, Map.put(sensitive, "error", "unauthorized")},
              {403, Map.put(sensitive, "error", "Forbidden")},
              {422, %{"errors" => %{"description" => ["is invalid"]}, "echo" => sensitive}},
              {422, Map.put(sensitive, "error", "provide q or external_url")},
              {500, Map.put(sensitive, "error", "Internal Server Error")},
              {200, sensitive},
              {201, sensitive}
            ] do
          json_stub(status, body)

          log = capture_log(fn -> call_with_secrets(unquote(fun)) end)

          assert log != ""

          for secret <- [
                @api_key,
                @description,
                @reference,
                @email,
                to_string(@sap_id),
                @answer_text
              ] do
            refute log =~ secret, "the log of a #{status} shows #{inspect(secret)}"
          end
        end

        stub(fn conn -> Req.Test.transport_error(conn, :timeout) end)
        log = capture_log(fn -> call_with_secrets(unquote(fun)) end)

        assert log != ""

        for secret <- [@api_key, @description, @reference, @email, to_string(@sap_id)] do
          refute log =~ secret
        end
      end
    end
  end

  defp attempts(count \\ 0) do
    receive do
      :attempt -> attempts(count + 1)
    after
      0 -> count
    end
  end

  # Fails the first request, with a 503 or a transport error, and answers well from then on: a
  # client that retried would get a good answer the second time.
  defp fails_once_stub(kind, status, body) do
    test = self()
    counter = :counters.new(1, [])

    stub(fn conn ->
      :counters.add(counter, 1, 1)
      send(test, :attempt)

      cond do
        :counters.get(counter, 1) > 1 ->
          conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)

        kind == :status ->
          conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => "unavailable"})

        kind == :transport ->
          Req.Test.transport_error(conn, :econnrefused)
      end
    end)
  end

  describe "retries" do
    # A client built to retry everything, as far as it can be told
    setup do
      stop_supervised!(Rest)

      start_supervised!(
        {Rest,
         [
           base_url: "https://nova.test",
           api_key: @api_key,
           req_options: [
             plug: {Req.Test, __MODULE__},
             retry: :transient,
             retry_delay: 1,
             max_retries: 3
           ]
         ]}
      )

      :ok
    end

    # Nova keeps every ranking, and every call makes a learning object
    for fun <- [:match_people, :create_learning_object], kind <- [:status, :transport] do
      test "#{fun} is never retried, even when it fails once with #{kind} and a retry would work" do
        fails_once_stub(unquote(kind), ok_status(unquote(fun)), ok_body(unquote(fun)))

        capture_log(fn ->
          assert {:error, unquote(:"#{fun}_error")} = call(unquote(fun))
        end)

        assert attempts() == 1
      end
    end

    test "a POST that keeps failing is asked once" do
      test = self()

      stub(fn conn ->
        send(test, :attempt)
        Req.Test.json(Plug.Conn.put_status(conn, 503), %{"error" => "unavailable"})
      end)

      capture_log(fn ->
        assert {:error, :match_people_error} = call(:match_people)
        assert {:error, :create_learning_object_error} = call(:create_learning_object)
      end)

      assert attempts() == 2
    end

    # The same client does retry what only reads, so the test above is about the call
    for fun <- [:list_technologies, :search_courses], kind <- [:status, :transport] do
      test "#{fun} can be repeated: it follows what the client was built with, after #{kind}" do
        fails_once_stub(unquote(kind), 200, ok_body(unquote(fun)))

        capture_log(fn -> assert {:ok, _} = call(unquote(fun)) end)

        assert attempts() == 2
      end
    end
  end
end
