defmodule BluetabConnect.Tempo.Rest do
  @moduledoc """
  Tempo REST Client

  Connects to the Tempo app API using an API key (Bearer token). Tempo API keys
  are scoped: the key must carry the scope of the endpoint it calls (`holidays`
  for `list_holidays/1`, `labor_claims` for `labor_claims_summary/1` and
  `labor_claims_date_range/1`), otherwise Tempo answers `403`.

  The `labor_claims` scope reaches everything under `/api/v1/labor-claims`, including the
  endpoints that approve and reject claims. This client only reads.

  ## Configuration

    * `:base_url` - Tempo base URL (e.g. `https://tempo.app.bluetab.net`)
    * `:api_key` - Tempo API key (`tempo_…`)
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

  @holiday_filter_keys ~w(calendar_code date_from date_to)a

  @doc """
  Lists the active holidays from the Tempo holidays API.

  Tempo mirrors the holiday calendars of SAP SuccessFactors. Holidays that
  SuccessFactors stopped returning are hidden in Tempo and are not included
  here. Requires an API key with the `holidays` scope.

  ## Options

    * `:calendar_code` - Only the holidays of this calendar (matches the employee `hub`)
    * `:date_from` - Include holidays with `date >= date_from` (`YYYY-MM-DD` or `Date`)
    * `:date_to` - Include holidays with `date <= date_to` (`YYYY-MM-DD` or `Date`)

  If no options are provided, returns every active holiday of every calendar.

  An invalid date returns `{:error, :bad_request}`.

  ## Returns

      {:ok, [%{"calendar_code" => ..., "date" => ..., "holiday_code" => ..., "name" => ...}, ...]}

  Items are ordered by `calendar_code`, `date` and `holiday_code`. `date` is an
  ISO 8601 string (`YYYY-MM-DD`).

  ## Examples

      BluetabConnect.Tempo.Rest.list_holidays()
      BluetabConnect.Tempo.Rest.list_holidays(calendar_code: "MADRID")
      BluetabConnect.Tempo.Rest.list_holidays(
        calendar_code: "MADRID",
        date_from: ~D[2026-01-01],
        date_to: ~D[2026-12-31]
      )
  """
  def list_holidays(opts \\ []) do
    base_req = get_client()

    query_params =
      opts
      |> Keyword.take(@holiday_filter_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {k, format_query_value(v)} end)

    case Req.get(base_req, url: "/api/v1/holidays", params: query_params) do
      {:ok, %{body: %{"items" => items}, status: 200}} when is_list(items) ->
        {:ok, items}

      {:ok, %{status: 400} = resp} ->
        Logger.error("Bad request listing holidays: #{error_reason(resp)}")
        {:error, :bad_request}

      {:ok, %{status: 401} = resp} ->
        Logger.error("Unauthorized listing holidays: #{error_reason(resp)}")
        {:error, :unauthorized}

      {:ok, %{status: 403} = resp} ->
        Logger.error(
          "Forbidden listing holidays (API key needs the holidays scope): #{error_reason(resp)}"
        )

        {:error, :forbidden}

      err ->
        Logger.error("Error listing holidays: #{inspect(err)}")
        {:error, :list_holidays_error}
    end
  end

  @labor_claim_id_filters ~w(employee_id employee_ids project_id project_ids)a
  @labor_claim_statuses ~w(draft submitted approved rejected pending_approval)
  @labor_claim_groupings ~w(project_id employee_id year month day status hour_type precontrato)

  @doc """
  Aggregates the hours of the labor claims of Tempo (`GET /api/v1/labor-claims/summary`).

  A labor claim is the hours that an employee claims on a project for a day. Tempo sums them in
  its database, so this answers a few rows and not one for each claim. Requires an API key with
  the `labor_claims` scope. Deleted claims are not counted. Tempo caches the answer, and
  refreshes it when the claims of an employee change.

  ## Options

    * `:date_from` / `:date_to` - Inclusive range of claim dates (`Date` or `YYYY-MM-DD`)
    * `:employee_id` / `:employee_ids` - SAP employee number(s)
    * `:project_id` / `:project_ids` - SAP project id(s) (`sap_id` of the project in PX, which is
      not its `doc_num`)
    * `:status` - Only the claims in this status: `draft`, `submitted`, `approved`, `rejected`
      (or `pending_approval`, which Tempo reads as `submitted`). One status: Tempo does not take a list.
    * `:group_by` - What to group by, a list of `:employee_id`, `:project_id`, `:year`, `:month`,
      `:day`, `:status`, `:hour_type` and `:precontrato`. Without it Tempo answers one row
      with the totals.

  A date that is not a date, a `:status` that is not one of those, a `:group_by` that is not a list
  of those: `{:error, :bad_request}`, **without asking Tempo**. Tempo itself ignores them,
  and an ignored date would sum the claims of every day.

  ## Returns

      {:ok, [%{"employee_id" => 92, "project_id" => 12345, "status" => "approved",
               "total_hours" => 80.0, "entry_count" => 10}, ...]}

  Each item has `"total_hours"` (a float) and `"entry_count"` (the claims summed), and a key for
  each of the `:group_by`. `"employee_id"` and `"project_id"` are `nil` for a claim of a user or
  a project that Tempo has no SAP id for.

  Errors: `{:error, :unauthorized}` (unknown or expired key), `{:error, :forbidden}` (the key lacks
  the `labor_claims` scope), `{:error, :bad_request}`, `{:error, :labor_claims_summary_error}`
  (anything else, including an answer that is not the documented one).

  ## Examples

      BluetabConnect.Tempo.Rest.labor_claims_summary(employee_id: 92)

      # The hours of every employee on every project in March 2026, by status
      BluetabConnect.Tempo.Rest.labor_claims_summary(
        date_from: ~D[2026-03-01],
        date_to: ~D[2026-03-31],
        group_by: [:employee_id, :project_id, :status]
      )
  """
  def labor_claims_summary(opts \\ []) do
    with {:ok, params} <- labor_claim_params(opts, :group_by),
         {:ok, %{"items" => items}} <-
           get_labor_claims(
             "/api/v1/labor-claims/summary",
             params,
             "items",
             :labor_claims_summary_error
           ) do
      {:ok, items}
    end
  end

  @doc """
  The first and the last date of the labor claims of Tempo (`GET /api/v1/labor-claims/date-range`).

  Takes the filters of `labor_claims_summary/1` (not `:group_by`). Requires an API key with the
  `labor_claims` scope.

  ## Returns

      {:ok, %{"min_date" => "2026-01-15", "max_date" => "2026-04-07"}}

  Both are `nil` when no claim matches.

  Errors are those of `labor_claims_summary/1`, with `{:error, :labor_claims_date_range_error}`
  for anything else.
  """
  def labor_claims_date_range(opts \\ []) do
    with {:ok, params} <- labor_claim_params(opts, nil),
         {:ok, range} <-
           get_labor_claims(
             "/api/v1/labor-claims/date-range",
             params,
             "min_date",
             :labor_claims_date_range_error
           ) do
      {:ok, Map.take(range, ["min_date", "max_date"])}
    end
  end

  # Tempo answers a summary as `{"items": [...]}`, and the doc allows the payload at the root or one
  # level under `data` (`data.attributes`), so all three are read. `key` is what the answer must hold.
  defp get_labor_claims(path, params, key, error) do
    base_req = get_client()

    # The labor claims routes are JSON:API routes: the doc asks for this media type
    case Req.get(base_req,
           url: path,
           params: params,
           headers: [{"accept", "application/vnd.api+json"}]
         ) do
      {:ok, %{status: 200, body: body}} ->
        case labor_claims_payload(body, key) do
          {:ok, payload} ->
            {:ok, payload}

          :error ->
            Logger.error("Unexpected answer reading labor claims (#{path}): #{inspect(body)}")
            {:error, error}
        end

      {:ok, %{status: status} = resp} when status in [400, 422] ->
        Logger.error("Bad request reading labor claims (#{path}): #{error_reason(resp)}")
        {:error, :bad_request}

      {:ok, %{status: 401} = resp} ->
        Logger.error("Unauthorized reading labor claims: #{error_reason(resp)}")
        {:error, :unauthorized}

      {:ok, %{status: 403} = resp} ->
        Logger.error(
          "Forbidden reading labor claims (API key needs the labor_claims scope): #{error_reason(resp)}"
        )

        {:error, :forbidden}

      err ->
        Logger.error("Error reading labor claims (#{path}): #{inspect(err)}")
        {:error, error}
    end
  end

  defp labor_claims_payload(body, key) when is_map(body) do
    data = body["data"]
    attributes = if is_map(data), do: data["attributes"]

    case Enum.find([body, data, attributes], &labor_claims_payload?(&1, key)) do
      nil -> :error
      payload -> {:ok, payload}
    end
  end

  defp labor_claims_payload(_body, _key), do: :error

  defp labor_claims_payload?(%{"items" => items}, "items"), do: is_list(items)
  defp labor_claims_payload?(%{} = map, key), do: Map.has_key?(map, key)
  defp labor_claims_payload?(_other, _key), do: false

  # Tempo ignores a date, a status or a grouping it cannot read, and answers for all the claims. The
  # options are checked here so that a typo is an error and not the hours of every day.
  defp labor_claim_params(opts, group_by_key) do
    with {:ok, dates} <- labor_claim_dates(opts),
         {:ok, status} <- labor_claim_status(Keyword.get(opts, :status)),
         {:ok, group_by} <- labor_claim_group_by(group_by_key && Keyword.get(opts, group_by_key)) do
      ids =
        opts
        |> Keyword.take(@labor_claim_id_filters)
        |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
        |> Enum.map(fn {k, v} -> {k, labor_claim_ids(v)} end)

      {:ok, ids ++ dates ++ status ++ group_by}
    else
      :error ->
        Logger.error("Invalid options reading labor claims: #{inspect(opts)}")
        {:error, :bad_request}
    end
  end

  defp labor_claim_ids(values) when is_list(values), do: Enum.map_join(values, ",", &to_string/1)
  defp labor_claim_ids(value), do: to_string(value)

  defp labor_claim_dates(opts) do
    Enum.reduce_while([:date_from, :date_to], {:ok, []}, fn key, {:ok, acc} ->
      case opts |> Keyword.get(key) |> labor_claim_date() do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, date} -> {:cont, {:ok, acc ++ [{key, date}]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp labor_claim_date(nil), do: {:ok, nil}
  defp labor_claim_date(%Date{} = date), do: {:ok, Date.to_iso8601(date)}

  defp labor_claim_date(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> labor_claim_date()

  defp labor_claim_date(%NaiveDateTime{} = naive),
    do: naive |> NaiveDateTime.to_date() |> labor_claim_date()

  defp labor_claim_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      {:error, _} -> :error
    end
  end

  defp labor_claim_date(_other), do: :error

  defp labor_claim_status(nil), do: {:ok, []}

  defp labor_claim_status(status) when is_atom(status) or is_binary(status) do
    if to_string(status) in @labor_claim_statuses,
      do: {:ok, [status: to_string(status)]},
      else: :error
  end

  defp labor_claim_status(_other), do: :error

  defp labor_claim_group_by(nil), do: {:ok, []}
  defp labor_claim_group_by([]), do: {:ok, []}

  defp labor_claim_group_by(fields) when is_list(fields) do
    names = Enum.map(fields, &to_string/1)

    if names != [] and Enum.all?(names, &(&1 in @labor_claim_groupings)),
      do: {:ok, [group_by: Enum.join(names, ",")]},
      else: :error
  end

  defp labor_claim_group_by(_other), do: :error

  defp format_query_value(%Date{} = date), do: Date.to_iso8601(date)

  defp format_query_value(%DateTime{} = datetime) do
    datetime |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp format_query_value(%NaiveDateTime{} = naive) do
    naive |> NaiveDateTime.to_date() |> Date.to_iso8601()
  end

  defp format_query_value(value), do: to_string(value)

  defp error_reason(%{body: %{"error" => reason}}), do: reason
  defp error_reason(%{body: body}), do: inspect(body)

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
