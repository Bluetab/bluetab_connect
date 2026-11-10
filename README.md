# BluetabConnect

**BluetabConnect** is an Elixir library that provides client wrappers for connecting to external enterprise systems. It offers a unified interface for interacting with PX (Project Management platform), Spend (expenses), Tempo (holiday calendars), Gedes (briefings, evaluations, careers and categories), and SAP Business One through both REST/OData and SOAP protocols.

## Features

- **PX REST Client** - Connect to PX platform to manage organizational data
- **Spend REST Client** - Connect to Spend app for employee per-diems
- **Tempo REST Client** - Connect to Tempo app for holiday calendars (no SAP SuccessFactors credentials needed)
- **Gedes REST Client** - Read briefings, evaluations, careers and categories from the Gedes app (read-only, scoped API key)
- **SAP OData Client** - Query SAP Business One data using OData protocol
- **SAP SOAP Client** - Comprehensive time entry management and approval workflows for SAP Business One
- **SAP SuccessFactors Client** - Query SAP SuccessFactors OData APIs

## Installation

```sh
mix igniter.install bluetab_connect@github:Bluetab/bluetab_connect
```

### Or:

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

### Spend REST Client

The Spend client requires a base URL and API key for authentication:

```elixir
config = [
  base_url: "https://spend.app.bluetab.net",
  api_key: "spend_your_api_key_here"
]

{:ok, _pid} = BluetabConnect.Spend.Rest.start_link(config)
```

### Tempo REST Client

The Tempo client requires a base URL and an API key. Create the key in Tempo under
**Admin → API Keys** and give it only the **Holidays** scope: it can then read holidays
and nothing else.

```elixir
config = [
  base_url: "https://tempo.app.bluetab.net",
  api_key: "tempo_your_api_key_here"
]

{:ok, _pid} = BluetabConnect.Tempo.Rest.start_link(config)
```

### Gedes REST Client

The Gedes client requires a base URL and an API key. Create the key in Gedes under
**Admin → API keys** and give it only the scopes you need: **Briefings** to call
`list_briefings/1`, **Evaluations** to call `list_evaluations/1`, **Careers and categories** to
call `list_careers/1` and `list_categories/1`. Briefings and evaluations hold information about
people (ratings and feedback), so give those scopes only to apps that need them. The careers
scope reads the career ladder and nothing about people.

```elixir
config = [
  base_url: "https://gedes.bluetab.net",
  api_key: "gedes_your_api_key_here"
]

{:ok, _pid} = BluetabConnect.Gedes.Rest.start_link(config)
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

The SAP SOAP client requires a SOAP URL and either a pre-issued token or TokenDispenser credentials:

```elixir
# Preferred: use a pre-issued authentication token
config = [
  soap_url: "https://your-sap-server.com/soap",
  token: "your_pre_issued_token"
]

# Alternative: fetch a token via TokenDispenser
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

#### List Spend Types

```elixir
{:ok, spend_types} = BluetabConnect.Px.Rest.list_spend_types()
```

#### List Projects

Projects, paginated. Each one always has `name`, `sap_id`, `doc_num`, `start_date`, `end_date`,
`status`, `is_time_off` and `block_date`; ask for the rest with `fields`. Full contract:
`docs/px-api-projects.md`.

```elixir
# First page of 100
{:ok, %{"projects" => projects, "pagination" => %{"has_next" => more?}}} =
  BluetabConnect.Px.Rest.list_projects()

# Filters, and the extra fields to return
{:ok, %{"projects" => projects}} =
  BluetabConnect.Px.Rest.list_projects(
    page: 1,
    per_page: 50,
    status: "pst_Started",
    client_id: 789,
    fields: [:client_id, :owner, :cluster_id]
  )

# The tags of each project, and only the projects that have a tag (or a child of it).
# `tags` takes an id, a list of ids or a comma-separated string; an empty list is left out.
{:ok, %{"projects" => projects}} =
  BluetabConnect.Px.Rest.list_projects(tags: [12, 15], fields: [:tags])

# Each tag of a project (an empty list when it has none):
# %{"id" => 12, "name" => "AWS", "dimension_id" => 3, "dimension_name" => "Tech",
#   "parent_id" => 11, "path" => "Tech > Cloud > AWS"}
```

Tags are hierarchical. A project lists only the tags assigned to it, not their ancestors (tagged
`AWS`, it does not list `Cloud`), while the `tags` filter includes descendants (filtering by
`Cloud` also returns the projects tagged `AWS`). Filters the client does not list can be sent
with `query: [cluster_id: 12]`.

#### List Planned Hours

Hours planned for employees on projects, aggregated per employee, project and month.
Requires a service account, admin, or business operations token. Every filter accepts a
single value or a list, and filters are combined with AND.

