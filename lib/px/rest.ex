defmodule BluetabConnect.Px.Rest do
  @moduledoc """
  PX REST Client
  """

  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_client do
    GenServer.call(__MODULE__, :get_client)
  end

  def list_initiatives do
    base_req = get_client()

    case Req.get(base_req, url: "/api/initiatives") do
      {:ok, %{body: %{"initiatives" => initiatives}, status: 200}} ->
        {:ok, initiatives}

      err ->
        Logger.error("Error listing initiatives: #{inspect(err)}")
        {:error, :list_initiatives_error}
    end
  end

  def list_clients do
    base_req = get_client()

    case Req.get(base_req, url: "/api/clients") do
      {:ok, %{body: %{"clients" => clients}, status: 200}} ->
        {:ok, clients}

      err ->
        Logger.error("Error listing clients: #{inspect(err)}")
        {:error, :list_clients_error}
    end
  end

  def list_client_groups do
    base_req = get_client()

    case Req.get(base_req, url: "/api/client-groups") do
      {:ok, %{body: %{"client_groups" => client_groups}, status: 200}} ->
        {:ok, client_groups}

      err ->
        Logger.error("Error listing client groups: #{inspect(err)}")
        {:error, :list_client_groups_error}
    end
  end

  def list_clusters do
    base_req = get_client()

    case Req.get(base_req, url: "/api/clusters") do
      {:ok, %{body: %{"clusters" => clusters}, status: 200}} ->
        {:ok, clusters}

      err ->
        Logger.error("Error listing clusters: #{inspect(err)}")
        {:error, :list_clusters_error}
    end
  end

  def list_business_units do
    base_req = get_client()

    case Req.get(base_req, url: "/api/business-units") do
      {:ok, %{body: %{"business_units" => business_units}, status: 200}} ->
        {:ok, business_units}

      err ->
        Logger.error("Error listing business units: #{inspect(err)}")
        {:error, :list_business_units_error}
    end
  end

  @impl true
  def init(config) do
    base_url = Keyword.fetch!(config, :base_url)
    token = Keyword.fetch!(config, :bearer_token)

    client =
      Req.new(
        base_url: base_url,
        auth: {:bearer, token}
      )

    {:ok, %{client: client}}
  end

  @impl true
  def handle_call(:get_client, _from, %{client: client} = state) do
    {:reply, client, state}
  end
end

"""
config = [
base_url: "https://px.app.bluetab.net",
bearer_token: "6u4Ie9TLHUEr0oFINekTEppI4gtWvr5YA4SnMQocteo"
]
"""
