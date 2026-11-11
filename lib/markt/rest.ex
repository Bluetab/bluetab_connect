defmodule BluetabConnect.Markt.Rest do
  @moduledoc """
  Markt REST Client

  Connects to the Markt app API (`/api/v1`) using an API key (Bearer token). Markt sends the
  email notifications of the Bluetab internal apps (BIA): the app says who and what, Markt
  renders it with an email template and delivers it.

  Markt API keys are scoped: the key must carry the scope of the endpoint it calls, otherwise
  Markt answers `403`:

    * `send_email` - `send_email/1`

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

  @send_email_keys ~w(to variables template subject)a

  @doc """
  Sends an email through Markt (`POST /api/v1/emails`), one for each recipient. Requires an API
  key with the `send_email` scope.

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

  The other values are plain text: Markt escapes them, so they can never add markup.

  The message is read as Markdown, so `*`, `_`, a leading `#` or `-`, and `<tags>` in it mean
  something. That matters when it includes text you did not write (a name, something a user
  typed): escape the Markdown characters with a backslash, or send the message as `%{html: …}`
  with that text escaped.

  ## Options

    * `:to` (required) - The recipients, up to 50 per call: an address, `"Name <address>"`,
      `%{email: address, name: name}`, `{name, address}`, or a list of those. An address that
      appears twice is sent once
    * `:variables` - The values to fill the template with, a map or a keyword list. A `nil`
      value is left out (as if the variable was not given), which is what an optional variable
      such as `:action_url` needs
    * `:template` - The slug of another Markt template (default: the BIA notification one)
    * `:subject` - Replaces the template's subject. It can use `{{variables}}` too

  An unknown option raises `ArgumentError` rather than being ignored. So does a recipient that is
  none of the forms above.

  ## Returns

  The emails are *queued*: Markt answers before handing them to its mail server, which it then
  retries by itself. So `:ok` means Markt accepted the request, not that the email arrived.

      {:ok, [%{"id" => "7db83b7e-…", "to" => "ana@bluetab.net", "status" => "pending"}, ...]}

  `"id"` identifies the email in Markt (Admin → Email activity).

  Errors:

    * `{:error, {:invalid_request, errors}}` - Nothing was sent. `errors` is a list of
      `%{"field" => "to[0]", "message" => "is not a valid email address"}` (`"to[n]"`,
      `"variables.title"`, ...). Markt checks the recipients first, then the values of the
      variables, then the variables the template needs, and reports the problems of the first of
      those that fails; after fixing them a call may show the next group. A message can also be
      refused (`"variables.message"`) for being blank, for having nothing left once cleaned (for
      example only a `<script>`), or for being over 200,000 bytes
    * `{:error, :template_not_found}` - `:template` is not the slug of any template
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
  """
  def send_email(opts) when is_list(opts) do
    opts = Keyword.validate!(opts, Enum.map(@send_email_keys, &{&1, nil}))

    body =
      %{
        "to" => recipients(opts[:to]),
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
