defmodule BluetabConnect.Gedex.Rest do
  @moduledoc """
  Gedex REST Client

  Connects to the Gedex app API (`/api/v1`) using an API key (Bearer token). The API is
  read-only. Gedex API keys are scoped: the key must carry the scope of the endpoint it
  calls (`briefings` for `list_briefings/1`, `evaluations` for `list_evaluations/1`),
  otherwise Gedex answers `403`.

  ## Configuration

    * `:base_url` - Gedex base URL (e.g. `https://gedes.bluetab.net`)
    * `:api_key` - Gedex API key (`gedex_…`)
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

  @filter_keys ~w(user_id user_email period_id evaluator_id evaluator_email status)a
  @list_keys @filter_keys ++ [:page_size]
  @max_page_size 500

  @doc """
  Lists the published briefings from the Gedex briefings API. Requires an API key with the
  `briefings` scope.

  Only published and acknowledged briefings are served; drafts and deleted ones never are. A
  person can have several briefings in a period and all of them are listed.

  Every matching briefing is returned: the client follows the API's pages until the list is
  complete, and a call that fails on any page is an error, never a partial list.

  ## Options

  All optional; they combine (AND). A `nil` or blank value means no filter.

    * `:user_id` - UUID of the person the briefing is about
    * `:user_email` - The same, by email (case-insensitive)
    * `:period_id` - Period id (integer). Without it, every period is listed
    * `:evaluator_id` - UUID of the evaluator (see below)
    * `:evaluator_email` - The same, by email (case-insensitive)
    * `:status` - `"published"` or `"acknowledged"` (a string or an atom)
    * `:page_size` - Items asked per request, `1..#{@max_page_size}` (default `#{@max_page_size}`);
      it only changes how many requests are made, not the result

  An unknown option raises `ArgumentError` rather than being ignored, so a misspelled filter can
  not silently turn into "everything".

  The evaluator is the person's *effective* evaluator for that period and position: after a
  delegation, filtering by the original evaluator no longer returns that person.

  ## Returns

      {:ok, [briefing, ...]}

  Items are maps with string keys, as Gedex sends them, oldest first: `id`, `status`, `date`,
  `role_description`, `evaluator_comments`, `published_at`, `acknowledged_at`, `inserted_at`,
  `updated_at`, `position_id`, `user`, `evaluator` (`nil` when the person has none),
  `created_by`, `period` and `objectives`. Dates are `YYYY-MM-DD`; timestamps are ISO 8601 in
  Madrid time with its offset.

  ## Examples

      BluetabConnect.Gedex.Rest.list_briefings(user_email: "ann@example.com")
      BluetabConnect.Gedex.Rest.list_briefings(period_id: 3, evaluator_id: evaluator_id)
  """
  def list_briefings(opts \\ []), do: list_all(:briefings, opts)

  @doc """
  Lists the published evaluations from the Gedex evaluations API. Requires an API key with the
  `evaluations` scope.

  Takes the same options, and has the same completeness and filtering rules, as
  `list_briefings/1`. `:user_id`, `:user_email`, `:period_id` and the evaluator filters apply to
  the evaluation's briefing.

  ## Returns

      {:ok, [evaluation, ...]}

  Items are maps with string keys, as Gedex sends them, oldest first: `id`, `briefing_id`,
  `status`, `date`, `rating` (`"a"`..`"d"`), `rationale`, `strengths`, `weaknesses`,
  `recommendations`, `tags`, `published_at`, `acknowledged_at`, `inserted_at`, `updated_at`,
  `position_id`, `user`, `evaluator`, `created_by`, `period`, `objective_ratings` and
  `competency_ratings`.

  ## Examples

      BluetabConnect.Gedex.Rest.list_evaluations(user_id: user_id, period_id: 3)
      BluetabConnect.Gedex.Rest.list_evaluations(evaluator_email: "bob@example.com")
  """
  def list_evaluations(opts \\ []), do: list_all(:evaluations, opts)

  defp list_all(resource, opts) do
    opts = Keyword.validate!(opts, Enum.map(@list_keys, &{&1, nil}))
    page_size = page_size!(opts[:page_size])

    filters =
      opts
      |> Keyword.take(@filter_keys)
      |> Enum.reject(fn {_key, value} -> blank?(value) end)
      |> Enum.map(fn {key, value} -> {key, to_string(value)} end)

    fetch_pages(get_client(), resource, filters, page_size, 0, [])
  end

  # The API lists oldest-first, so what is created while we page lands on the last page.
  # Each request advances by the items it returned, whatever limit the server applied.
  defp fetch_pages(client, resource, filters, page_size, offset, acc) do
    params = filters ++ [limit: page_size, offset: offset]

    case Req.get(client, url: path(resource), params: params) do
      {:ok, %{status: 200, body: %{"items" => items, "total" => total}}}
      when is_list(items) and is_integer(total) ->
        acc = [items | acc]
        next_offset = offset + length(items)

        if items == [] or next_offset >= total do
          {:ok, acc |> Enum.reverse() |> Enum.concat()}
        else
          fetch_pages(client, resource, filters, page_size, next_offset, acc)
        end

      other ->
        failure(resource, other)
    end
  end

  defp path(:briefings), do: "/api/v1/briefings"
  defp path(:evaluations), do: "/api/v1/evaluations"

  defp failure(resource, {:ok, %{status: 400} = resp}) do
    Logger.error("Bad request listing #{resource}: #{error_reason(resp)}")
    {:error, :bad_request}
  end

  defp failure(resource, {:ok, %{status: 401} = resp}) do
    Logger.error("Unauthorized listing #{resource}: #{error_reason(resp)}")
    {:error, :unauthorized}
  end

  defp failure(resource, {:ok, %{status: 403} = resp}) do
    Logger.error(
      "Forbidden listing #{resource} (API key needs the #{resource} scope): #{error_reason(resp)}"
    )

    {:error, :forbidden}
  end

  # Responses carry people's evaluations, so only the status and Gedex's error text are logged,
  # never a body.
  defp failure(resource, {:ok, %{status: status} = resp}) do
    Logger.error("Error listing #{resource}: HTTP #{status} #{error_reason(resp)}")
    {:error, :"list_#{resource}_error"}
  end

  defp failure(resource, {:error, exception}) do
    Logger.error("Error listing #{resource}: #{Exception.message(exception)}")
    {:error, :"list_#{resource}_error"}
  end

  defp error_reason(%{body: %{"error" => reason}}) when is_binary(reason), do: reason
  defp error_reason(_resp), do: "(no error message)"

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp page_size!(nil), do: @max_page_size
  defp page_size!(size) when is_integer(size) and size in 1..@max_page_size, do: size

  defp page_size!(other) do
    raise ArgumentError,
          ":page_size must be an integer between 1 and #{@max_page_size}, got: #{inspect(other)}"
  end

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
