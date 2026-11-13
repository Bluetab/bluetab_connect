defmodule BluetabConnect.Nova.Rest do
  @moduledoc """
  Nova REST Client

  Connects to the Nova app API (`/api`; Nova has no version in the path) using an API key (Bearer
  token). Through it an app can rank the people of Nova's knowledge map (the map) for a position,
  and look up and add courses of Nova's learning catalog.

  Nova API keys are scoped, and a key acts as the user it was made for, with the permissions of
  that user. The key must carry the scope of the endpoint it calls, otherwise Nova answers `403`:

    * `matching` - `match_people/1` and `list_technologies/1`. The key's user must also hold the
      `match_people` permission. The answers carry people's employee numbers, names, emails and
      what the map knows of their technologies: give this scope only to apps that need them
    * `learning_objects` - `search_courses/1` and `create_learning_object/1`. To create a talk the
      key's user must also hold the `manage_learning_objects` permission

  The two scopes are independent: a key with one of them is refused on the endpoints of the other.
  **A `403` is the same whether the key lacks the scope or its user lacks the permission**, so when
  one comes, check both. `{:error, :forbidden}` and the log line say so.

  ## Configuration

    * `:base_url` - Nova base URL (e.g. `https://nova.app.bluetab.net`)
    * `:api_key` - Nova API key (`nova_…`), created in Nova under **Admin → API keys** for an
      existing user who holds the permission the scope needs
    * `:req_options` - Extra `Req` options merged into the client (optional, e.g. `:adapter`
      to stub the HTTP layer in tests)

  ## What the four calls have in common

    * Nova checks the data (sizes, ranges, texts) and answers `400` or `422` saying which field is
      wrong and why. The client does not repeat those checks, so it never disagrees with Nova. It
      raises `ArgumentError`, without calling Nova, only for what can be nothing but a mistake of
      the program: an unknown option, `:people` or `:requirements` that is not a list, an entry
      of those lists that is not a map with the key it is made of (`:sap_id` or `:email`,
      `:technology`). Nova ignores a field it does not know, so a misspelled option must not be
      allowed to do the same.
    * The two calls that write (`match_people/1`, which Nova keeps, and `create_learning_object/1`,
      which is not idempotent) are **never retried**, whatever `:req_options` say about retries. A
      retry after a lost answer would keep a second ranking or make a second learning object.
      Retrying is the caller's decision. The two that read follow `:req_options` like the other
      clients.
    * Failures are logged with the HTTP status and Nova's own error text only; never a response
      body, a description, the people, or the key.
  """

  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_client do
    GenServer.call(__MODULE__, :get_client)
  end

  @match_keys ~w(description requirements people reference limit min_score)a
  @search_keys ~w(q external_url limit)a
  @learning_object_keys ~w(type name description image language external_url publish_date subject
                           tags details)a

  @doc """
  Ranks the people of Nova's map for a position (`POST /api/matches`). Requires an API key with the
  `matching` scope **and** whose user holds the `match_people` permission.

  The position is a `:description` (text, in English or Spanish), a list of `:requirements` already
  made, or both: what is listed wins and the description adds the technologies it names. By default
  every person of the map who is still at the company is ranked. With `:people` you name the ones
  to rank, and no one else: the app knows who is free, and the map knows who knows what. Every
  person named is answered for, even one the map knows nothing of.

  A ranking helps a person decide and decides nothing: every candidate comes with the reasons (a
  breakdown for each requirement), so whoever reads it can disagree with it. The same position
  against the same map always gives the same ranking. Nova does not read availability, seniority,
  language or location: combine the ranking with those in the way your decision needs.

  **The answer is about people, and the call is kept.** The answer has each person's employee
  number, name and email, and what the map knows of their technologies: treat it as personal data.
  And Nova keeps every ranking it makes (who asked, the description, the requirements, the
  `:reference`, the people named and the people returned), so call this for a real decision and not
  to try things out. A request Nova refuses keeps nothing.

  ## Options

  `:description` or `:requirements` is needed; the rest is optional. A `nil` value is left out, as
  if the option was not given. Nova checks every value and answers with the field and the reason
  when one is wrong.

    * `:description` - The position, as text. Nova reads it for the technologies of the map that it
      names, how much each matters (*nice to have*, *a plus*, *deseable* make it `"nice"`, anything
      else is `"must"`) and the years it asks for. It does not guess: a technology the map does not
      have is not made up
    * `:requirements` - A list of maps, one for each technology the position asks for:
      `%{technology: "Elixir", importance: "must", min_level: 3, years: 2}`. Only `:technology` is
      needed, a name or an alias of a technology of the map (see `list_technologies/1`); a name the
      map does not have comes back in `"unmatched"`. `:importance` is `"must"` or `"nice"`,
      `:min_level` the level asked, a whole number from 1 to 5, and `:years` the years of
      experience. Atom or string keys. **Nova does not refuse an importance, a level or years it
      cannot read** (`3.0` is not a level, nor is `9`): it takes `"must"` and no level or years
      instead. The `"requirements"` of the answer say what it understood: check them
    * `:people` - The people to rank, and no one else: a list of `%{sap_id: 1234}` (the employee
      number, a number or the same as text) or `%{email: "ana@bluetab.net"}` (in any case), one of
      the two for each person. Other keys of the map are not sent. Left out, everyone on the map who
      is still at the company is ranked; **`people: []` ranks no one**. A person named twice is
      answered for once. The employee number is not unique in Nova: when two users share the one
      named, both are answered for, each with its own `"id"` and `"email"`
    * `:reference` - Your own words for what this is for (a request number, say). Nova keeps it with
      the ranking and gives it back
    * `:limit` - How many people at most. Nova's default is 20 (best first), or all of the `:people`
      named
    * `:min_score` - The least score listed, from 0 to 1. Nova's default is `0.02`, or `0` with
      `:people`, so that every person named is listed

  An unknown option raises `ArgumentError` rather than being ignored. So does `:requirements` that
  is not a list or has an entry that is not a map with a `:technology`, and `:people` that is not a
  list or has an entry that is not a map with a `:sap_id` or an `:email`. The message says which
  entry, and never shows it: it is a person.

  ## Returns

  The answer as Nova sends it, a map with string keys:

      {:ok,
       %{
         "match_id" => "0b5d6c1e-…",
         "ranking_version" => 2,
         "weights_version" => 2,
         "reference" => "REQ-1042",
         "requirements" => [
           %{"technology" => %{"id" => "…", "name" => "Elixir"}, "importance" => "must",
             "min_level" => 3, "years" => 2.0, "mention" => "Elixir", "source" => "given"}
         ],
         "unmatched" => ["Cobol"],
         "unknown_people" => [%{"sap_id" => 4242}],
         "candidates" => [
           %{
             "score" => 0.82,
             "person" => %{"id" => "…", "sap_id" => 1234, "name" => "Ana García",
                           "email" => "ana@bluetab.net", "profile" => "/users/…"},
             "matched" => 1,
             "missing" => [],
             "coverage" => "stated",
             "technologies_known" => 14,
             "breakdown" => [
               %{"technology" => "Elixir", "importance" => "must", "satisfaction" => 0.82,
                 "weight" => 0.9, "proficiency" => 4, "confidence" => 0.8, "years" => 3.0,
                 "recency" => 1.0, "sources" => ["self", "course"], "via" => nil}
             ]
           }
         ]
       }}

    * `"match_id"` - The id of this ranking in Nova, which keeps it. `"ranking_version"` and
      `"weights_version"` are the versions of the numbers that made it
    * `"requirements"` - What Nova understood: each technology (`"id"` and `"name"`), its
      `"importance"`, `"min_level"` and `"years"`, `"mention"` (the words it came from) and
      `"source"` (`"text"`, read from the description, or `"given"`)
    * `"unmatched"` - The names you listed that the map does not have
    * `"unknown_people"` - The people in `:people` that no one at the company answers to, each as
      Nova understood it (`%{"sap_id" => n}`, or `%{"email" => text}` trimmed and in lower case). A
      person who has left is in it too. Empty when `:people` was not given. A name is never dropped
      in silence
    * `"candidates"` - The people, best first. A `"score"` is from 0 to 1. `"matched"` is how many
      requirements the person meets, and `"missing"` the technologies they do not. `"breakdown"` has
      a row for each requirement, with what stands behind it: `"sources"` (any of `"self"`,
      `"staff"`, `"document"`, `"job"`, `"course"`, `"project"`, `"certification"`) and `"via"` (the
      part of the technology it comes from, or `nil`). A requirement the person has nothing for has
      `nil` in `"weight"`, `"proficiency"`, `"confidence"`, `"years"` and `"recency"`, and `[]` in
      `"sources"`. The hours claimed on projects are never returned
    * `"coverage"` - How much the map knows of the person, whatever the position asks. A score of
      nothing means different things: with `"none"` (the map knows nothing of their technologies)
      it is **not known**, it says nothing against them; with `"exposure"` (nothing they said, but
      a course, project work or a certification bears on a technology) it is not known either;
      with `"stated"` (they, or someone who keeps their CV, said they know a technology) it is
      **not for this position**. `"technologies_known"` is in how many technologies the map holds
      a word of theirs. The ranking leans on what people said: it ranks, in part, who has been
      written down

  Errors:

    * `{:error, :bad_request}` - Nova could not read a parameter: nothing to rank (neither a
      description nor requirements), a value out of its range or too long, an entry of `:people`
      that does not name one person (Nova's message says which entry), a `:reference` with control
      characters. Nova's reason is in the log. Nothing was kept
    * `{:error, {:invalid_request, errors}}` - The position names no technology of the map and
      lists none. `errors` is what Nova sends, a map of field to messages:
      `%{"description" => ["does not name a technology the map has, and …"]}`. Nothing was kept
    * `{:error, :unauthorized}` - Unknown, expired or revoked key, or the key's user has left
    * `{:error, :forbidden}` - **Either** the key lacks the `matching` scope, **or** its user lacks
      the `match_people` permission: Nova answers the same for both, so check both
    * `{:error, :match_people_error}` - Anything else, including Nova being unreachable. The
      client does not know whether Nova kept the ranking

  **The request is never retried automatically**, whatever `:req_options` say about retries: Nova
  keeps every ranking, so a retry after a lost answer would keep a second one. Retrying is the
  caller's decision.

  Failures are logged with the HTTP status and Nova's error text only; never the description, the
  people, the answer or the key.

  ## Examples

      # From a description: everyone on the map who is still at the company, best 20
      BluetabConnect.Nova.Rest.match_people(
        description: "We need a backend engineer with 3+ years of Elixir. Kafka is a plus.",
        reference: "REQ-1042"
      )

      # From a list of requirements
      BluetabConnect.Nova.Rest.match_people(
        requirements: [
          %{technology: "Elixir", importance: "must", min_level: 3, years: 3},
          %{technology: "Kafka", importance: "nice"}
        ]
      )

      # Only these people (the ones who are free), all of them answered for
      BluetabConnect.Nova.Rest.match_people(
        description: "Data engineer, Spark and Python.",
        people: [%{sap_id: 1234}, %{email: "bob@bluetab.net"}]
      )
  """
  def match_people(opts) when is_list(opts) do
    opts = options!(opts, @match_keys)

    body =
      %{
        "description" => opts[:description],
        "requirements" => requirements!(opts[:requirements]),
        "people" => people!(opts[:people]),
        "reference" => opts[:reference],
        "limit" => opts[:limit],
        "min_score" => opts[:min_score]
      }
      |> reject_nil()

    # Never retried (`retry: false`), whatever the client was built with: see the doc above.
    case Req.post(get_client(), url: "/api/matches", json: body, retry: false) do
      {:ok, %{status: 200, body: %{"candidates" => candidates} = answer}}
      when is_list(candidates) ->
        {:ok, answer}

      other ->
        failure(:match_people, other)
    end
  end

  @doc """
  Reads the technologies of Nova's map (`GET /api/technologies`), the names a ranking is asked in.
  Requires an API key with the `matching` scope **and** whose user holds the `match_people`
  permission, the same as `match_people/1`.

  Use it to let someone choose what a position asks for, or to check that a name you keep still
  means a technology of the map. It names no person, and Nova keeps nothing of the call.

  It takes no options (`list_technologies/0` is the same call), and an option raises
  `ArgumentError`. Nova answers the whole list: there are no pages.

  ## Returns

      {:ok, [technology, ...]}

  Technologies are maps with string keys, as Nova sends them, by name in any case:

      %{"id" => "…", "name" => "Event Hubs", "aliases" => ["Azure Event Hubs"],
        "category" => "cloud", "parents" => [%{"id" => "…", "name" => "Azure"}], "people" => 7}

  `"aliases"` are the other names that find it: a requirement names a technology by its name or by
  any of them. `"category"` is what it is filed under (`"cloud"`, `"language"`, `"database"`…) or
  `nil`. `"parents"` is what it belongs to: the ranking counts whoever knows a part of a technology
  when the whole is asked for. `"people"` is how many people still at the company have said they
  know it, not counting whoever knows a part of it, nor whoever completed a course on it.

  **Keep the `"name"`, not the `"id"`.** A technology that is merged into another keeps its names
  as aliases of the other, so a name that was kept still finds it; its id goes.

  Errors:

    * `{:error, :unauthorized}` - Unknown, expired or revoked key, or the key's user has left
    * `{:error, :forbidden}` - **Either** the key lacks the `matching` scope, **or** its user lacks
      the `match_people` permission: Nova answers the same for both, so check both
    * `{:error, :list_technologies_error}` - Anything else, including Nova being unreachable

  A read can be repeated, so it follows `:req_options` like the other clients' reads. Failures are
  logged with the HTTP status and Nova's error text only, never a body or the key.

  ## Examples

      {:ok, technologies} = BluetabConnect.Nova.Rest.list_technologies()
      Enum.map(technologies, & &1["name"])
  """
  def list_technologies(opts \\ []) do
    options!(opts, [])

    case Req.get(get_client(), url: "/api/technologies") do
      {:ok, %{status: 200, body: %{"items" => items}}} when is_list(items) ->
        {:ok, items}

      other ->
        failure(:list_technologies, other)
    end
  end

  @doc """
  Looks for courses of Nova's learning catalog by a text or by their exact address
  (`GET /api/learning_objects/moocs/search`). Requires an API key with the `learning_objects`
  scope. The key's user needs no permission for it.

  The text of `:q` is matched against the name, the description, the external URL and the code of
  the courses, without regard to case, **as written**: a `%` or a `_` in it has no special meaning.
  `:external_url` matches the address exactly. With both, a course must match both. Only courses
  that are not hidden are returned. **Courses that are still pending are returned too**, so a
  program can find a course it created, and the result is not limited to the key's user. The
  newest come first.

  ## Options

  At least one of `:q` and `:external_url` has to be a text that is not blank; Nova refuses a call
  with neither, and the client leaves that to it. A `nil` value is left out.

    * `:q` - The text to look for
    * `:external_url` - The address of the course, exactly
    * `:limit` - How many courses at most. Nova's default is 20; it brings a number outside its
      range (1 to 50) into the range, and refuses a value that is not a number

  An unknown option raises `ArgumentError` rather than being ignored. That includes `:query`, which
  Nova takes as an alias of `q` only when `q` is absent: use `:q`.

  ## Returns

      {:ok, [course, ...]}

  Courses are maps with string keys, as Nova sends them:

      %{"id" => "…", "type" => "mooc", "name" => "Elixir for the impatient",
        "description" => "…", "image" => "…", "language" => "en",
        "external_url" => "https://example.com/elixir", "publish_date" => "2026-03-01",
        "subject" => "Programming", "tags" => ["elixir"],
        "code" => 17, "duration" => 12.0, "real_cost" => 0.0, "reason" => "…",
        "certification" => false, "title" => nil, "video" => nil,
        "creator_id" => "…", "published" => true,
        "inserted_at" => "2026-03-01T09:30:00Z", "updated_at" => "2026-03-01T09:30:00Z"}

  `"published"` says whether the course has an action, which is what approving it in Nova gives
  it: a course that is still pending has `false`. Dates are `YYYY-MM-DD` and times ISO 8601 in UTC.
  There are no counts of requests, completions or accesses: Nova does not give how popular a course
  is.

  Errors:

    * `{:error, :bad_request}` - A parameter Nova could not read: a `:limit` that is not a number,
      or a `:q` that is a list or a map. Nova's reason is in the log
    * `{:error, {:invalid_request, errors}}` - Neither `:q` nor `:external_url` is a text that is
      not blank. This is the one `422` that Nova says with a bare text,
      `{"error": "provide q or external_url"}`, and not with a map of fields. The client gives it
      back in the shape of all the others, so that `errors` is always a map of field to messages:
      `%{"base" => ["provide q or external_url"]}`. `"base"` is the name Nova itself uses in its
      `errors` for an error that is about no field in particular
    * `{:error, :unauthorized}` - Unknown, expired or revoked key, or the key's user has left
    * `{:error, :forbidden}` - The key lacks the `learning_objects` scope
    * `{:error, :search_courses_error}` - Anything else, including Nova being unreachable

  A read can be repeated, so it follows `:req_options` like the other clients' reads. Failures are
  logged with the HTTP status and Nova's error text only, never a body or the key.

  ## Examples

      {:ok, courses} = BluetabConnect.Nova.Rest.search_courses(q: "elixir")
      {:ok, courses} = BluetabConnect.Nova.Rest.search_courses(q: "elixir", limit: 5)

      # Has this course been added already?
      {:ok, found} =
        BluetabConnect.Nova.Rest.search_courses(external_url: "https://example.com/elixir")
  """
  def search_courses(opts) when is_list(opts) do
    opts = options!(opts, @search_keys)

    params =
      @search_keys
      |> Enum.map(&{&1, opts[&1]})
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Req.get(get_client(), url: "/api/learning_objects/moocs/search", params: params) do
      {:ok, %{status: 200, body: %{"items" => items}}} when is_list(items) ->
        {:ok, items}

      other ->
        failure(:search_courses, other)
    end
  end

  @doc """
  Adds a learning object to Nova's catalog (`POST /api/learning_objects`). Requires an API key with
  the `learning_objects` scope. To create a `talk`, the key's user must also hold the
  `manage_learning_objects` permission.

  The learning object is created **pending**, and the user of the key is its creator (a creator
  sent in the body is ignored, so this call has no option for it). It is in no list of Nova's
  catalog until it is approved there, but `search_courses/1` finds it. The API cannot approve,
  change, hide or delete anything: those are done in Nova.

  **Creating is not idempotent**: the same call twice makes two learning objects, except for a
  course with an address, which the second time Nova refuses. Look for the course first with
  `search_courses/1` (`external_url:`) if the call may be repeated.

  Takes a keyword list or a map (atom or string keys). A `nil` value is left out.

  ## Fields

    * `:type` - **Required**. `:mooc` (a course), `:talk` or `:path` (a string works too). The API
      has no blog
    * `:name` - **Required**
    * `:description`, `:image` (an address, or a data URI), `:language`, `:external_url` (where a
      course is taken), `:subject`
    * `:publish_date` - A `Date`, or text as `"2026-03-01"`
    * `:tags` - A list of texts
    * `:details` - The details of the type, a map. A **`mooc`** needs `duration` (hours),
      `real_cost` (euros) and `reason` (why the course is worth taking), and can have
      `certification` (`true` or `false`), `title` and `video`. A **`talk`** has `subtype`
      (`"talk"`, `"lightning_talk"` or `"academy_course"`), `speakers` (a list of user ids) and
      `video_url`. A **`path`** has `steps`, a list of learning object ids, in order. The tag of
      the details is the type, so it does not have to be repeated

  Nova checks every value (sizes, units, that a path's steps are learning objects) and answers
  with the field and the reason when one is wrong. A field that is not in the list above raises
  `ArgumentError` rather than being ignored (Nova would ignore it, which is how a misspelled
  `:descripton` would make a learning object without a description). That includes `:creator_id`
  and `:hidden_at`.

  ## Returns

      {:ok, learning_object}

  The learning object as Nova sends it, a map with string keys, in the shape of a course in
  `search_courses/1` with the details of its type (a talk has `"subtype"`, `"speakers"` and
  `"video_url"`; a path has `"steps"`). It has `"published" => false`, and its `"id"` is what a
  path takes as a step.

  Errors:

    * `{:error, {:invalid_request, errors}}` - Nova refused the data (`422`); nothing was created.
      `errors` is what Nova sends, a map of field to messages, nested for the details:
      `%{"details" => %{"duration" => ["is required"]}}`, or
      `%{"external_url" => ["a course with this address already exists"]}`. An error that is about
      no field in particular is under `"base"`. A body with no `:type`, or a `:type` that is not
      one of the three, is refused this way too
    * `{:error, :bad_request}` - A parameter Nova could not read. Nova's reason is in the log
    * `{:error, :unauthorized}` - Unknown, expired or revoked key, or the key's user has left
    * `{:error, :forbidden}` - **Either** the key lacks the `learning_objects` scope, **or**, for a
      `:talk`, its user lacks the `manage_learning_objects` permission: Nova answers the same for
      both, so check both
    * `{:error, :create_learning_object_error}` - Anything else, including Nova being unreachable.
      The client does not know whether Nova made the learning object: look for it with
      `search_courses/1` before trying again

  **The request is never retried automatically**, whatever `:req_options` say about retries: a
  retry after a lost answer would make a second learning object. Retrying is the caller's decision.

  Failures are logged with the HTTP status and Nova's error text only, never the learning object
  or the key.

  ## Examples

      BluetabConnect.Nova.Rest.create_learning_object(
        type: :mooc,
        name: "Elixir for the impatient",
        description: "A fast tour of the language",
        external_url: "https://example.com/elixir",
        language: "en",
        publish_date: ~D[2026-03-01],
        subject: "Programming",
        tags: ["elixir", "beginner"],
        details: %{duration: 12, real_cost: 0, reason: "It is how we start every Elixir project."}
      )

      # A path of courses, in order
      BluetabConnect.Nova.Rest.create_learning_object(%{
        type: :path,
        name: "Backend in Elixir",
        details: %{steps: [first_course["id"], second_course["id"]]}
      })
  """
  def create_learning_object(attrs)
      when is_list(attrs) or (is_map(attrs) and not is_struct(attrs)) do
    body = %{"learning_object" => attrs |> learning_object_fields!() |> reject_nil()}

    # Never retried (`retry: false`), whatever the client was built with: see the doc above.
    case Req.post(get_client(), url: "/api/learning_objects", json: body, retry: false) do
      {:ok, %{status: 201, body: %{"id" => _id} = learning_object}} ->
        {:ok, learning_object}

      other ->
        failure(:create_learning_object, other)
    end
  end

  # The options of a call, or an ArgumentError that says what is wrong without showing a value:
  # the values are people and position descriptions, and the message of an exception ends up in a
  # log (`Keyword.validate!/2` shows the whole list, values included).
  defp options!(opts, allowed) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "expected a keyword list of options"
    end

    case opts |> Keyword.keys() |> Enum.uniq() |> Enum.reject(&(&1 in allowed)) do
      [] -> opts
      unknown -> raise ArgumentError, unknown_keys_message(unknown, allowed)
    end
  end

  defp unknown_keys_message(unknown, []),
    do: "unknown keys #{inspect(unknown)}, this call takes no options"

  defp unknown_keys_message(unknown, allowed),
    do: "unknown keys #{inspect(unknown)}, the allowed keys are: #{inspect(allowed)}"

  # A learning object given as a keyword list or a map (atom or string keys), as a map with string
  # keys.
  defp learning_object_fields!(attrs) when is_list(attrs) do
    attrs
    |> options!(@learning_object_keys)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp learning_object_fields!(attrs) when is_map(attrs) do
    names = Enum.map(@learning_object_keys, &Atom.to_string/1)

    case for({key, _value} <- attrs, field_name(key) not in names, do: key) do
      [] ->
        Map.new(attrs, fn {key, value} -> {field_name(key), value} end)

      unknown ->
        raise ArgumentError, unknown_keys_message(unknown, @learning_object_keys)
    end
  end

  defp field_name(key) when is_atom(key), do: Atom.to_string(key)
  defp field_name(key) when is_binary(key), do: key
  defp field_name(_key), do: nil

  # What the position asks for. Each entry is passed on as it is (Nova reads `technology`,
  # `importance`, `min_level` and `years`); only its shape is checked, as a mistake of the program.
  defp requirements!(nil), do: nil

  defp requirements!(requirements) when is_list(requirements) do
    requirements
    |> Enum.with_index(1)
    |> Enum.each(fn
      {entry, position} when is_map(entry) and not is_struct(entry) ->
        if fetch_field(entry, :technology) == :error, do: bad_requirement!(position)

      {_entry, position} ->
        bad_requirement!(position)
    end)

    requirements
  end

  defp requirements!(_other) do
    raise ArgumentError, ":requirements takes a list of maps, each with a :technology"
  end

  defp bad_requirement!(position) do
    raise ArgumentError,
          ":requirements entry #{position} must be a map with a :technology " <>
            "(and, if wanted, :importance, :min_level and :years)"
  end

  # The people to rank. An entry is sent as the number or the address that names the person, and
  # nothing else of it (a person of the app has more than that, and Nova needs no more). Their
  # values are Nova's to judge: `%{sap_id: "abc"}` is a 400 that says which entry.
  defp people!(nil), do: nil

  defp people!(people) when is_list(people) do
    people
    |> Enum.with_index(1)
    |> Enum.map(fn {person, position} -> person!(person, position) end)
  end

  defp people!(_other) do
    raise ArgumentError, ":people takes a list of %{sap_id: number} or %{email: address}"
  end

  defp person!(person, position) when is_map(person) and not is_struct(person) do
    named =
      for key <- [:sap_id, :email], {:ok, value} <- [fetch_field(person, key)], into: %{} do
        {Atom.to_string(key), value}
      end

    if named == %{}, do: bad_person!(position), else: named
  end

  defp person!(_other, position), do: bad_person!(position)

  defp bad_person!(position) do
    raise ArgumentError,
          ":people entry #{position} must be a map with a :sap_id or an :email, " <>
            "like %{sap_id: 1234} or %{email: \"ana@bluetab.net\"}"
  end

  # A key of a map given as an atom or as a string.
  defp fetch_field(map, key) do
    case Map.fetch(map, key) do
      {:ok, _value} = found -> found
      :error -> Map.fetch(map, Atom.to_string(key))
    end
  end

  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  # What a call says when it goes wrong. Only the status and Nova's own error text are logged:
  # a body can carry people, and a request is people and position descriptions.
  defp failure(action, {:ok, %{status: 400} = resp}) do
    Logger.error("Bad request #{doing(action)}: #{error_reason(resp)}")
    {:error, :bad_request}
  end

  defp failure(action, {:ok, %{status: 401} = resp}) do
    Logger.error("Unauthorized #{doing(action)}: #{error_reason(resp)}")
    {:error, :unauthorized}
  end

  # Nova answers the same whether the key lacks the scope or the key's user lacks the permission,
  # so the line says both.
  defp failure(action, {:ok, %{status: 403} = resp}) do
    Logger.error(
      "Forbidden #{doing(action)} (#{forbidden_causes(action)}): #{error_reason(resp)}"
    )

    {:error, :forbidden}
  end

  # Nova files the errors of a field under the field (`%{"details" => %{"duration" => [...]}}`),
  # and the one of the course search, which has no field, as a single text.
  defp failure(action, {:ok, %{status: 422, body: %{"errors" => errors}}}) when is_map(errors) do
    Logger.error("Invalid request #{doing(action)}: #{format_errors(errors)}")
    {:error, {:invalid_request, errors}}
  end

  defp failure(action, {:ok, %{status: 422, body: %{"error" => reason}}})
       when is_binary(reason) do
    Logger.error("Invalid request #{doing(action)}: #{reason}")
    {:error, {:invalid_request, %{"base" => [reason]}}}
  end

  defp failure(action, {:ok, %{status: status} = resp}) do
    Logger.error("Error #{doing(action)}: HTTP #{status} #{error_reason(resp)}")
    {:error, :"#{action}_error"}
  end

  defp failure(action, {:error, exception}) do
    Logger.error("Error #{doing(action)}: #{Exception.message(exception)}")
    {:error, :"#{action}_error"}
  end

  defp doing(:match_people), do: "matching people"
  defp doing(:list_technologies), do: "listing the technologies"
  defp doing(:search_courses), do: "searching courses"
  defp doing(:create_learning_object), do: "creating a learning object"

  defp forbidden_causes(action) when action in [:match_people, :list_technologies] do
    "the API key lacks the matching scope, or its user lacks the match_people permission; " <>
      "Nova answers the same for both"
  end

  defp forbidden_causes(:search_courses), do: "the API key lacks the learning_objects scope"

  defp forbidden_causes(:create_learning_object) do
    "the API key lacks the learning_objects scope, or its user lacks the permission for this " <>
      "type (a talk needs manage_learning_objects); Nova answers the same for both"
  end

  defp error_reason(%{body: %{"error" => reason}}) when is_binary(reason), do: reason
  defp error_reason(_resp), do: "(no error message)"

  # `%{"details" => %{"duration" => ["is required"]}}` as "details.duration is required".
  defp format_errors(errors) do
    errors |> error_lines([]) |> Enum.join("; ")
  end

  defp error_lines(%{} = errors, path) do
    errors
    |> Enum.sort_by(fn {field, _messages} -> to_string(field) end)
    |> Enum.flat_map(fn {field, messages} ->
      error_lines(messages, path ++ [to_string(field)])
    end)
  end

  defp error_lines(messages, path) when is_list(messages) do
    Enum.flat_map(messages, &error_lines(&1, path))
  end

  defp error_lines(message, path) when is_binary(message),
    do: [String.trim("#{Enum.join(path, ".")} #{message}")]

  defp error_lines(_other, path),
    do: [String.trim("#{Enum.join(path, ".")} (unreadable error)")]

  @impl true
  def init(config) do
    base_url = Keyword.fetch!(config, :base_url)
    api_key = Keyword.fetch!(config, :api_key)
    req_options = Keyword.get(config, :req_options, [])

    client =
      [
        base_url: base_url,
        auth: {:bearer, api_key},
        headers: [{"accept", "application/json"}]
      ]
      |> Req.new()
      |> Req.merge(req_options)

    {:ok, %{client: client}}
  end

  @impl true
  def handle_call(:get_client, _from, %{client: client} = state) do
    {:reply, client, state}
  end
end
