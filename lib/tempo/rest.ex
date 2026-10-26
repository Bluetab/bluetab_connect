defmodule BluetabConnect.Tempo.Rest do
  @moduledoc """
  Tempo REST Client

  Connects to the Tempo app API using an API key (Bearer token). Tempo API keys
  are scoped: the key must carry the scope of the endpoint it calls (`holidays`
  for `list_holidays/1`), otherwise Tempo answers `403`.

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
