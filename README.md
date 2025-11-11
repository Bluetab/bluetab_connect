# BluetabConnect

**BluetabConnect** is an Elixir library that provides client wrappers for connecting to external enterprise systems. It offers a unified interface for interacting with PX (Project Management platform) and SAP Business One through both REST/OData and SOAP protocols.

## Features

- **PX REST Client** - Connect to PX platform to manage organizational data
- **SAP OData Client** - Query SAP Business One data using OData protocol
- **SAP SOAP Client** - Comprehensive time entry management and approval workflows for SAP Business One

## Installation

Add `bluetab_connect` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bluetab_connect, "~> 0.1.0"}
  ]
end
```

## Configuration

### PX REST Client

The PX client requires a base URL and bearer token for authentication:

```elixir
config = [
  base_url: "https://px.app.bluetab.net",
  bearer_token: "your_bearer_token_here"
]

{:ok, _pid} = BluetabConnect.Px.Rest.start_link(config)
```

### SAP OData Client

The SAP OData client requires base URL, database name, username, and password:

```elixir
config = [
  base_url: "https://your-sap-server.com",
  database: "YOUR_DB_NAME",
  username: "your_username",
  password: "your_password"
]

{:ok, _pid} = BluetabConnect.Sap.Odata.start_link(config)
```

### SAP SOAP Client

The SAP SOAP client requires SOAP URL, connection ID, username, and password:

```elixir
config = [
  soap_url: "https://your-sap-server.com/soap",
  connection_id: "your_connection_id",
  username: "your_username",
  password: "your_password"
]

{:ok, _pid} = BluetabConnect.Sap.Soap.start_link(config)
```

## Usage

### PX REST Client

The PX client provides methods to retrieve organizational data:

#### List Initiatives

```elixir
{:ok, initiatives} = BluetabConnect.Px.Rest.list_initiatives()
```

#### List Clients

```elixir
{:ok, clients} = BluetabConnect.Px.Rest.list_clients()
```

#### List Client Groups

```elixir
{:ok, client_groups} = BluetabConnect.Px.Rest.list_client_groups()
```

#### List Clusters

```elixir
{:ok, clusters} = BluetabConnect.Px.Rest.list_clusters()
```

#### List Business Units

```elixir
{:ok, business_units} = BluetabConnect.Px.Rest.list_business_units()
```

### SAP OData Client

The SAP OData client provides methods to query SAP Business One data with flexible filtering and pagination:

#### List Employees

```elixir
# List all recent active employees
{:ok, employees} = BluetabConnect.Sap.Odata.list_employees()

# Filter by specific criteria
params = %{
  recent: false,
  active: true,
  relation_type: "INTERNAL"
}
opts = [select: "EmployeeID,eMail,FirstName,LastName", size: 5000]
{:ok, employees} = BluetabConnect.Sap.Odata.list_employees(params, opts)

# Filter by employee ID or email
{:ok, employee} = BluetabConnect.Sap.Odata.list_employees(%{id: 123})
{:ok, employee} = BluetabConnect.Sap.Odata.list_employees(%{email: "user@example.com"})

# Filter by multiple employee IDs
{:ok, employees} = BluetabConnect.Sap.Odata.list_employees(%{employee_ids: [123, 456, 789]})
```

#### List Projects

```elixir
# List all projects
{:ok, projects} = BluetabConnect.Sap.Odata.list_projects()

# Filter by initiative code
{:ok, projects} = BluetabConnect.Sap.Odata.list_projects(%{initiative: "INIT-001"})

# Custom selection and pagination
opts = [
  select: "AbsEntry,ProjectName,StartDate,BusinessPartnerName",
  size: 1000
]
{:ok, projects} = BluetabConnect.Sap.Odata.list_projects(%{}, opts)
```

#### List Assignments (Time Tracking)

```elixir
# List all assignments
{:ok, assignments} = BluetabConnect.Sap.Odata.list_assignments()

# Filter by date range
params = %{
  since: "2024-01-01",
  until: "2024-12-31"
}
{:ok, assignments} = BluetabConnect.Sap.Odata.list_assignments(params)

# Filter by employee
params = %{
  employee_id: 123,
  since: "2024-01-01"
}
{:ok, assignments} = BluetabConnect.Sap.Odata.list_assignments(params)

# Filter by project IDs
params = %{
  project_ids: [100, 200, 300],
  since: "2024-01-01"
}
{:ok, assignments} = BluetabConnect.Sap.Odata.list_assignments(params)
```

### SAP SOAP Client

The SAP SOAP client provides comprehensive time entry management and approval workflows:

#### Time Entry Management

##### Create or Update Time Entries

```elixir
alias BluetabConnect.Sap.Soap.Proyectos

# Create new time entries
imputaciones = [
  %{
    "IdProyecto" => 123,
    "IdEmpleado" => 456,
    "Dia" => "2024-01-15",
    "Horas" => 8.0,
    "IdTipoHora" => "NORMAL",
    "Comentario" => "Development work",
    "Estado" => "Imputado",
    "Albaran" => 789,
    "IdEmpleadoImp" => 456
  }
]

{:ok, response} = Proyectos.set_imputaciones_horas(456, imputaciones)

