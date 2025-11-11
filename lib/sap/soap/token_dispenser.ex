defmodule BluetabConnect.Sap.Soap.TokenDispenser do
  @moduledoc """
  TokenDispenser SOAP client module for handling token dispensing.
  """
  require Logger

  @doc """
  Gets a token for SOAP requests
  """
  def get_token(config) do
    soap_url = Keyword.fetch!(config, :soap_url)
    connection_id = Keyword.fetch!(config, :connection_id)
    username = Keyword.fetch!(config, :username)
    password = Keyword.fetch!(config, :password)

    wsdl_url = "#{soap_url}/TokenDispenser.asmx?WSDL"

    with {:ok, wsdl} <- Soap.init_model(wsdl_url, :url),
         params = %{
           "UserName" => username,
           "Password" => password,
           "ConnectionID" => connection_id
         },
         {:ok, response} <- Soap.call(wsdl, "GetToken", params),
         {:response,
          %{
            GetTokenResponse: %{
              GetTokenResult: %{LoginSuccess: "true", LoginFailureReason: %{}, TokenString: token}
            }
          }}
         when is_binary(token) <- {:response, Soap.Response.parse(response)} do
      {:ok, token}
    else
      {:response, response} ->
        Logger.error("Unexpected token response format: #{inspect(response)}")
        {:error, :invalid_token_response}

      error ->
        Logger.error("Error fetching token: #{inspect(error)}")
        error
    end
  end
end
