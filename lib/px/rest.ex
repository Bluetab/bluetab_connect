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

  def list_employees(criteria \\ []) do
    base_req = get_client()

    url =
      case criteria do
        [{:employee_number, number}] ->
          "/api/employees?employee_number=#{URI.encode_www_form(to_string(number))}"

        [{:email, email}] ->
          "/api/employees?email=#{URI.encode_www_form(email)}"

        _ ->
          "/api/employees"
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"employees" => employees}, status: 200}} ->
        {:ok, employees}

      err ->
        Logger.error("Error listing employees: #{inspect(err)}")
        {:error, :list_employees_error}
    end
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

  def list_hour_types do
    base_req = get_client()

    case Req.get(base_req, url: "/api/hour-types") do
      {:ok, %{body: %{"hour_types" => hour_types}, status: 200}} ->
        {:ok, hour_types}

      err ->
        Logger.error("Error listing hour types: #{inspect(err)}")
        {:error, :list_hour_types_error}
    end
  end

  def list_spend_types do
    base_req = get_client()

    case Req.get(base_req, url: "/api/spend-types") do
      {:ok, %{body: %{"spend_types" => spend_types}, status: 200}} ->
        {:ok, spend_types}

      err ->
        Logger.error("Error listing spend types: #{inspect(err)}")
        {:error, :list_spend_types_error}
    end
  end

  @project_filter_keys ~w(status sap_id doc_num start_date_from start_date_to end_date_from end_date_to client_id owner)a
  @project_pagination_keys ~w(page per_page)a

  @doc """
  Lists projects from the PX Projects API.

  ## Options

    * `:page` - Page number (default: 1)
    * `:per_page` - Items per page (default: 100)
    * `:status` - Filter by project status (e.g., "pst_Started", "pst_Closed")
    * `:sap_id` - Filter by project AbsEntry (SAP identifier)
    * `:doc_num` - Filter by project ID (DocNum from SAP)
    * `:start_date_from` - Filter projects with start date from (format: YYYY-MM-DD)
    * `:start_date_to` - Filter projects with start date to (format: YYYY-MM-DD)
    * `:end_date_from` - Filter projects with end date from (format: YYYY-MM-DD)
    * `:end_date_to` - Filter projects with end date to (format: YYYY-MM-DD)
    * `:client_id` - Filter by client ID
    * `:owner` - Filter by owner employee number
    * `:fields` - List of additional fields to include (e.g., `[:client_id, :owner_name]`)

  ## Examples

      # Basic request - returns all projects with default pagination
      BluetabConnect.Px.Rest.list_projects()

      # With pagination and filters
      BluetabConnect.Px.Rest.list_projects(page: 1, per_page: 20, status: "pst_Started")

      # With field selection
      BluetabConnect.Px.Rest.list_projects(fields: [:client_id, :owner_name, :financial_project])

  ## Returns

      {:ok, %{"projects" => [...], "pagination" => %{...}}}
  """
  def list_projects(opts \\ []) do
    base_req = get_client()

    query_params =
      opts
      |> Keyword.take(@project_pagination_keys ++ @project_filter_keys)
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    query_params =
      case Keyword.get(opts, :fields) do
        nil ->
          query_params

        fields when is_list(fields) ->
          fields_str = fields |> Enum.map_join(",", &to_string/1)
          [{"fields", fields_str} | query_params]

        fields when is_binary(fields) ->
          [{"fields", fields} | query_params]
      end

    url =
      case query_params do
        [] -> "/api/projects"
        params -> "/api/projects?" <> URI.encode_query(params)
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"projects" => projects, "pagination" => pagination}, status: 200}} ->
        {:ok, %{"projects" => projects, "pagination" => pagination}}

      {:ok, %{body: %{"error" => reason}, status: 401}} ->
        Logger.error("Unauthorized listing projects: #{reason}")
        {:error, :unauthorized}

      err ->
        Logger.error("Error listing projects: #{inspect(err)}")
        {:error, :list_projects_error}
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
