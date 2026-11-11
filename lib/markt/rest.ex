defmodule BluetabConnect.Markt.Rest do
  @moduledoc """
  Markt REST Client

  Connects to the Markt app API (`/api/v1`) using an API key (Bearer token). Markt sends the
  email notifications of the Bluetab internal apps (BIA): the app says who and what, Markt
  renders it with an email template and delivers it.

  Markt API keys are scoped: the key must carry the scope of the endpoint it calls, otherwise
  Markt answers `403`:

    * `send_email` - `send_email/1`
    * `manage_groups` - `get_group/1`, `sync_group/2`, `add_group_member/2` and
      `remove_group_member/2`, to keep a group of people up to date in Markt. The two scopes are
      independent: sending to a group needs `send_email`, not `manage_groups`

  Email only goes to people of the organization (the Markt users, synced from PX, who have not left
  the company). An address that is not one is never sent to, and is never added to a group.

  ## Configuration

    * `:base_url` - Markt base URL (e.g. `https://markt.app.bluetab.net`)
    * `:api_key` - Markt API key (`markt_…`), created in Markt under **Admin → API keys**
    * `:req_options` - Extra `Req` options merged into the client (optional, e.g. `:adapter`
      to stub the HTTP layer in tests)
  """

  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_client do
    GenServer.call(__MODULE__, :get_client)
  end

  @send_email_keys ~w(to group variables template subject)a

  @doc """
  Sends an email through Markt (`POST /api/v1/emails`), to some people or to a group. Requires an
  API key with the `send_email` scope.

  By default the email uses Markt's generic BIA notification template: a bar on top with the
  Bluetab logo, the app name and a subtitle, a greeting, the message and a footer. It takes
  these `:variables`:

    * `:title` (required) - The subject of the email (`[App] Title`). It is **not shown in the
      body**: if you want a heading, write it in the message
    * `:message` (required) - The body, in **Markdown** (headings, lists, tables, links, quotes,
      code). A plain string works as it always did: a line break stays a line break and a blank
      line starts a paragraph. For HTML give `%{html: "<p>…</p>"}`; `%{markdown: "…"}` says
      "Markdown" explicitly. Markt removes whatever could run (scripts, forms, event handlers,
      `javascript:` links), and a tag written inside Markdown is dropped (its text stays)
    * `:subtitle` - Text on the right of the bar on top, e.g. the section of the app. Optional
    * `:app_name` - Shown next to the logo, in the subject and in the footer. Default `"BIA"`
    * `:action_url` - If given, the email has a button that links to it. Must be an `http(s)://`
      or `mailto:` link
    * `:action_label` - The text of that button. Default `"Open"`

  The other values are plain text: Markt escapes them, so they can never add markup. A template
  can also use the name of the person (`name`, `first_name`, `last_name`, `email`) and `site_url`:
  Markt fills these in, so do not pass them.

  The message is read as Markdown, so `*`, `_`, a leading `#` or `-`, and `<tags>` in it mean
  something. That matters when it includes text you did not write (a name, something a user
  typed): escape the Markdown characters with a backslash, or send the message as `%{html: …}`
  with that text escaped.

  ## Options

  Give `:to` or `:group`, not both.

    * `:to` - The recipients, up to 50 per call: an address, `"Name <address>"`,
      `%{email: address, name: name}`, `{name, address}`, or a list of those. An address that
      appears twice is sent once. **Each has to be a person of the organization**: the name in the
      email is the one Markt has for that person, and `:name` here is only used if it has none
    * `:group` - The slug of a group an app keeps up to date in Markt (see `sync_group/2`), instead
      of `:to`. How it goes out is a setting of the group: **one email to each person** (up to 500
      people; each with their own name and their own tracking) or **one email to everyone**, who
      all see who it went to (up to 50 people; nothing in it can be about one person, so the
      template must not greet by name). Any key with the `send_email` scope can send to any
      group an app owns. Never to a group people made in Markt
    * `:variables` - The values to fill the template with, a map or a keyword list. A `nil`
      value is left out (as if the variable was not given), which is what an optional variable
      such as `:action_url` needs
    * `:template` - The slug of another Markt template (default: the BIA notification one)
    * `:subject` - Replaces the template's subject. It can use `{{variables}}` too

  An unknown option raises `ArgumentError` rather than being ignored. So does a recipient that is
  none of the forms above, a `:group` that is not a slug, and giving both `:to` and `:group`.

  ## Returns

  The emails are *queued*: Markt answers before handing them to its mail server, which it then
  retries by itself. So `:ok` means Markt accepted the request, not that the email arrived.

      {:ok, [%{"id" => "7db83b7e-…", "to" => "ana@bluetab.net", "status" => "pending"}, ...]}

  `"id"` identifies the email in Markt (Admin → Email activity). The list has one item for each
  email, and two things to look for:

    * **An address Markt did not send to** is in the list too, so one outsider does not stop the
      rest. It has no id, and says why: `"reason"` is `"unknown_recipient"` (Markt does not know
      the address) or `"left_company"` (it belonged to someone who has left):

          %{"id" => nil, "to" => "outsider@gmail.com", "status" => "rejected",
            "reason" => "unknown_recipient"}

      Check for `"status" => "rejected"` if you need to know. Markt keeps a list of them in
      Admin → Refused addresses. If *nobody* can receive the email the call is an
      `{:invalid_request, errors}` instead
    * **One email to everyone** (a public group) is one item, whose `"to"` is the first address and
      whose `"recipients"` lists them all

  Errors:

    * `{:error, {:invalid_request, errors}}` - Nothing was sent. `errors` is a list of
      `%{"field" => "to[0]", "message" => "is not a valid email address"}` (`"to[n]"`,
      `"variables.title"`, ...). Markt checks the recipients first, then the values of the
      variables, then the variables the template needs, and reports the problems of the first of
      those that fails; after fixing them a call may show the next group. A message can also be
      refused (`"variables.message"`) for being blank, for having nothing left once cleaned (for
      example only a `<script>`), or for being over 200,000 bytes
    * `{:error, :template_not_found}` - `:template` is not the slug of any template
    * `{:error, :group_not_found}` - `:group` is not the slug of a group an app owns
    * `{:error, :unauthorized}` - Unknown, deleted or expired key
    * `{:error, :forbidden}` - The key lacks the `send_email` scope
    * `{:error, :send_email_error}` - Anything else, including Markt being unreachable. The
      client does not know whether Markt queued the email

  **The request is never retried automatically**, whatever `:req_options` say about retries: a
  retry after a lost answer would send the email twice. Retrying is the caller's decision.

  Failures are logged with the HTTP status and Markt's error text only; never the recipients, the
  variables or the key.

  ## Examples

      BluetabConnect.Markt.Rest.send_email(
        to: "ana@bluetab.net",
        variables: %{title: "Labor claim approved", message: "Your claim #4521 was approved."}
      )

      BluetabConnect.Markt.Rest.send_email(
        to: ["ana@bluetab.net", %{email: "bob@bluetab.net", name: "Bob Ruiz"}],
        variables: %{
          app_name: "Tempo",
          subtitle: "Labor claims",
          title: "Labor claim approved",
          message: "Your claim **#4521** was approved.\\nThe payment is scheduled for Friday.",
          action_url: "https://tempo.app.bluetab.net/claims/4521",
          action_label: "View claim"
        }
      )

      # The message with structure (Markdown), or written in HTML
      BluetabConnect.Markt.Rest.send_email(
        to: "ana@bluetab.net",
        variables: %{
          title: "Monthly report",
          message: "## Summary\\n\\n- Hours: 160\\n- Absences: 2\\n\\nSee [the report](https://tempo.app.bluetab.net)."
        }
      )

      BluetabConnect.Markt.Rest.send_email(
        to: "ana@bluetab.net",
        variables: %{title: "Monthly report", message: %{html: "<p>Hours: <strong>160</strong></p>"}}
      )

      # To a group that the app keeps up to date (see `sync_group/2`)
      BluetabConnect.Markt.Rest.send_email(
        group: "tempo-business-operators",
        variables: %{app_name: "Tempo", title: "Closing time changed", message: "From Monday the close is at 18:00."}
      )
  """
  def send_email(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, Enum.map(@send_email_keys, &{&1, nil}))
    check_target!(opts)

    body =
      %{
        "to" => recipients(opts[:to]),
        "group" => opts[:group],
        "variables" => variables(opts[:variables]),
        "template" => opts[:template],
        "subject" => opts[:subject]
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    # Never retried (`retry: false`), whatever the client was built with: see the doc above.
    case Req.post(get_client(), url: "/api/v1/emails", json: body, retry: false) do
      {:ok, %{status: 202, body: %{"data" => queued}}} when is_list(queued) ->
        {:ok, queued}

      {:ok, %{status: 422, body: %{"errors" => errors}}} when is_list(errors) ->
        Logger.error("Markt refused the email: #{format_errors(errors)}")
        {:error, {:invalid_request, errors}}

      {:ok, %{status: 404, body: %{"error" => "template_not_found"}}} ->
        Logger.error("Markt has no template with the given slug")
        {:error, :template_not_found}

      {:ok, %{status: 404, body: %{"error" => "group_not_found"}}} ->
        Logger.error("Markt has no group that an app owns with the given slug")
        {:error, :group_not_found}

      {:ok, %{status: 401} = resp} ->
        Logger.error("Unauthorized sending an email: #{error_reason(resp)}")
        {:error, :unauthorized}

      {:ok, %{status: 403} = resp} ->
        Logger.error(
          "Forbidden sending an email (API key needs the send_email scope): #{error_reason(resp)}"
        )

        {:error, :forbidden}

      {:ok, %{status: status} = resp} ->
        Logger.error("Error sending an email: HTTP #{status} #{error_reason(resp)}")
        {:error, :send_email_error}

      {:error, exception} ->
        Logger.error("Error sending an email: #{Exception.message(exception)}")
        {:error, :send_email_error}
    end
  end

  @group_keys ~w(name description visibility members)a

  @doc """
  Makes a group in Markt, or changes it, and (if `:members` is given) leaves exactly those people in
  it (`PUT /api/v1/groups/:slug`). Requires an API key with the `manage_groups` scope.

  This is the call for an app to make on start-up, to confirm that the group of a role is in sync
  with its own data: it is safe to repeat and makes the same group every time. Then keep the group
  up to date as people come and go with `add_group_member/2` and `remove_group_member/2`, and send
  to it with `send_email/1` (`group: slug`).

  The group is **owned by the key that made it**: it says *Managed by …* in Markt, its people are not
  edited by hand there, and the API only touches groups made this way, never the ones people make
  in Markt. The `slug` is its name in the API: 3 to 80 lower case letters, digits and hyphens.
  Start it with the name of the app (`"tempo-business-operators"`) so two apps do not meet.

  ## Options

    * `:name` - Required to make the group (it defaults to the slug). It has to be different from
      the name of every other group
    * `:description` - Optional
    * `:visibility` - How an email to the group goes out. `:bcc` (the default): one email **to each
      person**, so each can be tracked, with their own name. `:public`: **one email to everyone**,
      who all see who it went to, up to 50 people. **Leave it out to keep what is set in Markt**:
      whoever manages email there can change it, and a call that does not give it does not undo
      that
    * `:members` - The people, up to 1000: addresses, or maps with an `:email` (a Markt user or a
      row of your own, for example). The name is the one of the person in Markt. **If it is given,
      those are the people in the group and the others are taken out**, also whoever has left the
      company since; `members: []` empties the group. **If it is not given, the people are left as
      they are**, so a call can change the name without touching them. The people have to be
      people of the organization: the others are not added, and come back in `"rejected"`

  An unknown option, a `slug` that is not a non-empty string, and a member that is none of the
  forms above raise `ArgumentError`.

  ## Returns

  What Markt answers, with string keys:

      {:ok,
       %{
         "data" => %{
           "slug" => "tempo-business-operators",
           "name" => "Tempo business operators",
           "description" => nil,
           "visibility" => "bcc",
           "managed_by" => "Tempo production",
           "member_count" => 2,
           "members" => [%{"email" => "ana@bluetab.net", "name" => "Ana García"}, ...]
         },
         "added" => 2,
         "removed" => 0,
         "skipped" => 0,
         "rejected" => [%{"email" => "outsider@gmail.com", "reason" => "unknown_recipient"}]
       }}

  `"added"`, `"removed"` and `"skipped"` (already in the group) count people. `"rejected"` is the
  addresses that are not people of the organization, with `"unknown_recipient"` or
  `"left_company"` as the reason; Markt notes them in Admin → Refused addresses. An app can log them
  and carry on: the rest of the people were synced.

  Errors:

    * `{:error, {:invalid_request, errors}}` - Nothing was changed. `errors` is a list of
      `%{"field" => "members[2]", "message" => "is not a valid email address"}` (`"slug"`,
      `"name"` when it is taken, `"visibility"`, `"members"`: more than 1000 people, or a public
      group with more than 50)
    * `{:error, :group_not_managed}` - The slug is the one of a group that people made in Markt:
      an app cannot change it
    * `{:error, :unauthorized}` - Unknown, deleted or expired key
    * `{:error, :forbidden}` - The key lacks the `manage_groups` scope
    * `{:error, :sync_group_error}` - Anything else, including Markt being unreachable

  Unlike a send, this can be repeated: an answer that got lost is no reason not to call again.

  ## Examples

      BluetabConnect.Markt.Rest.sync_group("tempo-business-operators",
        name: "Tempo business operators",
        description: "People with the Business Operators role in Tempo",
        members: Enum.map(operators, & &1.email)
      )

      # Only change how it is sent, leave the people as they are
      BluetabConnect.Markt.Rest.sync_group("tempo-business-operators", visibility: :public)
  """
  def sync_group(slug, opts \\ []) when is_list(opts) do
    slug = slug!(slug)
    opts = Keyword.validate!(opts, Enum.map(@group_keys, &{&1, nil}))

    body =
      opts
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new(fn {key, value} -> {Atom.to_string(key), group_value(key, value)} end)

    get_client()
    |> Req.put(url: group_path(slug), json: body)
    |> group_response({"sync the group", :sync_group_error}, :body)
  end

  @doc """
  Reads a group an app owns, with its people (`GET /api/v1/groups/:slug`). Requires an API key with
  the `manage_groups` scope.

  Returns `{:ok, group}`, the `"data"` of `sync_group/2`'s answer:

      {:ok, %{"slug" => "tempo-business-operators", "visibility" => "bcc", "member_count" => 2,
              "members" => [%{"email" => "ana@bluetab.net", "name" => "Ana García"}, ...], ...}}

  Errors: `{:error, :group_not_found}` (there is no group with that slug that an app owns),
  `{:error, :group_not_managed}` (people made it in Markt), `{:error, :unauthorized}`,
  `{:error, :forbidden}` (the key lacks the `manage_groups` scope) and
  `{:error, :get_group_error}` (anything else, including Markt being unreachable).
  """
  def get_group(slug) do
    slug = slug!(slug)

    get_client()
    |> Req.get(url: group_path(slug))
    |> group_response({"read the group", :get_group_error}, :data)
  end

  @doc """
  Adds one person to a group an app owns (`PUT /api/v1/groups/:slug/members/:email`); nothing
  happens if they are in it. Requires an API key with the `manage_groups` scope.

  `member` is an address, or a map with an `:email`. Returns what Markt answers, as `sync_group/2`
  does: `{:ok, %{"data" => group, "added" => 1, "removed" => 0, "skipped" => 0, "rejected" => []}}`
  (`"skipped" => 1` if they were in it already).

  Errors: `{:error, {:invalid_request, errors}}` (the address is not valid, it is not a person of
  the organization, or the group is public and would have more than 50 people),
  `{:error, :group_not_found}`, `{:error, :group_not_managed}`, `{:error, :unauthorized}`,
  `{:error, :forbidden}` and `{:error, :add_group_member_error}` (anything else).
  """
  def add_group_member(slug, member) do
    path = member_path(slug!(slug), email!(member))

    get_client()
    |> Req.put(url: path)
    |> group_response({"add the person to the group", :add_group_member_error}, :body)
  end

  @doc """
  Takes one person out of a group an app owns (`DELETE /api/v1/groups/:slug/members/:email`);
  nothing happens if they are not in it. Requires an API key with the `manage_groups` scope.

  `member` is an address, or a map with an `:email`. Returns what Markt answers:
  `{:ok, %{"data" => group, "removed" => 1}}` (`"removed" => 0` if they were not in it).

  Errors: `{:error, :group_not_found}`, `{:error, :group_not_managed}`, `{:error, :unauthorized}`,
  `{:error, :forbidden}` and `{:error, :remove_group_member_error}` (anything else).
  """
  def remove_group_member(slug, member) do
    path = member_path(slug!(slug), email!(member))

    get_client()
    |> Req.delete(url: path)
    |> group_response({"take the person out of the group", :remove_group_member_error}, :body)
  end

  defp group_response(
         {:ok, %{status: status, body: %{"data" => data} = body}},
         _action,
         unwrap
       )
       when status in [200, 201] do
    case unwrap do
      :data -> {:ok, data}
      :body -> {:ok, body}
    end
  end

  defp group_response({:ok, %{status: 422, body: %{"errors" => errors}}}, {action, _}, _)
       when is_list(errors) do
    Logger.error("Markt refused to #{action}: #{format_errors(errors)}")
    {:error, {:invalid_request, errors}}
  end

  defp group_response(
         {:ok, %{status: 404, body: %{"error" => "group_not_found"}}},
         {action, _},
         _
       ) do
    Logger.error("Could not #{action}: Markt has no group that an app owns with that slug")
    {:error, :group_not_found}
  end

  defp group_response(
         {:ok, %{status: 403, body: %{"error" => "group_not_managed"}}},
         {action, _},
         _
       ) do
    Logger.error(
      "Could not #{action}: the group was made by people in Markt, not through the API"
    )

    {:error, :group_not_managed}
  end

  defp group_response({:ok, %{status: 401} = resp}, {action, _}, _) do
    Logger.error("Unauthorized trying to #{action}: #{error_reason(resp)}")
    {:error, :unauthorized}
  end

  defp group_response({:ok, %{status: 403} = resp}, {action, _}, _) do
    Logger.error(
      "Forbidden trying to #{action} (API key needs the manage_groups scope): #{error_reason(resp)}"
    )

    {:error, :forbidden}
  end

  defp group_response({:ok, %{status: status} = resp}, {action, error}, _) do
    Logger.error("Error trying to #{action}: HTTP #{status} #{error_reason(resp)}")
    {:error, error}
  end

  defp group_response({:error, exception}, {action, error}, _) do
    Logger.error("Error trying to #{action}: #{Exception.message(exception)}")
    {:error, error}
  end

  defp group_value(:members, members) when is_list(members), do: Enum.map(members, &member!/1)

  defp group_value(:members, other) do
    raise ArgumentError, ":members takes a list of addresses, got: #{inspect(other)}"
  end

  defp group_value(:visibility, visibility) when is_atom(visibility),
    do: Atom.to_string(visibility)

  defp group_value(_key, value), do: value

  # The people of a group are sent as plain addresses: their names are Markt's, not ours.
  defp member!(address) when is_binary(address), do: address

  defp member!(%{} = member) do
    case recipient_field(member, :email) do
      address when is_binary(address) -> address
      _none -> bad_member!(member)
    end
  end

  defp member!(other), do: bad_member!(other)

  defp bad_member!(member) do
    raise ArgumentError,
          "a member of a group is an address or a map with an :email, got: #{inspect(member)}"
  end

  defp email!(member) do
    case member!(member) do
      "" -> bad_member!(member)
      address -> address
    end
  end

  defp slug!(slug) when is_binary(slug) and slug != "", do: slug

  defp slug!(other) do
    raise ArgumentError,
          "a group is named by its slug, a non-empty string such as \"tempo-business-operators\", " <>
            "got: #{inspect(other)}"
  end

  # Only one of `to` and `group` says who the email is for.
  defp check_target!(opts), do: check_target!(opts[:to], opts[:group])
  defp check_target!(_to, nil), do: :ok
  defp check_target!(nil, group), do: slug!(group)

  defp check_target!(_to, _group) do
    raise ArgumentError, "an email goes :to some people or to a :group, not both"
  end

  defp group_path(slug), do: "/api/v1/groups/" <> path_segment(slug)
  defp member_path(slug, email), do: group_path(slug) <> "/members/" <> path_segment(email)

  # An address has an `@`, which goes in a path as %40.
  defp path_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  # A single recipient is sent as a single recipient, a list as a list. Markt takes both; nothing
  # given is left out so that Markt answers "to is required" rather than the client guessing.
  defp recipients(nil), do: nil
  defp recipients(recipients) when is_list(recipients), do: Enum.map(recipients, &recipient/1)
  defp recipients(recipient), do: recipient(recipient)

  defp recipient(address) when is_binary(address), do: address

  defp recipient({name, address}) when is_binary(name) and is_binary(address),
    do: %{"email" => address, "name" => name}

  defp recipient(%{} = recipient) do
    case recipient_field(recipient, :email) do
      address when is_binary(address) ->
        %{"email" => address, "name" => recipient_field(recipient, :name)}
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      _none ->
        bad_recipient!(recipient)
    end
  end

  defp recipient(other), do: bad_recipient!(other)

  defp recipient_field(recipient, key),
    do: Map.get(recipient, key) || Map.get(recipient, Atom.to_string(key))

  defp bad_recipient!(recipient) do
    raise ArgumentError,
          ":to takes addresses, \"Name <address>\", %{email: _, name: _} or {name, address}, " <>
            "got: #{inspect(recipient)}"
  end

  defp variables(nil), do: nil

  defp variables(variables) when is_map(variables) or is_list(variables) do
    variables
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Map.new(fn {name, value} -> {to_string(name), value} end)
  end

  defp format_errors(errors) do
    Enum.map_join(errors, "; ", fn
      %{"field" => field, "message" => message} -> "#{field} #{message}"
      _other -> "(unreadable error)"
    end)
  end

  defp error_reason(%{body: %{"error" => reason}}) when is_binary(reason), do: reason
  defp error_reason(_resp), do: "(no error message)"

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
