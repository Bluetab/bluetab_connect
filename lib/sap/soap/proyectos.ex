defmodule BluetabConnect.Sap.Soap.Proyectos do
  @moduledoc """
  Proyectos SOAP client module for handling project-related operations.
  Based on SCL_Addins_Bluetab_Proyectos.wsdl
  """

  @endpoint "SCL_Addins_Bluetab_Proyectos.asmx"

  require Logger
  alias BluetabConnect.Sap.Soap

  # Time Entry Management Operations

  @doc """
  Creates or updates multiple time entries for an employee.

  Parameters:
  - id_empleado: Employee ID
  - imputaciones: List of time entry maps

  Time entry map structure:
  %{
    "Code" => "optional_code",           # Omit for new entries, include for updates
    "IdProyecto" => 123,                 # Required: Project ID
    "IdEmpleado" => 456,                 # Required: Employee ID
    "Dia" => "2023-12-15",              # Required: Date in YYYY-MM-DD format
    "Horas" => 8.0,                     # Required: Hours worked (0.0-24.0)
    "IdTipoHora" => "NORMAL",           # Required: Hour type ID
    "Comentario" => "Optional comment", # Optional: Comments (max 500 chars)
    "Estado" => "Imputado",             # Required: Status (typically "Imputado" for new)
    "Albaran" => 789,                   # Required: Invoice number
    "IdEmpleadoImp" => 456              # Required: Employee who made the entry
  }
  """
  def set_imputaciones_horas(id_empleado, imputaciones) do
    params = %{
      "IdEmpleado" => id_empleado,
      "Imputaciones" => Enum.map(imputaciones, &%{"ImputacionHoras" => &1})
    }

    case Soap.call(@endpoint, "SetImputacionesHoras", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  # Approval Workflow Operations

  @doc """
  Submits time entries for approval (changes status to "Liberado").

  Parameters:
  - id_empleado: Employee ID
  - liberaciones: List of time entries to release
  - imputacion_propia: Boolean indicating if these are the employee's own entries

  Time entries must have Estado = "Imputado" to be released.
  """
  def set_liberaciones_horas(id_empleado, liberaciones, imputacion_propia \\ true) do
    params = %{
      "IdEmpleado" => id_empleado,
      "Liberaciones" => Enum.map(liberaciones, &%{"ImputacionHoras" => &1}),
      "ImputacionPropia" => imputacion_propia
    }

    case Soap.call(@endpoint, "SetLiberacionesHoras", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Approves time entries (changes status to "Aprobado").

  Parameters:
  - aprobaciones: List of time entries to approve

  Time entries must have Estado = "Liberado" to be approved.
  """
  def set_aprobaciones_horas(aprobaciones) do
    params = %{
      "Aprobaciones" => Enum.map(aprobaciones, &%{"ImputacionHoras" => &1})
    }

    case Soap.call(@endpoint, "SetAprobacionesHoras", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Rejects time entries (changes status to "Rechazado").

  Parameters:
  - rechazos: List of time entries to reject

  Each time entry must include "MotivoRechazo" field with rejection reason.
  Time entries must have Estado = "Liberado" to be rejected.
  """
  def set_rechazos_horas(rechazos) do
    params = %{
      "Rechazos" => Enum.map(rechazos, &%{"ImputacionHoras" => &1})
    }

    case Soap.call(@endpoint, "SetRechazosHoras", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  # Data Retrieval Operations

  @doc """
  Gets calendar data for time tracking.

  Parameters:
  - user_id: User ID for whom calendar data is requested
  - fecha: Reference date in YYYY-MM-DD format (typically Monday of the week)

  Returns: {:ok, %{calendario: calendar_data}}
  """
  def get_calendario(user_id, fecha) do
    params = %{
      "UserId" => user_id,
      "Fecha" => fecha
    }

    case Soap.call(@endpoint, "GetCalendario", params) do
      {:ok,
       %{
         GetCalendarioResponse: %{
           GetCalendarioResult: %{
             ExecutionSuccess: "true",
             CalendarioVisible: %{
               Dias: days
             }
           }
         }
       }} ->
        {:ok, parse_days(days, user_id)}

      {:ok,
       %{
         GetCalendarioResponse: %{
           GetCalendarioResult: %{
             ExecutionSuccess: "false",
             FailureReason:
               "Error al obtener el calendario de vacaciones: No se encuantra el empleado"
           }
         }
       }} ->
        {:error, :employee_not_found}

      {:ok,
       %{
         GetCalendarioResponse: %{
           GetCalendarioResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      {:error, :timeout} = error ->
        error

      error ->
        Logger.error("Unexpected calendar response format: #{inspect(error)}")
        {:error, :invalid_calendar_response}
    end
  end

  defp parse_days(days, employee_id) do
    days
    |> Enum.map(fn {_,
                    %{Fecha: fecha, Estado: status, Festivo: festivo, Imputaciones: imputaciones}} ->
      date =
        fecha
        |> String.split("T")
        |> List.first()
        |> Date.from_iso8601!()

      %{
        employee_id: employee_id,
        date: date,
        status: status,
        is_holiday: festivo == "true",
        inputs: Enum.map(imputaciones, &parse_imputacion/1)
      }
    end)
  end

  defp parse_imputacion(
         {_,
          %{
            Code: code,
            Estado: status,
            IdProyecto: project_id,
            Horas: hours,
            IdTipoHora: type_id,
            Comentario: comment,
            MotivoRechazo: reject_reason
          }}
       ),
       do: %{
         code: code,
         status: status,
         project_id: project_id,
         hours: hours,
         type_id: type_id,
         comment: comment,
         reject_reason: reject_reason
       }

  @doc """
  Gets available hour types.

  Parameters:

  Returns: {:ok, %{tipos_horas: [hour_type_data]}}
  """
  def get_tipos_horas do
    case Soap.call(@endpoint, "GetTiposHoras") do
      {:ok,
       %{
         GetTiposHorasResponse: %{
           GetTiposHorasResult: %{
             ExecutionSuccess: "true",
             FailureReason: %{},
             TiposHoras: tipos_imputacion
           }
         }
       }}
      when is_list(tipos_imputacion) ->
        tipos_imputacion
        |> Enum.map(fn {_, %{Id: code, Nombre: name, PorDefecto: is_default}} ->
          %{
            code: code,
            name: name,
            is_default: is_default == "true"
          }
        end)
        |> then(&{:ok, &1})

      error ->
        Logger.error("Unexpected report input types response format: #{inspect(error)}")

        {:error, :invalid_report_input_types_response}
    end
  end

  @doc """
  Gets available projects for time assignment.

  Parameters:

  Returns: {:ok, %{proyectos: [project_data]}}
  """
  def get_proyectos do
    case Soap.call(@endpoint, "GetProyectos") do
      {:ok,
       %{
         GetProyectosResponse: %{
           GetProyectosResult: %{
             ExecutionSuccess: "true",
             FailureReason: %{},
             Proyectos: projects
           }
         }
       }}
      when is_list(projects) ->
        Enum.map(projects, fn {_, %{Id: id, Nombre: name}} ->
          %{
            id: id,
            name: name
          }
        end)
        |> then(&{:ok, &1})

      error ->
        Logger.error("Unexpected projects response format: #{inspect(error)}")
        {:error, :invalid_projects_response}
    end
  end

  @doc """
  Gets available expense types.

  Returns: {:ok, [expense_type_data]}
  """
  def get_tipos_gasto do
    case Soap.call(@endpoint, "GetTiposGasto") do
      {:ok,
       %{
         GetTiposGastoResponse: %{
           GetTiposGastoResult: %{
             ExecutionSuccess: "true",
             Gastos: tipos_gasto
           }
         }
       }} ->
        tipos_gasto
        |> parse_collection(&parse_tipo_gasto/1)
        |> then(&{:ok, &1})

      {:ok,
       %{
         GetTiposGastoResponse: %{
           GetTiposGastoResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense types response format: #{inspect(error)}")
        {:error, :invalid_expense_types_response}
    end
  end

  # User Management Operations

  @doc """
  Gets users that can be approved by the current user.

  Parameters:
  - user_id: ID of the user requesting the list (approver)

  Returns: {:ok, %{empleados: [employee_data]}}
  """
  def get_usuarios_aprobacion(user_id) do
    params = %{
      "UserId" => user_id
    }

    case Soap.call(@endpoint, "GetUsuariosAprobar", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Gets all users for HR management.

  Parameters:
  - user_id: ID of the HR user requesting the list

  Returns: {:ok, %{usuarios: [user_data]}}
  """
  def get_usuarios_para_rrhh(user_id) do
    params = %{
      "UserId" => user_id
    }

    case Soap.call(@endpoint, "GetUsuariosParaRRHH", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  # Expense Management Operations

  @doc """
  Gets expense settlements for a user.

  Parameters:
  - user_id: User ID for whom settlements are requested
  """
  def get_liquidaciones_gastos(user_id) do
    params = %{
      "UserId" => user_id
    }

    case Soap.call(@endpoint, "GetLiquidacionesGastos", params) do
      {:ok,
       %{
         GetLiquidacionesGastosResponse: %{
           GetLiquidacionesGastosResult: %{
             ExecutionSuccess: "true",
             Liquidaciones: liquidaciones
           }
         }
       }} ->
        liquidaciones
        |> parse_collection(&parse_liquidacion/1)
        |> then(&{:ok, &1})

      {:ok,
       %{
         GetLiquidacionesGastosResponse: %{
           GetLiquidacionesGastosResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense settlements response format: #{inspect(error)}")
        {:error, :invalid_expense_settlements_response}
    end
  end

  @doc """
  Gets expense settlement headers for a user.

  Parameters:
  - user_id: User ID for whom settlement headers are requested
  """
  def get_cabeceras_liquidaciones(user_id) do
    params = %{
      "UserId" => user_id
    }

    case Soap.call(@endpoint, "GetCabecerasLiquidaciones", params) do
      {:ok,
       %{
         GetCabecerasLiquidacionesResponse: %{
           GetCabecerasLiquidacionesResult: %{
             ExecutionSuccess: "true",
             Liquidaciones: liquidaciones
           }
         }
       }} ->
        liquidaciones
        |> parse_collection(&parse_liquidacion/1)
        |> then(&{:ok, &1})

      {:ok,
       %{
         GetCabecerasLiquidacionesResponse: %{
           GetCabecerasLiquidacionesResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense headers response format: #{inspect(error)}")
        {:error, :invalid_expense_headers_response}
    end
  end

  @doc """
  Gets a single expense settlement by code.

  Parameters:
  - code: Settlement code
  """
  def get_liquidacion_gastos(code) do
    params = %{
      "Code" => code
    }

    case Soap.call(@endpoint, "GetLiquidacionGastos", params) do
      {:ok,
       %{
         GetLiquidacionGastosResponse: %{
           GetLiquidacionGastosResult: %{
             ExecutionSuccess: "true",
             Liquidacion: liquidacion
           }
         }
       }} ->
        {:ok, parse_liquidacion(liquidacion)}

      {:ok,
       %{
         GetLiquidacionGastosResponse: %{
           GetLiquidacionGastosResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense settlement response format: #{inspect(error)}")
        {:error, :invalid_expense_settlement_response}
    end
  end

  @doc """
  Creates or updates an expense settlement.

  Parameters:
  - liquidacion: Settlement payload map
  """
  def set_liquidacion_gastos(liquidacion) do
    params = %{
      "Liquidacion" => normalize_comment_line_breaks(liquidacion)
    }

    case Soap.call(@endpoint, "SetLiquidacionGastos", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Submits multiple settlements for release.

  Parameters:
  - liberaciones: List of settlement codes
  """
  def set_liberaciones_liquidaciones(liberaciones) do
    params = %{
      "Liberaciones" => Enum.map(liberaciones, &%{"string" => &1})
    }

    case Soap.call(@endpoint, "SetLiberacionesLiquidaciones", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Gets settlements pending approval using filters.

  Parameters:
  - user_id: Approver user ID
  - user_filter: Employee filter
  - project_filter: Project filter
  """
  def get_liquidaciones_gastos_aprobar(user_id, user_filter, project_filter) do
    params = %{
      "UserId" => user_id,
      "UserFilter" => user_filter,
      "ProjectFilter" => project_filter
    }

    case Soap.call(@endpoint, "GetLiquidacionesGastosAprobar", params) do
      {:ok,
       %{
         GetLiquidacionesGastosAprobarResponse: %{
           GetLiquidacionesGastosAprobarResult: %{
             ExecutionSuccess: "true",
             Liquidaciones: liquidaciones
           }
         }
       }} ->
        liquidaciones
        |> parse_collection(&parse_liquidacion/1)
        |> then(&{:ok, &1})

      {:ok,
       %{
         GetLiquidacionesGastosAprobarResponse: %{
           GetLiquidacionesGastosAprobarResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense approvals response format: #{inspect(error)}")
        {:error, :invalid_expense_approvals_response}
    end
  end

  @doc """
  Approves settlements with optional refactoring flags.

  Parameters:
  - user_id: Approver user ID
  - aprobaciones: List of approval payloads
  """
  def set_aprobaciones_liquidaciones(user_id, aprobaciones) do
    params = %{
      "UserId" => user_id,
      "Aprobaciones" => Enum.map(aprobaciones, &%{"DatosAprobacion" => &1})
    }

    case Soap.call(@endpoint, "SetAprobacionesLiquidaciones", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Rejects settlements with a rejection reason.

  Parameters:
  - rechazos: List of rejection payloads
  """
  def set_rechazos_liquidaciones(rechazos) do
    params = %{
      "Rechazos" => Enum.map(rechazos, &%{"DatosRechazoLiquidacion" => &1})
    }

    case Soap.call(@endpoint, "SetRechazosLiquidaciones", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Gets an expense attachment by code.

  Parameters:
  - code: Attachment code
  """
  def get_justificante(code) do
    params = %{
      "Code" => code
    }

    case Soap.call(@endpoint, "GetJustificante", params) do
      {:ok,
       %{
         GetJustificanteResponse: %{
           GetJustificanteResult: %{
             ExecutionSuccess: "true",
             Justificante: justificante
           }
         }
       }} ->
        {:ok, parse_justificante(justificante)}

      {:ok,
       %{
         GetJustificanteResponse: %{
           GetJustificanteResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense attachment response format: #{inspect(error)}")
        {:error, :invalid_expense_attachment_response}
    end
  end

  @doc """
  Creates or updates an expense attachment.

  Parameters:
  - justificante: Attachment payload map
  """
  def set_justificante(justificante) do
    params = %{
      "Justificante" => justificante
    }

    case Soap.call(@endpoint, "SetJustificante", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  @doc """
  Gets an expense report file for a user and date range.

  Parameters:
  - user_id: User ID
  - from_date: Start date (YYYY-MM-DD)
  - to_date: End date (YYYY-MM-DD)
  """
  def get_hoja_gastos(user_id, from_date, to_date) do
    params = %{
      "UserId" => user_id,
      "FromDate" => from_date,
      "ToDate" => to_date
    }

    case Soap.call(@endpoint, "GetHojaGastos", params) do
      {:ok,
       %{
         GetHojaGastosResponse: %{
           GetHojaGastosResult: %{
             ExecutionSuccess: "true",
             Base64String: base64,
             FileName: file_name
           }
         }
       }} ->
        {:ok, %{base64_string: base64, file_name: file_name}}

      {:ok,
       %{
         GetHojaGastosResponse: %{
           GetHojaGastosResult: %{
             ExecutionSuccess: "false",
             FailureReason: reason
           }
         }
       }} ->
        {:error, inspect(reason)}

      error ->
        Logger.error("Unexpected expense report response format: #{inspect(error)}")
        {:error, :invalid_expense_report_response}
    end
  end

  @doc """
  Creates an expense settlement with explicit credentials.

  Parameters:
  - usuario: Fastag user
  - password: Fastag password
  - liquidacion: Settlement payload map
  """
  def create_liquidacion_gastos(usuario, password, liquidacion) do
    params = %{
      "Usuario" => usuario,
      "Password" => password,
      "Liquidacion" => normalize_comment_line_breaks(liquidacion)
    }

    case Soap.call(@endpoint, "CreateLiquidacionGastos", params) do
      {:ok, response} ->
        {:ok, response}

      error ->
        {:error, error}
    end
  end

  defp parse_collection(collection, mapper) when is_list(collection),
    do: Enum.map(collection, mapper)

  defp parse_collection(%{} = collection, mapper),
    do: collection |> Map.to_list() |> Enum.map(mapper)

  defp parse_collection(_, _mapper), do: []

  defp parse_liquidacion({_, liquidacion}), do: parse_liquidacion(liquidacion)

  defp parse_liquidacion(%{} = liquidacion) do
    %{
      code: value(liquidacion, :Code),
      concept: value(liquidacion, :Concepto),
      project_id: value(liquidacion, :IdProyecto),
      project_name: value(liquidacion, :NombreProyecto),
      employee_id: value(liquidacion, :IdEmpleado),
      employee_name: value(liquidacion, :NombreEmpleado),
      approver_employee_id: value(liquidacion, :IdEmpleadoAprobacion),
      date: value(liquidacion, :Fecha),
      country: value(liquidacion, :Pais),
      country_name: value(liquidacion, :NombrePais),
      locality: value(liquidacion, :Localidad),
      comment: value(liquidacion, :Comentario),
      status: value(liquidacion, :Estado),
      reject_reason: value(liquidacion, :MotivoRechazo),
      expenses: value(liquidacion, :Gastos) |> parse_collection(&parse_gasto/1)
    }
  end

  defp parse_liquidacion(_), do: %{}

  defp parse_gasto({_, gasto}), do: parse_gasto(gasto)

  defp parse_gasto(%{} = gasto) do
    %{
      code: value(gasto, :Code),
      line: value(gasto, :Line),
      project_id: value(gasto, :IdProyecto),
      employee_id: value(gasto, :IdEmpleado),
      employee_name: value(gasto, :NombreEmpleado),
      date: value(gasto, :Fecha),
      expense_type: value(gasto, :TipoGasto),
      expense_name: value(gasto, :NombreGasto),
      comment: value(gasto, :Comentario),
      amount: value(gasto, :Importe),
      currency: value(gasto, :Divisa),
      quantity: value(gasto, :Cantidad),
      receipt_name: value(gasto, :NombreJustificante),
      receipt: value(gasto, :Justificante),
      receipt_code: value(gasto, :CodeJustificante),
      rebill: parse_boolean(value(gasto, :Refacturar)),
      albaran: value(gasto, :Albaran)
    }
  end

  defp parse_gasto(_), do: %{}

  defp parse_justificante({_, justificante}), do: parse_justificante(justificante)

  defp parse_justificante(%{} = justificante) do
    %{
      code: value(justificante, :Code),
      receipt: value(justificante, :Justificante),
      receipt_name: value(justificante, :NombreJustificante)
    }
  end

  defp parse_justificante(_), do: %{}

  defp parse_tipo_gasto({_, tipo_gasto}), do: parse_tipo_gasto(tipo_gasto)

  defp parse_tipo_gasto(%{} = tipo_gasto) do
    %{
      code: value(tipo_gasto, :Id),
      name: value(tipo_gasto, :Nombre),
      class: value(tipo_gasto, :Clase),
      price: value(tipo_gasto, :Precio),
      currency: value(tipo_gasto, :Moneda)
    }
  end

  defp parse_tipo_gasto(_), do: %{}

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  # SAP stores multiline comments more reliably when sent as CRLF.
  # We normalize both atom and string keys named "Comentario".
  defp normalize_comment_line_breaks(value) when is_list(value),
    do: Enum.map(value, &normalize_comment_line_breaks/1)

  defp normalize_comment_line_breaks(%{} = value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_value =
        if comentario_key?(key) and is_binary(nested_value) do
          nested_value
          |> String.replace("\r\n", "\n")
          |> String.replace("\r", "\n")
          |> String.replace("\n", "\r\n")
        else
          normalize_comment_line_breaks(nested_value)
        end

      Map.put(acc, key, normalized_value)
    end)
  end

  defp normalize_comment_line_breaks(value), do: value

  defp comentario_key?(:Comentario), do: true
  defp comentario_key?("Comentario"), do: true
  defp comentario_key?(_), do: false

  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(_), do: nil
end
