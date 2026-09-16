defmodule BluetabConnect.Spend.Rest do
  @moduledoc """
  Spend REST Client

  Connects to the Spend app API using an API key (Bearer token).
  """

  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_client do
    GenServer.call(__MODULE__, :get_client)
  end

  @per_diem_filter_keys ~w(from to)a

  @doc """
  Lists employee per-diems (Dieta gastos) from the Spend API.

  ## Options

    * `:from` - Include items with `start_date >= from` (`YYYY-MM-DD` or `Date`)
    * `:to` - Include items with `start_date <= to` (`YYYY-MM-DD` or `Date`)

  If no options are provided, returns all per-diems.

  ## Returns

      {:ok, [%{"email" => ..., "start_date" => ..., "duration_days" => ..., "status" => ...}, ...]}

  Each item includes: `email`, `start_date`, `duration_days`, and `status`
  (parent liquidación SAP estado, e.g. `"Imputada"`, `"Pagada"`).

  ## Examples

      BluetabConnect.Spend.Rest.list_employee_per_diems()
      BluetabConnect.Spend.Rest.list_employee_per_diems(from: ~D[2026-09-01])
      BluetabConnect.Spend.Rest.list_employee_per_diems(
        from: ~D[2026-09-01],
        to: ~D[2026-09-30]
      )
  """
  def list_employee_per_diems(opts \\ []) do
    base_req = get_client()

    query_params =
      opts
      |> Keyword.take(@per_diem_filter_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {to_string(k), format_date_query_value(v)} end)

    url =
      case query_params do
        [] -> "/api/v1/employee-per-diems"
        params -> "/api/v1/employee-per-diems?" <> URI.encode_query(params)
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"items" => items}, status: 200}} when is_list(items) ->
        {:ok, items}

      {:ok, %{status: 401} = resp} ->
        reason = get_in(resp.body, ["error"]) || inspect(resp.body)
        Logger.error("Unauthorized listing employee per-diems: #{reason}")
        {:error, :unauthorized}

      err ->
        Logger.error("Error listing employee per-diems: #{inspect(err)}")
        {:error, :list_employee_per_diems_error}
    end
  end

  defp format_date_query_value(%Date{} = date), do: Date.to_iso8601(date)

  defp format_date_query_value(%DateTime{} = datetime) do
    datetime |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp format_date_query_value(%NaiveDateTime{} = naive) do
    naive |> NaiveDateTime.to_date() |> Date.to_iso8601()
  end

  defp format_date_query_value(value), do: to_string(value)

  @impl true
  def init(config) do
    base_url = Keyword.fetch!(config, :base_url)
    api_key = Keyword.fetch!(config, :api_key)

    client =
      Req.new(
        base_url: base_url,
        auth: {:bearer, api_key},
        headers: [
          {"accept", "application/vnd.api+json"},
          {"content-type", "application/vnd.api+json"}
        ]
      )

    {:ok, %{client: client}}
  end

  @impl true
  def handle_call(:get_client, _from, %{client: client} = state) do
    {:reply, client, state}
  end
end
