defmodule BluetabConnect.Sap.Soap do
  @moduledoc """
  SAP SOAP Client wrapper
  """

  use GenServer
  require Logger

  alias BluetabConnect.Sap.Soap.TokenDispenser

  @doc """
  Starts the SOAP GenServer.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Gets the current token from the SAP state.
  """
  def get_wsdl(endpoint) do
    GenServer.call(__MODULE__, {:get_wsdl, endpoint})
  end

  @spec call(any(), any(), any()) :: {:error, any()} | {:ok, map()}
  def call(endpoint, action, params \\ %{}) do
    with {:ok, wsdl, token, http_opts} <- get_wsdl(endpoint),
         {:ok, response} <-
           Soap.call(
             wsdl,
             action,
             %{"request" => Map.put(params, "AuthenticationToken", token)},
             [],
             http_opts
           ) do
      {:ok, Soap.Response.parse(response)}
    else
      {:error, _} = error ->
        error

      error ->
        Logger.error("SAP -> Error calling #{endpoint}: #{inspect(error)}")
        {:error, error}
    end
  end

  @impl true
  def init(config) do
    {:ok, %{config: config, token: nil, wsdls: %{}}}
  end

  # GenServer Callbacks
  @impl true
  def handle_call({:get_wsdl, endpoint}, _from, state) do
    timeout = state |> Map.get(:config) |> Keyword.get(:timeout, 30_000)
    http_opts = [timeout: timeout, recv_timeout: timeout]

    with {:ok, token, %{config: config, wsdls: wsdls} = state} <- get_token(state) do
      case Map.get(wsdls, endpoint) do
        nil ->
          {:ok, wsdl} = init_wsdl(config, endpoint)
          wsdls = Map.put(wsdls, endpoint, wsdl)
          {:reply, {:ok, wsdl, token, http_opts}, Map.put(state, :wsdls, wsdls)}

        wsdl ->
          {:reply, {:ok, wsdl, token, http_opts}, state}
      end
    else
      {:error, state} ->
        {:reply, :error, state}
    end
  end

  defp get_token(%{config: config, token: nil} = state) do
    with {:ok, token} <- TokenDispenser.get_token(config) do
      {:ok, token, Map.put(state, :token, token)}
    else
      error ->
        Logger.error("SAP initialization failed: #{inspect(error)}")
        {:error, state}
    end
  end

  defp get_token(%{token: token} = state), do: {:ok, token, state}

  defp init_wsdl(config, endpoint) do
    soap_url = Keyword.fetch!(config, :soap_url)
    wsdl_url = "#{soap_url}/#{endpoint}?WSDL"
    Soap.init_model(wsdl_url, :url)
  end
end
