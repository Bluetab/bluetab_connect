defmodule BluetabConnect.Sap.Odata do
  @moduledoc """
  SAP SOAP Client wrapper
  """

  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_client do
    GenServer.call(__MODULE__, :get_client)
  end

  def list_employees(params \\ %{}, opts \\ []) do
    base_req = get_client()
    filter = employee_filter(params)
    select = Keyword.get(opts, :select, "EmployeeID,eMail")
    size = Keyword.get(opts, :size, 10_000)

    odata(base_req, "/b1s/v2/EmployeesInfo",
      size: size,
      filter: filter,
      select: select
    )
  end

  def list_projects(params \\ %{}, opts \\ []) do
    base_req = get_client()
    filter = project_filter(params)

    select =
      Keyword.get(
        opts,
        :select,
        "AbsEntry,ProjectName,StartDate,ClosingDate,DocNum,BusinessPartner,BusinessPartnerName,ProjectStatus,FinancialProject,Reason"
      )

    size = Keyword.get(opts, :size, 10_000)

    odata(base_req, "/b1s/v2/ProjectManagements",
      size: size,
      filter: filter,
      select: select
    )
  end

  def list_assignments(params \\ %{}, opts \\ []) do
    base_req = get_client()
    filter = assignment_filter(params)

    select =
      Keyword.get(
        opts,
        :select,
        "DocNum,EmployeeNumber,ImputacionYear,ImputacionMonth,PlannedQuantity,PostedQuantity"
      )

    size = Keyword.get(opts, :size, 10_000)

    odata(base_req, "/b1s/v2/sml.svc/SCLPRJBIANLHORASQUERY",
      size: size,
      filter: filter,
      select: select
    )
  end

  defp employee_filter(params) do
    params
    |> Map.new()
    |> Map.put_new(:recent, true)
    |> Enum.flat_map(fn
      {:recent, false} ->
        []

      {:recent, true} ->
        cutoff = Date.utc_today() |> Date.add(-180) |> Date.to_iso8601()
        ["(TerminationDate eq null or TerminationDate ge '#{cutoff}')"]

      {:active, true} ->
        ["Active ne 'tNO'"]

      {:relation_type, relation_type} ->
        ["U_SCL_TIPORELACION eq '#{relation_type}'"]

      {:id, id} ->
        ["EmployeeID eq #{id}"]

      {:email, email} ->
        ["eMail eq '#{email}'"]

      {:employee_ids, ids} ->
        clause = Enum.map_join(ids, " or ", &"EmployeeID eq #{&1}")

        ["(#{clause})"]
    end)
    |> Enum.join(" and ")
  end

  defp assignment_filter(params) do
    params
    |> Enum.reduce(["IsGeneral ne 'Y'"], fn
      {:since, since}, acc ->
        ["ImputacionDate ge '#{since}'" | acc]

      {:until, until}, acc ->
        ["ImputacionDate lt '#{until}'" | acc]

      {:employee_id, employee_id}, acc ->
        ["EmployeeNumber eq #{employee_id}" | acc]

      {:id, id}, acc ->
        ["DocNum eq #{id}" | acc]

      {:project_ids, ids}, acc ->
        clause = Enum.map_join(ids, " or ", &"DocNum eq #{&1}")

        ["(#{clause})" | acc]

      {:initiative, _}, acc ->
        acc
    end)
    |> Enum.join(" and ")
  end

  defp project_filter(params) do
    params
    |> Enum.flat_map(fn
      {:initiative, initiative_code} -> ["contains(Reason, '#{initiative_code}')"]
      _ -> []
    end)
    |> Enum.join(" and ")
  end

  defp odata(base_req, resource, opts) do
    url = resource <> "?" <> query(opts)

    odata_pages(base_req, url, headers(opts))
  end

  defp odata_pages(base_req, url, headers) do
    with {:ok, %{body: body}} <- Req.get(base_req, url: url, headers: headers) do
      case body do
        %{"@odata.nextLink" => next_url, "value" => value} ->
          {:ok, next_value} = odata_pages(base_req, next_url, headers)
          {:ok, value ++ next_value}

        %{"value" => value} ->
          {:ok, value}
      end
    end
  end

  defp headers(opts) do
    Enum.reduce(opts, [], fn
      {:size, size}, acc -> [{"prefer", "odata.maxpagesize=#{size}"} | acc]
      {:case_insensitive, true}, acc -> [{"B1S-CaseInsensitive", "true"} | acc]
      _, acc -> acc
    end)
  end

  defp query(opts) do
    opts
    |> Enum.reject(fn {_, v} -> v == "" end)
    |> Enum.reduce(%{}, fn
      {:apply, apply}, acc -> Map.put(acc, "$apply", apply)
      {:filter, filter}, acc -> Map.put(acc, "$filter", filter)
      {:select, select}, acc -> Map.put(acc, "$select", select)
      {:orderby, orderby}, acc -> Map.put(acc, "$orderby", orderby)
      {:top, top}, acc -> Map.put(acc, "$top", top)
      {:skip, skip}, acc -> Map.put(acc, "$skip", skip)
      {:count, count}, acc -> Map.put(acc, "$count", count)
      {:inlinecount, inlinecount}, acc -> Map.put(acc, "$inlinecount", inlinecount)
      _, acc -> acc
    end)
    |> URI.encode_query()
    |> String.replace("+", "%20")
  end

  @impl true
  def init(config) do
    base_url = Keyword.fetch!(config, :base_url)
    database = Keyword.fetch!(config, :database)
    username = Keyword.fetch!(config, :username)
    password = Keyword.fetch!(config, :password)

    username = Jason.encode!(%{"CompanyDB" => database, "UserName" => username})

    transport_opts = [
      ciphers: :ssl.cipher_suites(:all, :tlsv1),
      verify: :verify_peer,
      versions: [:tlsv1]
    ]

    cred = "#{username}:#{password}"

    client =
      Req.new(
        base_url: base_url,
        auth: {:basic, cred},
        connect_options: [transport_opts: transport_opts]
      )

    {:ok, %{client: client}}
  end

  def handle_call(:get_client, _from, %{client: client} = state) do
    {:reply, client, state}
  end
end