```elixir
# Every employee, project and month (can be large - prefer filtering)
{:ok, %{"planned_hours" => planned_hours, "total" => total}} =
  BluetabConnect.Px.Rest.list_planned_hours()

# One employee on one project during some months (months as "YYYY-MM" or Date)
{:ok, %{"planned_hours" => planned_hours}} =
  BluetabConnect.Px.Rest.list_planned_hours(
    employee_number: 10001,
    doc_num: 12345,
    months: ["2026-03", "2026-04"]
  )

# Several employees
{:ok, _} = BluetabConnect.Px.Rest.list_planned_hours(employee_number: [10001, 10002])

# Each item (ordered by employee_number, doc_num and month):
# %{"employee_number" => 10001, "doc_num" => 12345, "project_name" => "Example Project",
#   "month" => "2026-03", "hours" => 80.0}
```

Invalid values (e.g. the month `"2026-13"`) return `{:error, :bad_request}`. An empty list
filter matches nothing and returns an empty result without calling the API.

### Spend REST Client

The Spend client provides methods to retrieve expense-related data:

#### List Employee Per-Diems

```elixir
# List all employee per-diems
{:ok, items} = BluetabConnect.Spend.Rest.list_employee_per_diems()

# Filter by date range (start_date)
{:ok, items} =
  BluetabConnect.Spend.Rest.list_employee_per_diems(
    from: ~D[2026-09-01],
    to: ~D[2026-09-30]
  )

# Each item:
# %{"email" => ..., "start_date" => "YYYY-MM-DD", "duration_days" => n, "status" => "Imputada"}
```

### Tempo REST Client

The Tempo client reads the holiday calendars that Tempo keeps in sync with SAP SuccessFactors,
so an app that only needs holidays does not need SuccessFactors credentials
(`BluetabConnect.Sap.SuccessFactors.list_holiday_calendars/1` is what this replaces).

#### List Holidays

```elixir
# Every active holiday of every calendar
{:ok, holidays} = BluetabConnect.Tempo.Rest.list_holidays()

# One calendar (the employee hub, e.g. "MADRID"), optionally within a date range
{:ok, holidays} =
  BluetabConnect.Tempo.Rest.list_holidays(
    calendar_code: "MADRID",
    date_from: ~D[2026-01-01],
    date_to: ~D[2026-12-31]
  )

# Each item:
# %{"calendar_code" => "MADRID", "date" => "2026-01-01", "holiday_code" => "NEW_YEAR", "name" => "New Year"}
```

Holidays that SuccessFactors stopped returning are hidden in Tempo and are not listed. Items are
ordered by `calendar_code`, `date` and `holiday_code`; `date` is an ISO 8601 string.

Errors: `{:error, :unauthorized}` (unknown or expired key), `{:error, :forbidden}` (the key lacks
the `holidays` scope), `{:error, :bad_request}` (invalid date), `{:error, :list_holidays_error}`
(anything else).

#### Labor Claims

The hours that employees claim on projects, for each day. Tempo sums them in its database, so the
client reads the sums (`GET /api/v1/labor-claims/summary`) and not the claims. Needs an API key
with the **Labor claims** scope. That scope also reaches the endpoints that approve and reject
claims; the client only reads. Contract: Tempo's `docs/labor_claims_api.md`.

```elixir
# The hours of every employee on every project in March 2026, by status
{:ok, items} =
  BluetabConnect.Tempo.Rest.labor_claims_summary(
    date_from: ~D[2026-03-01],
    date_to: ~D[2026-03-31],
    group_by: [:employee_id, :project_id, :status]
  )

# Each item:
# %{"employee_id" => 92, "project_id" => 12345, "status" => "approved",
#   "total_hours" => 80.0, "entry_count" => 10}

# One employee, with the totals of their claims
{:ok, [%{"total_hours" => hours}]} = BluetabConnect.Tempo.Rest.labor_claims_summary(employee_id: 92)

# The first and the last date of the claims
{:ok, %{"min_date" => "2026-01-15", "max_date" => "2026-04-07"}} =
  BluetabConnect.Tempo.Rest.labor_claims_date_range()
```

`employee_id` is the SAP employee number and `project_id` is the SAP id of the project (its
`sap_id` in PX, not its `doc_num`); both are `nil` for a claim of a user or a project that Tempo has
no SAP id for. Deleted claims are not counted. Tempo ignores a date, a status or a `group_by` that
it cannot read and answers for all the claims, so the client refuses them with
`{:error, :bad_request}` before asking. Other errors: `{:error, :unauthorized}`,
`{:error, :forbidden}` (the key lacks the scope), `{:error, :labor_claims_summary_error}`.

### Gedes REST Client

The Gedes client reads the briefings and evaluations that Gedes has **published**, and its
careers and categories. The API is read-only; drafts and deleted records are never served. Full
contract: Gedes's `docs/api.md`.

#### List Briefings

