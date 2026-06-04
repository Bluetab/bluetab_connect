defmodule BluetabConnect.Sap.SuccessFactors do
  @moduledoc """
  SuccessFactors OData v2 client.
  """

  use GenServer

  @timeout 30_000
  @expand "employmentNav,employmentNav/jobInfoNav,employmentNav/userNav,personalInfoNav,userAccountNav"
  @select "personIdExternal,employmentNav/assignmentClass,employmentNav/endDate,employmentNav/jobInfoNav/company,employmentNav/jobInfoNav/customString6,employmentNav/jobInfoNav/customString7,employmentNav/originalStartDate,employmentNav/startDate,employmentNav/userNav/email,personalInfoNav/firstName,personalInfoNav/lastName,personalInfoNav/secondLastName,personalInfoNav/customString2,userAccountNav/email"
  @holiday_expand "holidayAssignments,holidayAssignments/holidayNav"

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def list_employees(params \\ %{}) do
    GenServer.call(__MODULE__, {:employees, params}, @timeout)
  end

  def list_picklist(params) do
    GenServer.call(__MODULE__, {:picklist, params}, @timeout)
  end

  def categories do
    list_picklist(id: "ESP_CATEGORIA")
  end

  def careers do
    list_picklist(id: "ESP_CARRERA")
  end

  def list_holiday_calendars(params \\ %{}) do
    GenServer.call(__MODULE__, {:holiday_calendars, params}, @timeout)
  end

  @impl true
  def init(config) do
    base_url = Keyword.fetch!(config, :base_url)
    username = Keyword.fetch!(config, :username)
    password = Keyword.fetch!(config, :password)

    client =
      Req.new(
        base_url: base_url,
        auth: {:basic, "#{username}:#{password}"},
        headers: [{"accept", "application/json"}]
      )

    {:ok, %{client: client}}
  end

  @impl true
  def handle_call({:employees, params}, _from, %{client: client} = state) do
    filter = employee_filter(params)

    reply =
      odata(client, "/odata/v2/PerPerson",
        filter: filter,
        expand: @expand,
        select: @select
      )

    {:reply, reply, state}
  rescue
    e -> {:reply, error(e), state}
  end

  @impl true
  def handle_call({:picklist, params}, _from, %{client: client} = state) do
    filter = picklist_filter(params)

    reply =
      odata(client, "/odata/v2/PicklistLabel",
        filter: filter,
        expand: "picklistOption/picklist",
        select: "label,optionId"
      )

    {:reply, reply, state}
  rescue
    e -> {:reply, error(e), state}
  end

  def handle_call({:holiday_calendars, params}, _from, %{client: client} = state) do
    reply =
      case odata(client, "/odata/v2/HolidayCalendar", holiday_calendar_opts(params)) do
        {:ok, results} -> {:ok, parse_holiday_calendars(results)}
        error -> error
      end

    {:reply, reply, state}
  rescue
    e -> {:reply, error(e), state}
  end

  defp employee_filter(params) do
    params
    |> Map.new()
    |> Map.put_new(:company, "ESP_0001")
    |> Enum.flat_map(fn
      {:company, value} -> ["employmentNav/jobInfoNav/company eq '#{value}'"]
      _ -> []
    end)
    |> Enum.join(" and ")
  end

  defp picklist_filter(params) do
    params
    |> Map.new()
    |> Map.put_new(:locale, "es_ES")
    |> Enum.flat_map(fn
      {:id, value} -> ["picklistOption/picklist/picklistId eq '#{value}'"]
      {:locale, value} -> ["locale eq '#{value}'"]
      _ -> []
    end)
    |> Enum.join(" and ")
  end

  defp holiday_calendar_opts(params) do
    params = Map.new(params)

    [
      expand: @holiday_expand,
      top: Map.get(params, :top),
      skip: Map.get(params, :skip)
    ]
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
  end

  defp parse_holiday_calendars(calendars) when is_list(calendars) do
    Enum.map(calendars, &parse_holiday_calendar/1)
  end

  defp parse_holiday_calendar(calendar) do
    %{
      code: calendar["externalCode"],
      class: calendar["holidayClass"],
      holidays: parse_holiday_assignments(calendar["holidayAssignments"])
    }
  end

  defp parse_holiday_assignments(%{"results" => assignments}) when is_list(assignments) do
    Enum.map(assignments, &parse_holiday_assignment/1)
  end

  defp parse_holiday_assignments(_), do: []

  defp parse_holiday_assignment(assignment) do
    %{
      date: parse_odata_date(assignment["date"]),
      holiday_code: assignment["holiday"],
      name: get_in(assignment, ["holidayNav", "name_defaultValue"])
    }
  end

  defp parse_odata_date("/Date(" <> rest) do
    ms =
      rest
      |> String.split([")", "+"], parts: 2)
      |> hd()
      |> String.to_integer()

    ms
    |> div(1000)
    |> DateTime.from_unix!()
    |> DateTime.to_date()
  end

  defp parse_odata_date(value) when is_binary(value) do
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      _ -> value
    end
  end

  defp parse_odata_date(%Date{} = date), do: date
  defp parse_odata_date(nil), do: nil
  defp parse_odata_date(value), do: value

  defp error(%CaseClauseError{term: {:error, e}}) do
    message = if is_exception(e), do: Exception.message(e), else: e
    {:error, message}
  end

  defp error(e) do
    message = if is_exception(e), do: Exception.message(e), else: e
    {:error, message}
  end

  defp odata(client, resource, opts) do
    url = resource <> "?" <> query(opts)
    odata_pages(client, url, headers(opts))
  end

  defp odata_pages(client, url, headers) do
    with {:ok, %{body: %{"d" => data}}} <- Req.get(client, url: url, headers: headers) do
      case data do
        %{"__next" => next_url, "results" => results} ->
          {:ok, next_results} = odata_pages(client, next_url, headers)
          {:ok, results ++ next_results}

        %{"results" => results} ->
          {:ok, results}

        res ->
          {:ok, res}
      end
    end
  end

  defp query(opts) do
    opts
    |> Enum.reject(fn {_, v} -> v == "" end)
    |> Enum.reduce(%{}, fn
      {:apply, apply}, acc -> Map.put(acc, "$apply", apply)
      {:expand, expand}, acc -> Map.put(acc, "$expand", expand)
      {:filter, filter}, acc -> Map.put(acc, "$filter", filter)
      {:select, select}, acc -> Map.put(acc, "$select", select)
      {:orderby, orderby}, acc -> Map.put(acc, "$orderby", orderby)
      {:top, top}, acc -> Map.put(acc, "$top", top)
      {:skip, skip}, acc -> Map.put(acc, "$skip", skip)
      {:count, count}, acc -> Map.put(acc, "$count", count)
      {:inlinecount, inlinecount}, acc -> Map.put(acc, "$inlinecount", inlinecount)
      _, acc -> acc
    end)
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> URI.encode_query()
    |> String.replace("+", "%20")
  end

  defp headers(opts) do
    Enum.reduce(opts, [], fn
      {:accept, accept}, acc -> [{"accept", accept} | acc]
      {:size, size}, acc -> [{"prefer", "odata.maxpagesize=#{size}"} | acc]
      {:case_insensitive, true}, acc -> [{"B1S-CaseInsensitive", "true"} | acc]
      _, acc -> acc
    end)
  end
end
