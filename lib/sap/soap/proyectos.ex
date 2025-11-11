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
             FailureReason: %{},
             CalendarioVisible: %{
               Dias: days
             }
           }
         }
       }} ->
        {:ok, parse_days(days, user_id)}

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
end