```elixir
# Every published briefing, every person, every period (can be large - prefer filtering)
{:ok, briefings} = BluetabConnect.Gedes.Rest.list_briefings()

# One person (by email or user_id), optionally in one period
{:ok, briefings} =
  BluetabConnect.Gedes.Rest.list_briefings(user_email: "ann@example.com", period_id: 3)

# What an evaluator has briefed in a period
{:ok, briefings} =
  BluetabConnect.Gedes.Rest.list_briefings(evaluator_id: evaluator_id, period_id: 3)

# Each item (string keys, as Gedes sends them):
# %{"id" => "6f1c…", "status" => "published", "date" => "2026-02-10",
#   "role_description" => "…", "evaluator_comments" => "…",
#   "user" => %{"id" => …, "email" => …, "given_name" => …, "family_name" => …, "sap_id" => …},
#   "evaluator" => %{…} | nil, "created_by" => %{…},
#   "period" => %{"id" => 3, "name" => "2026", "start_date" => "2026-01-01", "end_date" => "2026-12-01", "active" => true},
#   "objectives" => [%{"id" => …, "definition" => …, "measurement" => …, "weight" => 60,
#                      "type" => %{…} | nil, "competency" => %{…} | nil}], …}
```

#### List Evaluations

```elixir
{:ok, evaluations} =
  BluetabConnect.Gedes.Rest.list_evaluations(user_id: user_id, period_id: 3)

{:ok, evaluations} =
  BluetabConnect.Gedes.Rest.list_evaluations(evaluator_email: "bob@example.com", status: :acknowledged)

# Each item: the evaluation (`rating` "a".."d", `rationale`, `strengths`, `weaknesses`,
# `recommendations`, …) plus `briefing_id`, `user`, `evaluator`, `created_by`, `period`,
# `objective_ratings` and `competency_ratings`.
```

#### List Careers

```elixir
{:ok, careers} = BluetabConnect.Gedes.Rest.list_careers()

# Each item: %{"id" => 1, "name" => "Technical", "external_id" => "TECH", "order" => 1,
#              "inserted_at" => "…", "updated_at" => "…"}
```

#### List Categories

```elixir
# Every category, grouped by career and in display order
{:ok, categories} = BluetabConnect.Gedes.Rest.list_categories()

# The categories of one career
{:ok, categories} = BluetabConnect.Gedes.Rest.list_categories(career_id: 1)

# Each item: %{"id" => 4, "career_id" => 1, "name" => "Senior", "external_id" => "SR", "order" => 3,
#              "category_codes" => ["A1", "A2"], "delegatable" => true,
#              "inserted_at" => "…", "updated_at" => "…",
#              "competency_levels" => [
#                %{"id" => 31, "competency" => %{"id" => 7, "name" => "Communication"},
#                  "level" => %{"id" => 3, "name" => "Senior"}}
#              ]}
```

`competency_levels` are the competency levels expected of the category (the baseline evaluations
compare competency ratings against); `[]` when none are set. Careers and categories are the
organization's career ladder, not data about people, so every one is listed.

#### Options

`list_briefings/1` and `list_evaluations/1` take the same optional filters, which combine (AND).
`nil` or blank means no filter.

| Option | Meaning |
|--------|---------|
| `:user_id` / `:user_email` | The person (UUID, or email - case-insensitive) |
| `:period_id` | Period id (integer). Without it, every period is listed |
| `:evaluator_id` / `:evaluator_email` | The person's effective evaluator for that period and position. After a delegation, the original evaluator no longer matches |
| `:status` | `"published"` or `"acknowledged"` (string or atom) |
| `:page_size` | Items per request, `1..500` (default `500`); only changes how many requests are made |

`list_categories/1` takes `:career_id` (integer) and `:page_size`; `list_careers/1` takes only
`:page_size`.

The client follows Gedes's pages until the list is complete, so the result is always the whole
list. A request that fails on any page is an error, never a partial list. An unknown option
raises `ArgumentError`: a misspelled filter must not silently turn into "everything".

Dates are `YYYY-MM-DD`. Timestamps are ISO 8601 in Madrid time with its offset
(`2026-03-01T10:15:00+01:00`).

Errors (all four functions): `{:error, :unauthorized}` (unknown, revoked or expired key),
`{:error, :forbidden}` (the key lacks the `briefings` / `evaluations` / `careers` scope),
`{:error, :bad_request}` (malformed UUID or integer, unsupported status),
`{:error, :list_briefings_error}` / `{:error, :list_evaluations_error}` /
`{:error, :list_careers_error}` / `{:error, :list_categories_error}` (anything else). Failures
are logged with the HTTP status and Gedes's error text, never with a response body or the key.

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
- **Spend REST Client**: Maintains HTTP client with API key (Bearer) authentication
- **Tempo REST Client**: Maintains HTTP client with API key (Bearer) authentication
- **Gedes REST Client**: Maintains HTTP client with API key (Bearer) authentication
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
