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

  @employee_filter_keys ~w(employee_number email)a

  @doc """
  Lists employees from the PX Employees API.

  Organizational hierarchy is available via the Positions API, not on employee
  records. Requires a service account, admin, or business operations access.

  ## Options

    * `:employee_number` - Filter by employee number (SAP employee number)
    * `:email` - Filter by email address

  If no options are provided, returns all employees.

  ## Returns

      {:ok, %{"employees" => [...], "total" => count}}

  Each employee map includes: `sap_employee_number`, `email`, `full_name`,
  `first_name`, `last_name`, `ssff_id`, `category`, `category_name`,
  `weekly_hours`, `hub`, `is_active`, `start_date`, `termination_date`.

  ## Examples

      BluetabConnect.Px.Rest.list_employees()
      BluetabConnect.Px.Rest.list_employees(employee_number: 10001)
      BluetabConnect.Px.Rest.list_employees(email: "john@example.com")
  """
  def list_employees(opts \\ []) do
    base_req = get_client()

    query_params =
      opts
      |> Keyword.take(@employee_filter_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {to_string(k), format_employee_query_value(v)} end)

    url =
      case query_params do
        [] -> "/api/employees"
        params -> "/api/employees?" <> URI.encode_query(params)
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"employees" => employees, "total" => total}, status: 200}} ->
        {:ok, %{"employees" => employees, "total" => total}}

      {:ok, %{body: %{"error" => reason}, status: 401}} ->
        Logger.error("Unauthorized listing employees: #{reason}")
        {:error, :unauthorized}

      err ->
        Logger.error("Error listing employees: #{inspect(err)}")
        {:error, :list_employees_error}
    end
  end

  defp format_employee_query_value(value) when is_integer(value), do: to_string(value)
  defp format_employee_query_value(value), do: to_string(value)

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

  @position_filter_keys ~w(position_id employee_number is_active is_default)a

  @doc """
  Lists positions from the PX Positions API.

  Returns organizational positions, current reporting relationships, and assigned
  employees. Requires a service account.

  ## Options

    * `:position_id` - Filter by position ID
    * `:employee_number` - Positions assigned to or default for this employee
    * `:is_active` - Filter by active status
    * `:is_default` - Filter default vs non-default positions

  ## Returns

      {:ok, %{
        "positions" => [...],
        "relationships" => [...],
        "total_positions" => count,
        "total_relationships" => count
      }}

  ## Examples

      BluetabConnect.Px.Rest.list_positions()
      BluetabConnect.Px.Rest.list_positions(employee_number: 10001, is_active: true)
  """
  def list_positions(opts \\ []) do
    base_req = get_client()

    query_params =
      opts
      |> Keyword.take(@position_filter_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {to_string(k), format_position_query_value(v)} end)

    url =
      case query_params do
        [] -> "/api/positions"
        params -> "/api/positions?" <> URI.encode_query(params)
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"positions" => _} = body, status: 200}} ->
        {:ok, body}

      {:ok, %{body: %{"error" => reason}, status: 401}} ->
        Logger.error("Unauthorized listing positions: #{reason}")
        {:error, :unauthorized}

      err ->
        Logger.error("Error listing positions: #{inspect(err)}")
        {:error, :list_positions_error}
    end
  end

  @doc """
  Gets a position by ID from the PX Positions API.

  Requires a service account.

  ## Examples

      BluetabConnect.Px.Rest.get_position(10)
  """
  def get_position(id) do
    base_req = get_client()
    id_str = to_string(id)

    case Req.get(base_req, url: "/api/positions/#{id_str}") do
      {:ok, %{body: body, status: 200}} ->
        {:ok, body}

      {:ok, %{body: %{"error" => reason}, status: 401}} ->
        Logger.error("Unauthorized getting position: #{reason}")
        {:error, :unauthorized}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      err ->
        Logger.error("Error getting position #{id_str}: #{inspect(err)}")
        {:error, :get_position_error}
    end
  end

  defp format_position_query_value(value) when is_boolean(value), do: to_string(value)
  defp format_position_query_value(value), do: to_string(value)

  @project_filter_keys ~w(status sap_id doc_num start_date_from start_date_to end_date_from end_date_to client_id owner)a
  @project_pagination_keys ~w(page per_page)a
  @project_passthrough_option_key :query

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
    * `:fields` - Additional fields to include as a list or comma-separated string
      (e.g., `[:client_id, :owner_name, :financial_project, :reason]`)
    * `:query` - Keyword list or map with extra API query params not explicitly listed
      (useful to expose new server-side filters without changing this client)

  ## Examples

      # Basic request - returns all projects with default pagination
      BluetabConnect.Px.Rest.list_projects()

      # With pagination and filters
      BluetabConnect.Px.Rest.list_projects(page: 1, per_page: 20, status: "pst_Started")

      # With field selection
      BluetabConnect.Px.Rest.list_projects(fields: [:client_id, :owner_name, :financial_project])

      # Pass through additional query params supported by the API
      BluetabConnect.Px.Rest.list_projects(
        page: 1,
        per_page: 50,
        query: [some_new_filter: "value", include_flags: true]
      )

  ## Returns

      {:ok, %{"projects" => [...], "pagination" => %{...}}}
  """
  def list_projects(opts \\ []) do
    base_req = get_client()

    query_params = build_project_query_params(opts)

    url =
      case query_params do
        [] -> "/api/projects"
        params -> "/api/projects?" <> URI.encode_query(params)
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"projects" => _projects} = body, status: 200}} ->
        {:ok, body}

      {:ok, %{body: %{"error" => reason}, status: 401}} ->
        Logger.error("Unauthorized listing projects: #{reason}")
        {:error, :unauthorized}

      err ->
        Logger.error("Error listing projects: #{inspect(err)}")
        {:error, :list_projects_error}
    end
  end

  defp build_project_query_params(opts) do
    opts = normalize_project_opts(opts)

    base_params =
      opts
      |> Keyword.take(@project_pagination_keys ++ @project_filter_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Map.new()

    passthrough_params =
      opts
      |> Keyword.get(@project_passthrough_option_key, [])
      |> normalize_query_params()
      |> Map.new()

    params =
      base_params
      |> Map.merge(passthrough_params)
      |> maybe_put_fields_param(Keyword.get(opts, :fields))

    Map.to_list(params)
  end

  defp normalize_project_opts(opts) when is_list(opts), do: opts
  defp normalize_project_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_project_opts(_opts), do: []

  defp normalize_query_params(params) when is_list(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_query_params(params) when is_map(params) do
    params
    |> Map.to_list()
    |> normalize_query_params()
  end

  defp normalize_query_params(_params), do: []

  defp maybe_put_fields_param(params, nil), do: params

  defp maybe_put_fields_param(params, fields) when is_list(fields) do
    fields_str =
      fields
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(",")

    if fields_str == "" do
      params
    else
      Map.put(params, "fields", fields_str)
    end
  end

  defp maybe_put_fields_param(params, fields) when is_binary(fields) do
    case String.trim(fields) do
      "" -> params
      trimmed -> Map.put(params, "fields", trimmed)
    end
  end

  defp maybe_put_fields_param(params, _fields), do: params

  @doc """
  Lists month end close records from the PX Month End Close API.

  Requires a service account, admin, or business operations access.

  ## Options

    * `:year` - Filter by year
    * `:month` - Filter by month (1-12)

  ## Returns

      {:ok, %{"month_end_close" => [...], "total" => count}}

  ## Examples

      BluetabConnect.Px.Rest.list_month_end_close()
      BluetabConnect.Px.Rest.list_month_end_close(year: 2025, month: 3)
  """
  def list_month_end_close(opts \\ []) do
    base_req = get_client()

    query_params =
      opts
      |> Keyword.take([:year, :month])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    url =
      case query_params do
        [] -> "/api/month-end-close"
        params -> "/api/month-end-close?" <> URI.encode_query(params)
      end

    case Req.get(base_req, url: url) do
      {:ok, %{body: %{"month_end_close" => records, "total" => total}, status: 200}} ->
        {:ok, %{"month_end_close" => records, "total" => total}}

      {:ok, %{body: %{"error" => reason}, status: 401}} ->
        Logger.error("Unauthorized listing month end close: #{reason}")
        {:error, :unauthorized}

      err ->
        Logger.error("Error listing month end close: #{inspect(err)}")
        {:error, :list_month_end_close_error}
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
