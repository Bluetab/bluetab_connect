if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BluetabConnect.Install do
    @shortdoc "Installs BluetabConnect connectors (px_rest, sap_soap, sap_odata)"

    @moduledoc """
    Installs one or more BluetabConnect connectors into a Phoenix application.

    Adds runtime configuration and Application supervision tree entries for each
    selected connector.

    ## Available connectors

    - `px_rest` - PX REST API client (`BluetabConnect.Px.Rest`)
    - `sap_soap` - SAP SOAP client (`BluetabConnect.Sap.Soap`)
    - `sap_odata` - SAP OData client (`BluetabConnect.Sap.Odata`)

    ## Usage

        mix bluetab_connect.install px_rest sap_soap sap_odata

    ## What this installer does

    For each selected connector:

    1. Adds runtime configuration to `config/runtime.exs` (inside a `config_env() != :test` guard)
    2. Adds the connector as a conditionally-supervised child in the Application module
    3. Adds a `maybe_child/2` helper to the Application module (if not already present)

    ## Environment Variables

    ### px_rest

    - `PX_API_URL` - PX API base URL
    - `PX_TOKEN` - PX API bearer token

    ### sap_soap

    - `SOAP_CONNECTION_ID` - SAP SOAP connection ID
    - `SOAP_USERNAME` - SAP SOAP username
    - `SOAP_PASSWORD` - SAP SOAP password
    - `SOAP_URL` - SAP SOAP base URL
    - `SOAP_VERIFY_SSL` - Enable SSL verification (default: "true")

    ### sap_odata

    - `ODATA_BASE_URL` - SAP OData base URL
    - `ODATA_DATABASE` - SAP CompanyDB name
    - `ODATA_USERNAME` - SAP OData username
    - `ODATA_PASSWORD` - SAP OData password
    """

    use Igniter.Mix.Task

    @valid_connectors ~w(px_rest sap_soap sap_odata)

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :bluetab_connect,
        example: "mix bluetab_connect.install px_rest sap_soap sap_odata"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      connectors = igniter.args.argv
      invalid = connectors -- @valid_connectors

      cond do
        connectors == [] ->
          Igniter.add_issue(
            igniter,
            """
            No connectors specified.

            Pass one or more of: #{Enum.join(@valid_connectors, ", ")}

            Example: mix bluetab_connect.install px_rest sap_soap
            """
          )

        invalid != [] ->
          Igniter.add_issue(
            igniter,
            """
            Unknown connectors: #{Enum.join(invalid, ", ")}

            Valid connectors are: #{Enum.join(@valid_connectors, ", ")}
            """
          )

        true ->
          app_name = Igniter.Project.Application.app_name(igniter)

          igniter
          |> add_runtime_configs(connectors, app_name)
          |> add_soap_globals_config(connectors)
          |> add_application_children(connectors, app_name)
          |> add_install_notice(connectors)
      end
    end

    # ──────────────────────────────────────────────
    # Runtime Config
    # ──────────────────────────────────────────────

    defp add_runtime_configs(igniter, connectors, app_name) do
      Igniter.update_file(igniter, "config/runtime.exs", fn source ->
        content = Rewrite.Source.get(source, :content)

        configs_to_add =
          connectors
          |> Enum.reject(&runtime_config_exists?(content, &1, app_name))
          |> Enum.map(&runtime_config_block(&1, app_name))

        if configs_to_add == [] do
          source
        else
          config_code = Enum.join(configs_to_add, "\n\n")
          content = insert_runtime_config(content, config_code)
          Rewrite.Source.update(source, :content, content)
        end
      end)
    end

    defp add_soap_globals_config(igniter, connectors) do
      if "sap_soap" in connectors do
        Igniter.update_file(igniter, "config/config.exs", fn source ->
          content = Rewrite.Source.get(source, :content)

          if soap_globals_config_exists?(content) do
            source
          else
            content =
              String.trim_trailing(content) <>
                "\n\nconfig :soap, :globals, version: \"1.1\"\n"

            Rewrite.Source.update(source, :content, content)
          end
        end)
      else
        igniter
      end
    end

    defp soap_globals_config_exists?(content) do
      Regex.match?(~r/config\s+:soap,\s+:globals,\s*version:\s*"1\.1"/, content)
    end

    defp runtime_config_exists?(content, connector, app_name) do
      key = config_key(connector)
      String.contains?(content, "config :#{app_name}, :#{key}")
    end

    defp config_key("px_rest"), do: "px"
    defp config_key("sap_soap"), do: "soap"
    defp config_key("sap_odata"), do: "odata"

    defp runtime_config_block("px_rest", app_name) do
      String.trim_trailing("""
        config :#{app_name}, :px,
          base_url: System.fetch_env!("PX_API_URL"),
          bearer_token: System.fetch_env!("PX_TOKEN")
      """)
    end

    defp runtime_config_block("sap_soap", app_name) do
      String.trim_trailing("""
        config :#{app_name}, :soap,
          connection_id: System.get_env("SOAP_CONNECTION_ID"),
          timeout: 120_000,
          username: System.get_env("SOAP_USERNAME"),
          password: System.get_env("SOAP_PASSWORD"),
          verify_ssl: System.get_env("SOAP_VERIFY_SSL", "true") != "false",
          soap_url: System.get_env("SOAP_URL", "")
      """)
    end

    defp runtime_config_block("sap_odata", app_name) do
      String.trim_trailing("""
        config :#{app_name}, :odata,
          base_url: System.fetch_env!("ODATA_BASE_URL"),
          database: System.fetch_env!("ODATA_DATABASE"),
          username: System.fetch_env!("ODATA_USERNAME"),
          password: System.fetch_env!("ODATA_PASSWORD")
      """)
    end

    defp insert_runtime_config(content, config_code) do
      if Regex.match?(~r/if config_env\(\) != :test do/, content) do
        Regex.replace(
          ~r/(if config_env\(\) != :test do\n)/,
          content,
          fn match -> match <> config_code <> "\n\n" end,
          global: false
        )
      else
        block = "if config_env() != :test do\n#{config_code}\nend\n"

        if Regex.match?(~r/if config_env\(\) == :prod do/, content) do
          Regex.replace(
            ~r/(if config_env\(\) == :prod do)/,
            content,
            fn match -> block <> "\n" <> match end,
            global: false
          )
        else
          String.trim_trailing(content) <> "\n\n" <> block <> "\n"
        end
      end
    end

    # ──────────────────────────────────────────────
    # Application Supervision Tree
    # ──────────────────────────────────────────────

    defp add_application_children(igniter, connectors, app_name) do
      prefix = Igniter.Project.Module.module_name_prefix(igniter)
      app_module = Module.concat(prefix, Application)

      case Igniter.Project.Module.find_module(igniter, app_module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Rewrite.Source.get(source, :path)

          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            children_to_add =
              connectors
              |> Enum.reject(&child_exists?(content, &1))

            if children_to_add == [] do
              source
            else
              content =
                content
                |> ensure_maybe_child()
                |> insert_children(children_to_add, app_name)

              Rewrite.Source.update(source, :content, content)
            end
          end)

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find Application module #{inspect(app_module)}. Supervision tree not modified."
          )
      end
    end

    defp child_exists?(content, "px_rest"),
      do: String.contains?(content, "BluetabConnect.Px.Rest")

    defp child_exists?(content, "sap_soap"),
      do: String.contains?(content, "BluetabConnect.Sap.Soap,")

    defp child_exists?(content, "sap_odata"),
      do: String.contains?(content, "BluetabConnect.Sap.Odata")

    defp child_line("px_rest", app_name),
      do: "maybe_child(BluetabConnect.Px.Rest, Application.get_env(:#{app_name}, :px))"

    defp child_line("sap_soap", app_name),
      do: "maybe_child(BluetabConnect.Sap.Soap, Application.get_env(:#{app_name}, :soap))"

    defp child_line("sap_odata", app_name),
      do: "maybe_child(BluetabConnect.Sap.Odata, Application.get_env(:#{app_name}, :odata))"

    defp ensure_maybe_child(content) do
      if String.contains?(content, "defp maybe_child") do
        content
      else
        helper = """

          defp maybe_child(_module, nil), do: []
          defp maybe_child(module, config), do: [{module, config}]
        """

        Regex.replace(~r/\nend\s*\z/, content, fn _match ->
          "\n" <> helper <> "end\n"
        end)
      end
    end

    defp insert_children(content, connectors, app_name) do
      Enum.reduce(connectors, content, fn connector, content ->
        insert_single_child(content, child_line(connector, app_name))
      end)
    end

    defp maybe_child_call?(line) do
      String.contains?(line, "maybe_child(") and
        not String.contains?(line, "defp maybe_child")
    end

    defp insert_single_child(content, child_code) do
      lines = String.split(content, "\n")

      maybe_child_calls =
        lines
        |> Enum.with_index()
        |> Enum.filter(fn {line, _} -> maybe_child_call?(line) end)

      if maybe_child_calls != [] do
        {_line, last_idx} = List.last(maybe_child_calls)
        existing_line = Enum.at(lines, last_idx)
        indent_str = String.replace(existing_line, ~r/\S.*$/, "")
        existing_line = String.replace(existing_line, ~r/,\s*$/, "")

        lines
        |> List.update_at(last_idx, fn _ -> existing_line <> " ++" end)
        |> List.insert_at(last_idx + 1, "#{indent_str}#{child_code}")
        |> Enum.join("\n")
      else
        children_start_idx =
          Enum.find_index(lines, &String.contains?(&1, "children ="))

        if children_start_idx do
          closing_idx = find_children_closing_idx(lines, children_start_idx)

          case closing_idx do
            idx when is_integer(idx) ->
              closing_line = Enum.at(lines, idx)
              indent_str = String.replace(closing_line, ~r/\S.*$/, "")

              lines
              |> List.update_at(idx, &(&1 <> " ++"))
              |> List.insert_at(idx + 1, "#{indent_str}#{child_code}")
              |> Enum.join("\n")

            nil ->
              content
          end
        else
          content
        end
      end
    end

    defp find_children_closing_idx(lines, children_start_idx) do
      joined = Enum.join(lines, "\n")

      line_offsets =
        lines
        |> Enum.reduce({[], 0}, fn line, {acc, offset} ->
          {[offset | acc], offset + String.length(line) + 1}
        end)
        |> elem(0)
        |> Enum.reverse()

      children_line_offset = Enum.at(line_offsets, children_start_idx)
      children_line = Enum.at(lines, children_start_idx)

      bracket_pos =
        case :binary.match(children_line, "[") do
          {pos, _len} -> pos
          :nomatch -> nil
        end

      if is_nil(bracket_pos) do
        nil
      else
        start_offset = children_line_offset + bracket_pos
        scan_for_matching_bracket(joined, start_offset + 1, 1, line_offsets)
      end
    end

    defp scan_for_matching_bracket(_content, offset, 0, line_offsets) do
      offset_to_line_index(offset - 1, line_offsets)
    end

    defp scan_for_matching_bracket(content, offset, depth, line_offsets) do
      if offset >= byte_size(content) do
        nil
      else
        char = :binary.at(content, offset)

        new_depth =
          case char do
            ?[ -> depth + 1
            ?] -> depth - 1
            _ -> depth
          end

        if new_depth == 0 do
          offset_to_line_index(offset, line_offsets)
        else
          scan_for_matching_bracket(content, offset + 1, new_depth, line_offsets)
        end
      end
    end

    defp offset_to_line_index(offset, line_offsets) do
      line_offsets
      |> Enum.with_index()
      |> Enum.reduce_while(nil, fn {line_offset, idx}, _acc ->
        next_offset = Enum.at(line_offsets, idx + 1, :infinity)

        if offset >= line_offset and offset < next_offset do
          {:halt, idx}
        else
          {:cont, nil}
        end
      end)
    end

    # ──────────────────────────────────────────────
    # Install Notice
    # ──────────────────────────────────────────────

    defp add_install_notice(igniter, connectors) do
      env_vars =
        connectors
        |> Enum.map(&env_vars_for/1)
        |> Enum.join("\n\n")

      Igniter.add_notice(igniter, """
      BluetabConnect connectors installed: #{Enum.join(connectors, ", ")}

      Set the following environment variables:

      #{env_vars}
      """)
    end

    defp env_vars_for("px_rest") do
      String.trim_trailing("""
          # Px.Rest
          PX_API_URL=https://your-px-api-url
          PX_TOKEN=your-px-token
      """)
    end

    defp env_vars_for("sap_soap") do
      String.trim_trailing("""
          # Sap.Soap
          SOAP_CONNECTION_ID=your-connection-id
          SOAP_USERNAME=your-username
          SOAP_PASSWORD=your-password
          SOAP_URL=https://your-soap-url
          SOAP_VERIFY_SSL=true
      """)
    end

    defp env_vars_for("sap_odata") do
      String.trim_trailing("""
          # Sap.Odata
          ODATA_BASE_URL=https://your-odata-base-url
          ODATA_DATABASE=your-database
          ODATA_USERNAME=your-username
          ODATA_PASSWORD=your-password
      """)
    end
  end
end