# Update existing time entries (include "Code" field)
imputaciones = [
  %{
    "Code" => "12345",  # Include for updates
    "IdProyecto" => 123,
    "IdEmpleado" => 456,
    "Dia" => "2024-01-15",
    "Horas" => 6.5,  # Updated hours
    "IdTipoHora" => "NORMAL",
    "Comentario" => "Updated comment",
    "Estado" => "Imputado",
    "Albaran" => 789,
    "IdEmpleadoImp" => 456
  }
]

{:ok, response} = Proyectos.set_imputaciones_horas(456, imputaciones)
```

#### Approval Workflow

##### Submit Time Entries for Approval

```elixir
# Submit time entries (changes status from "Imputado" to "Liberado")
liberaciones = [
  %{
    "Code" => "12345",
    "IdProyecto" => 123,
    "IdEmpleado" => 456,
    "Dia" => "2024-01-15",
    "Horas" => 8.0,
    "IdTipoHora" => "NORMAL",
    "Estado" => "Imputado"
  }
]

{:ok, response} = Proyectos.set_liberaciones_horas(456, liberaciones)
# Or for manager submitting on behalf of employee
{:ok, response} = Proyectos.set_liberaciones_horas(456, liberaciones, false)
```

##### Approve Time Entries

```elixir
# Approve time entries (changes status from "Liberado" to "Aprobado")
aprobaciones = [
  %{
    "Code" => "12345",
    "IdProyecto" => 123,
    "IdEmpleado" => 456,
    "Dia" => "2024-01-15",
    "Horas" => 8.0,
    "IdTipoHora" => "NORMAL",
    "Estado" => "Liberado"
  }
]

{:ok, response} = Proyectos.set_aprobaciones_horas(aprobaciones)
```

##### Reject Time Entries

```elixir
# Reject time entries (changes status from "Liberado" to "Rechazado")
rechazos = [
  %{
    "Code" => "12345",
    "IdProyecto" => 123,
    "IdEmpleado" => 456,
    "Dia" => "2024-01-15",
    "Horas" => 8.0,
    "IdTipoHora" => "NORMAL",
    "Estado" => "Liberado",
    "MotivoRechazo" => "Incorrect project assignment"
  }
]

{:ok, response} = Proyectos.set_rechazos_horas(rechazos)
```

#### Data Retrieval

##### Get Calendar Data

```elixir
# Get weekly calendar with time entries for an employee
{:ok, calendar} = Proyectos.get_calendario(456, "2024-01-15")

# Returns a list of days with structure:
# [
#   %{
#     employee_id: 456,
#     date: ~D[2024-01-15],
#     status: "Aprobado",
#     is_holiday: false,
#     inputs: [
#       %{
#         code: "12345",
#         status: "Aprobado",
#         project_id: "123",
#         hours: "8.0",
#         type_id: "NORMAL",
#         comment: "Development work",
#         reject_reason: %{}
#       }
#     ]
#   }
# ]
```

##### Get Available Hour Types

```elixir
# Get list of available hour types
{:ok, hour_types} = Proyectos.get_tipos_horas()

# Returns:
# [
#   %{code: "NORMAL", name: "Normal Hours", is_default: true},
#   %{code: "EXTRA", name: "Extra Hours", is_default: false}
# ]
```

##### Get Available Projects

```elixir
# Get list of available projects for time assignment
{:ok, projects} = Proyectos.get_proyectos()

# Returns:
# [
#   %{id: "123", name: "Project Alpha"},
#   %{id: "456", name: "Project Beta"}
# ]
```

##### Get Users for Approval

```elixir
# Get list of users that can be approved by current user
{:ok, response} = Proyectos.get_usuarios_aprobacion(789)
```

##### Get Users for HR Management

```elixir
# Get list of all users for HR management
{:ok, response} = Proyectos.get_usuarios_para_rrhh(789)
```

## Architecture

### GenServer-Based Clients

All clients are implemented as GenServers that maintain persistent connections and authentication state:

- **PX REST Client**: Maintains HTTP client with bearer token authentication
- **SAP OData Client**: Maintains HTTP client with basic authentication and custom SSL configuration
- **SAP SOAP Client**: Manages WSDL cache and authentication tokens

### Automatic Pagination

The SAP OData client automatically handles pagination for large result sets using the `@odata.nextLink` pattern, returning complete datasets without manual pagination management.

### Error Handling

All client methods return tagged tuples:

- `{:ok, result}` - Successful operation
- `{:error, reason}` - Failed operation with reason

Errors are also logged for debugging purposes.

## Time Entry Workflow States

Time entries in SAP follow a state machine pattern:

```
Imputado → Liberado → Aprobado
    ↓          ↓
    ×      Rechazado
```

- **Imputado**: Initial state when time entry is created
- **Liberado**: Submitted for approval (can be approved or rejected)
- **Aprobado**: Approved by manager
- **Rechazado**: Rejected by manager (can be corrected and resubmitted)

## Dependencies

- **req** (~> 0.5.15) - HTTP client for REST and OData APIs
- **soap** - SOAP client for SAP SOAP services
- **jason** - JSON encoding/decoding (via req)
- **sweet_xml** - XML parsing (via soap)

## License

Copyright © 2024 Bluetab

---

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at <https://hexdocs.pm/bluetab_connect>.
