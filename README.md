# BluetabConnect

**BluetabConnect** is an Elixir library that provides client wrappers for connecting to external enterprise systems. It offers a unified interface for interacting with PX (Project Management platform), Spend (expenses), Tempo (holiday calendars), Gedes (briefings, evaluations, careers and categories), Markt (email notifications), Nova (matching people to positions, and the learning catalog), and SAP Business One through both REST/OData and SOAP protocols.

## Features

- **PX REST Client** - Connect to PX platform to manage organizational data
- **Spend REST Client** - Connect to Spend app for employee per-diems
- **Tempo REST Client** - Connect to Tempo app for holiday calendars (no SAP SuccessFactors credentials needed)
- **Gedes REST Client** - Read briefings, evaluations, careers and categories from the Gedes app (read-only, scoped API key)
- **Markt REST Client** - Send email notifications through the Markt app, with its BIA template (scoped API key)
- **Nova REST Client** - Rank the people of Nova's knowledge map for a position and read its technologies, and look up and add courses of its learning catalog (scoped API key, two scopes)
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

### Markt REST Client

The Markt client requires a base URL and an API key. Create the key in Markt under
**Admin → API keys** and give it the scopes it needs: **Send email** to send emails, and
**Manage groups** to make and keep up to date the groups of people an app sends to. The two are
independent, and a key can do nothing else.

```elixir
config = [
  base_url: "https://markt.app.bluetab.net",
  api_key: "markt_your_api_key_here"
]

{:ok, _pid} = BluetabConnect.Markt.Rest.start_link(config)
```

### Nova REST Client

The Nova client requires a base URL and an API key. An admin makes the key in Nova under
**Admin → API keys** (`/admin/api_keys`), **for an existing user**, with the scopes it needs, and
sees the secret once. The key does what its user may do, within its scopes:

- **Matching** (`matching`) for `match_people/1` and `list_technologies/1`. Nova makes this key
  only for a user who holds the `match_people` permission (the base role *People matcher* has it).
  Its answers carry people's employee numbers, names and emails and what the map knows of their
  technologies, so give it only to apps that need them.
- **Learning objects** (`learning_objects`) for `search_courses/1` and `create_learning_object/1`.
  Creating a talk also needs the `manage_learning_objects` permission of the key's user.

The scopes are independent: a key with one of them is refused on the endpoints of the other.

```elixir
config = [
  base_url: "https://nova.app.bluetab.net",
  api_key: "nova_your_api_key_here"
]

{:ok, _pid} = BluetabConnect.Nova.Rest.start_link(config)
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

#### List Work Assignments

The employee work assignment history: every row, current or past, that links an employee to a
client, a cluster or a business unit. Requires a service account. The filters are single values,
combine with AND, and are all optional (with none, the whole history is returned).
Full contract: [docs/px-api-work-assignments.md](docs/px-api-work-assignments.md).

```elixir
{:ok, %{"work_assignments" => assignments, "total" => total}} =
  BluetabConnect.Px.Rest.list_work_assignments(employee_number: 1234)

{:ok, _} =
  BluetabConnect.Px.Rest.list_work_assignments(cluster_id: 12, start_date_from: ~D[2026-01-01])

# Each item (ordered by effective_from descending, then employee_number):
# %{"id" => 57, "employee_number" => 1234, "target_type" => "cluster", "source" => "automatic",
#   "effective_from" => "2026-09-01", "effective_to" => nil, "is_current" => true,
#   "cluster_id" => 12, "cluster_name" => "Banking", "business_unit_id" => 3,
#   "business_unit_name" => "Financial Services", "total_hours" => 812.5,
#   "claim_days_count" => 98, "computed_at" => "2026-09-01T03:00:00", …}
```

`effective_to` is `nil` for the assignment in force. Invalid values return `{:error, :bad_request}`.

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

### Markt REST Client

Markt sends the email notifications of the BIA apps: the app says who and what, and Markt renders
it with an email template and delivers it. Needs an API key with the **Send email** scope (and
**Manage groups** for the groups). Contract: Markt's `docs/email.md`.

**Email only goes to people of the organization**: the Markt users (synced from PX) who have not
left the company. An address that is not one is never sent to, and never added to a group; Markt
keeps a list of them (Admin → Refused addresses). A template can use the name of the person
(`name`, `first_name`, `last_name`, `email`): Markt fills these in, so do not pass them.

#### Send an Email

```elixir
{:ok, queued} =
  BluetabConnect.Markt.Rest.send_email(
    to: "ana@bluetab.net",
    variables: %{title: "Labor claim approved", message: "Your claim #4521 was approved."}
  )

# Several recipients, some with a name, and the optional parts of the template
{:ok, queued} =
  BluetabConnect.Markt.Rest.send_email(
    to: ["ana@bluetab.net", %{email: "bob@bluetab.net", name: "Bob Ruiz"}],
    variables: %{
      app_name: "Tempo",
      subtitle: "Labor claims",
      title: "Labor claim approved",
      message: "Your claim **#4521** was approved.\nThe payment is scheduled for Friday.",
      action_url: "https://tempo.app.bluetab.net/claims/4521",
      action_label: "View claim"
    }
  )

# The message with structure (Markdown), or written in HTML
{:ok, queued} =
  BluetabConnect.Markt.Rest.send_email(
    to: "ana@bluetab.net",
    variables: %{
      title: "Monthly report",
      message: "## Summary\n\n- Hours: 160\n- Absences: 2\n\nSee [the report](https://tempo.app.bluetab.net)."
    }
  )

{:ok, queued} =
  BluetabConnect.Markt.Rest.send_email(
    to: "ana@bluetab.net",
    variables: %{title: "Monthly report", message: %{html: "<p>Hours: <strong>160</strong></p>"}}
  )

# To a group an app keeps up to date (see "Groups an app keeps up to date" below)
{:ok, queued} =
  BluetabConnect.Markt.Rest.send_email(
    group: "tempo-business-operators",
    variables: %{app_name: "Tempo", title: "Closing time changed", message: "From Monday the close is at 18:00."}
  )

# One item for each email:
# %{"id" => "7db83b7e-…", "to" => "ana@bluetab.net", "status" => "pending"}
#
# An address Markt did not send to is in the list too, without an id, so one outsider does not
# stop the rest:
# %{"id" => nil, "to" => "outsider@gmail.com", "status" => "rejected", "reason" => "unknown_recipient"}
# ("reason" is "unknown_recipient", or "left_company" for someone who has left)
```

By default the email uses Markt's generic BIA notification template: a bar on top (the Bluetab
logo, the app name and a subtitle), a greeting, the message, and a footer.

| Variable | Meaning |
|----------|---------|
| `:title` | **Required.** The subject of the email (`[App] Title`). It is **not shown in the body**: if you want a heading, write it in the message |
| `:message` | **Required.** The body, in **Markdown** (headings, lists, tables, links, quotes, code). A plain string works as it always did: a line break stays a line break and a blank line starts a paragraph. For HTML give `%{html: "<p>…</p>"}`; `%{markdown: "…"}` says "Markdown" explicitly |
| `:subtitle` | Text on the right of the bar on top, e.g. the section of the app. Optional |
| `:app_name` | Next to the logo, in the subject and in the footer. Default `"BIA"` |
| `:action_url` | If given, the email gets a button that links to it (`http(s)://` or `mailto:`) |
| `:action_label` | Text of that button. Default `"Open"` |

Everything except the message is plain text: Markt escapes it, so it can never add markup. The
message is cleaned by Markt of whatever could run (scripts, forms, event handlers, `javascript:`
links); a tag written inside Markdown is dropped and its text stays. Because the message is read
as Markdown, `*`, `_`, a leading `#` or `-`, and `<tags>` in it mean something: when it includes
text you did not write (a name, something a user typed), escape the Markdown characters with a
backslash, or send the message as `%{html: …}` with that text escaped. A `nil` value is left out,
so an optional variable can be passed along as it is.

| Option | Meaning |
|--------|---------|
| `:to` | One recipient or a list of up to 50: an address, `"Name <address>"`, `%{email: _, name: _}` or `{name, address}`. Each has to be a person of the organization, and the name in the email is the one Markt has for them (the name given is used only if it has none) |
| `:group` | Instead of `:to` (not both): the slug of a group an app keeps up to date. It goes out as the group is set up: **one email to each person** (up to 500, each with their own name and tracking) or **one email to everyone**, who all see who it went to (up to 50; the template must not greet by name). Any key that can send can send to any group an app owns; never to a group people made in Markt |
| `:variables` | What to fill the template with (map or keyword list) |
| `:template` | Slug of another Markt template (default: the BIA notification one, `"bia-notification"`) |
| `:subject` | Replaces the template's subject |

The emails are **queued**: `{:ok, _}` means Markt accepted the request, not that the email has
arrived. Markt delivers in the background and retries by itself, and shows what finally failed to
its admins. The client **never retries** a send, whatever `:req_options` say, because a retry after
a lost answer would send the email twice; that decision is the caller's.

Errors: `{:error, {:invalid_request, errors}}` (nothing was sent; `errors` is a list of
`%{"field" => "to[0]", "message" => "is not a valid email address"}`: Markt checks the
recipients first, then the values of the variables, then the variables the template needs, and
reports the first group that fails; a message can be refused as `"variables.message"` for being
blank, for having nothing left once cleaned, or for being over 200,000 bytes),
`{:error, :template_not_found}`, `{:error, :group_not_found}` (`:group` is not the slug of a group
an app owns), `{:error, :unauthorized}`
(unknown, deleted or expired key), `{:error, :forbidden}` (the key lacks the `send_email` scope),
`{:error, :send_email_error}` (anything else, including Markt being unreachable). If *nobody* in
the call can receive email, nothing is sent and the answer is `{:invalid_request, errors}` too (one
error for each address, e.g. `"to[0]"`: "is not a person in Markt"). An unknown option, a recipient
that is none of the forms above, a `:group` that is not a slug, and giving both `:to` and `:group`
raise `ArgumentError`. Failures are logged with the HTTP status and Markt's error text, never with
the recipients, the variables or the key.

#### Groups an app keeps up to date

An app can have a group of people in Markt that it keeps in step with its own data, and then send
to the group. The case: Tempo has the role *Business Operators*; on start-up it makes sure the
group `tempo-business-operators` has exactly those people, it adds or removes someone whenever the
role changes, and it sends its system notifications to the group instead of to a list of
addresses. Needs an API key with the **Manage groups** scope (and **Send email** to send).

```elixir
# On start-up: make the group, or change it, and leave exactly these people in it.
# Safe to repeat: it is the same group every time.
{:ok, %{"data" => group, "added" => added, "removed" => removed, "rejected" => rejected}} =
  BluetabConnect.Markt.Rest.sync_group("tempo-business-operators",
    name: "Tempo business operators",
    description: "People with the Business Operators role in Tempo",
    members: Enum.map(operators, & &1.email)
  )

# Then, as the role changes
{:ok, _} = BluetabConnect.Markt.Rest.add_group_member("tempo-business-operators", user.email)
{:ok, _} = BluetabConnect.Markt.Rest.remove_group_member("tempo-business-operators", user.email)

# What Markt has now
{:ok, %{"member_count" => 2, "members" => [%{"email" => "ana@bluetab.net", "name" => "Ana García"}, ...]}} =
  BluetabConnect.Markt.Rest.get_group("tempo-business-operators")

# And send to it
{:ok, queued} =
  BluetabConnect.Markt.Rest.send_email(
    group: "tempo-business-operators",
    variables: %{app_name: "Tempo", title: "Closing time changed", message: "From Monday the close is at 18:00."}
  )
```

The group is **owned by the key that made it** (it says *Managed by …* in Markt, and its people are
not edited by hand there), and the API only touches groups made this way, never the ones people
make in Markt. The slug is its name in the API: 3 to 80 lower case letters, digits and hyphens;
start it with the name of the app so two apps do not meet.

| Function | Does |
|----------|------|
| `sync_group(slug, opts)` | Makes the group or changes it. `:name` (needed to make it), `:description`, `:visibility`, `:members` |
| `get_group(slug)` | The group and its people. Returns `{:ok, group}` |
| `add_group_member(slug, member)` | Adds one person (nothing happens if they are in it) |
| `remove_group_member(slug, member)` | Takes one person out (nothing happens if they are not in it) |

- **`:members`**: addresses, or maps with an `:email` (up to 1000). If given, those are the people in
  the group and the others are taken out, also whoever has left the company since; `members: []`
  empties the group. **If not given, the people are left as they are**, so a call can change the
  name without touching them. They have to be people of the organization: the others are not
  added and come back in `"rejected"` (`%{"email" => _, "reason" => "unknown_recipient" | "left_company"}`),
  and the rest are synced; an app can log them and carry on.
- **`:visibility`**: `:bcc` (the default) sends **one email to each person**, so each can be tracked,
  with their own name; `:public` sends **one email to everyone**, who all see who it went to, up to 50
  people. **Leave it out to keep what is set in Markt**, where whoever manages email can change it.
- The answers are what Markt says, with string keys: `sync_group` and `add_group_member` return
  `{:ok, %{"data" => group, "added" => _, "removed" => _, "skipped" => _, "rejected" => [...]}}`,
  `remove_group_member` returns `{:ok, %{"data" => group, "removed" => _}}`.
- Unlike a send, these calls can be repeated: an answer that got lost is no reason not to call again.

Errors: `{:error, {:invalid_request, errors}}` (nothing was changed; `errors` is a list of
`%{"field" => "members[2]", "message" => "is not a valid email address"}`, also a name that is
taken, a public group over 50 people, more than 1000 members, and, for `add_group_member`, an address
that is not a person of the organization), `{:error, :group_not_found}` (`get_group`,
`add_group_member` and `remove_group_member` only: `sync_group` makes the group),
`{:error, :group_not_managed}` (people made that group in Markt: an app cannot touch it),
`{:error, :unauthorized}`, `{:error, :forbidden}` (the key lacks the `manage_groups` scope), and
one error of its own for anything else, including Markt being unreachable: `:get_group_error`,
`:sync_group_error`, `:add_group_member_error`, `:remove_group_member_error`. A `slug` or a member
that is not a non-empty string or a map with an `:email`, and an unknown option, raise
`ArgumentError`. Failures are logged with the HTTP status and Markt's error text, never with the
addresses or the key.

### Nova REST Client

Nova keeps Bluetab's learning catalog (courses, talks and paths) and a map of who knows which
technologies. The client covers both scopes of its API. Contract: Nova's `specs/api/index.md`, `matching.md` and
`learning.md`. Nova has no version in the path, and its lists come whole as
`{"items": [...], "total": n}`, so there is nothing to page.

| Function | Endpoint | Key scope | The key's user must also hold |
|----------|----------|-----------|-------------------------------|
| `match_people/1` | `POST /api/matches` | Matching | `match_people` |
| `list_technologies/1` | `GET /api/technologies` | Matching | `match_people` |
| `search_courses/1` | `GET /api/learning_objects/moocs/search` | Learning objects | - |
| `create_learning_object/1` | `POST /api/learning_objects` | Learning objects | `manage_learning_objects`, to create a talk |

**A `403` is the same whether the key lacks the scope or its user lacks the permission**, so when
one comes, check both (the client's log line names both). A key with only one scope is refused on
the endpoints of the other.

#### Match People

Ranks the people of the map for a position, from a text, from a list of requirements already made,
or from both (what is listed wins, and the text adds the technologies it names). By default it
ranks everyone on the map who is still at the company; with `:people` it ranks exactly the people
you name, and answers for every one of them. Needs the **Matching** scope.

```elixir
# From a description: everyone on the map who is still at the company, the best 20
{:ok, answer} =
  BluetabConnect.Nova.Rest.match_people(
    description: "We need a backend engineer with 3+ years of Elixir. Kafka is a plus.",
    reference: "REQ-1042"
  )

# From a list of requirements
{:ok, answer} =
  BluetabConnect.Nova.Rest.match_people(
    requirements: [
      %{technology: "Elixir", importance: "must", min_level: 3, years: 3},
      %{technology: "Kafka", importance: "nice"}
    ]
  )

# Only the people who are free: exactly those, best first, none of them left out
{:ok, answer} =
  BluetabConnect.Nova.Rest.match_people(
    description: "Data engineer, Spark and Python.",
    people: [%{sap_id: 1234}, %{email: "bob@bluetab.net"}],
    reference: "REQ-1043"
  )

# The answer, as Nova sends it (a map with string keys):
# %{"match_id" => "0b5d6c1e-…", "ranking_version" => 2, "weights_version" => 2,
#   "reference" => "REQ-1043",
#   "requirements" => [%{"technology" => %{"id" => "…", "name" => "Spark"}, "importance" => "must",
#                        "min_level" => nil, "years" => nil, "mention" => "Spark", "source" => "text"}, …],
#   "unmatched" => [],
#   "unknown_people" => [%{"sap_id" => 4242}],
#   "candidates" => [
#     %{"score" => 0.82,
#       "person" => %{"id" => "…", "sap_id" => 1234, "name" => "Ana García",
#                     "email" => "ana@bluetab.net", "profile" => "/users/…"},
#       "matched" => 2, "missing" => [], "coverage" => "stated", "technologies_known" => 14,
#       "breakdown" => [%{"technology" => "Spark", "importance" => "must", "satisfaction" => 0.9,
#                         "weight" => 0.9, "proficiency" => 4, "confidence" => 0.8, "years" => 3.0,
#                         "recency" => 1.0, "sources" => ["self", "course"], "via" => nil}, …]},
#     …]}
```

| Option | Meaning |
|--------|---------|
| `:description` | The position, as text (English or Spanish). Nova reads it for the technologies of its map that it names, how much each matters (*nice to have*, *a plus*, *deseable* make it `"nice"`) and the years asked. A technology the map does not have is not made up |
| `:requirements` | A list of maps `%{technology: name, importance: "must" \| "nice", min_level: 1..5, years: n}` (atom or string keys). Only `:technology` is needed: a name or an alias from `list_technologies/1`. One the map does not have comes back in `"unmatched"`. **Nova does not refuse an importance, level or years it cannot read** (a level is a whole number from 1 to 5: `3.0` and `9` are not): it takes `"must"` and no level or years, so check the `"requirements"` of the answer, which say what it understood |
| `:people` | Rank these people and no one else: `%{sap_id: 1234}` (the employee number, or the same as text) or `%{email: "ana@bluetab.net"}`, one of the two for each. Nothing else of a person is sent. Left out, everyone on the map is ranked; **`people: []` ranks no one** |
| `:reference` | Your own words for what the ranking is for (a request number). Nova keeps it with the ranking and gives it back |
| `:limit` | How many people at most (Nova's default: 20, or all of `:people`) |
| `:min_score` | The least score listed, 0 to 1 (Nova's default: `0.02`, or `0` with `:people`, so that every person named is listed) |

`:description` or `:requirements` is needed. `nil` means not given. Nova checks every value (sizes,
ranges, texts) and says which one is wrong; the client does not repeat those checks.

- **A ranking helps a person decide and decides nothing.** Every candidate comes with the reasons (a
  `"breakdown"` for each requirement: how sure Nova is, how recent, and where it comes from:
  `"sources"` are any of `"self"`, `"staff"`, `"document"`, `"job"`, `"course"`, `"project"`,
  `"certification"`, and `"via"` the part of the technology it comes from, such as Azure for Event
  Hubs), so whoever reads it can disagree. The same position against the same map always gives the
  same ranking. Nova does not read availability, seniority, language or location: combine the
  ranking with those in the way your decision needs.
- **A score of nothing is not one thing.** `"coverage"` is how much the map knows of the person,
  whatever the position asks: with `"none"` (nothing about their technologies) or `"exposure"` (a
  course, project work or a certification, but nothing they said) a score of nothing is *not
  known* and says nothing against them; with `"stated"` (they, or someone who keeps their CV, said
  they know a technology) it means *not for this position*.
- **`"unknown_people"`**: the names of `:people` that no one at the company answers to (or who has
  left), each as Nova understood it: `%{"sap_id" => n}` or `%{"email" => text}` trimmed and in lower
  case. A name is never dropped in silence. The employee number is not unique in Nova: when two
  users share the one you named, both are answered for, each with its own `"id"` and `"email"`.
- **The answer is about people, and the call is kept.** It carries employee numbers, names, emails
  and what the map knows of their technologies: treat it as personal data. Nova stores every
  ranking (who asked, the description, the people named and the people returned), so call it for a
  real decision, not to try things out. For that reason the client **never retries** it, whatever
  `:req_options` say: a retry after a lost answer would keep a second ranking. A request Nova refuses
  keeps nothing.
- Errors: `{:error, {:invalid_request, errors}}` (the position names no technology of the map and
  lists none: `%{"description" => ["does not name a technology the map has, …"]}`),
  `{:error, :bad_request}` (a parameter Nova could not read: nothing to rank, a value out of range,
  an entry of `:people` that does not name one person; its reason is in the log),
  `{:error, :unauthorized}`, `{:error, :forbidden}` (the key lacks the Matching scope, **or** its user
  lacks `match_people`) and `{:error, :match_people_error}` (anything else, including Nova being
  unreachable; the client does not know whether Nova kept the ranking). An unknown option, `:people`
  or `:requirements` that is not a list, and an entry that is not a map with a `:sap_id` or an
  `:email` (or a `:technology`) raise `ArgumentError`, without calling Nova; the message says which
  entry and never shows it. Failures are logged with the HTTP status and Nova's error text, never
  with the description, the people, the answer or the key.

#### List Technologies

The technologies of the map, by name, for a program that lets someone choose what a position asks
for. A ranking is asked in these names. It names no person and Nova keeps nothing of the call.
Needs the **Matching** scope.

```elixir
{:ok, technologies} = BluetabConnect.Nova.Rest.list_technologies()

# Each item:
# %{"id" => "…", "name" => "Event Hubs", "aliases" => ["Azure Event Hubs"], "category" => "cloud",
#   "parents" => [%{"id" => "…", "name" => "Azure"}], "people" => 7}
```

`"aliases"` are other names that find it (a requirement names a technology by either);
`"category"` is what it is filed under (`"cloud"`, `"language"`, `"database"`…) or `nil`;
`"parents"` is what it belongs to (the ranking counts whoever knows a part of a technology when the
whole is asked for); `"people"` is how many people still at the company have said they know it.
**Keep the `"name"`, not the `"id"`**: a technology that is merged into another keeps its names as
aliases of the other, so a name you kept still finds it, but its id goes. It takes no options.
Errors: `{:error, :unauthorized}`, `{:error, :forbidden}` (the key lacks the Matching scope, **or**
its user lacks `match_people`) and `{:error, :list_technologies_error}` (anything else).

#### Search Courses

Looks for courses by a text or by an exact address. Needs the **Learning objects** scope; the key's
user needs no permission.

```elixir
{:ok, courses} = BluetabConnect.Nova.Rest.search_courses(q: "elixir")
{:ok, courses} = BluetabConnect.Nova.Rest.search_courses(q: "elixir", limit: 5)

# Has this course been added already?
{:ok, found} =
  BluetabConnect.Nova.Rest.search_courses(external_url: "https://example.com/elixir")

# Each item, newest first:
# %{"id" => "…", "type" => "mooc", "name" => "Elixir for the impatient", "description" => "…",
#   "image" => "…", "language" => "en", "external_url" => "https://example.com/elixir",
#   "publish_date" => "2026-03-01", "subject" => "Programming", "tags" => ["elixir"],
#   "code" => 17, "duration" => 12.0, "real_cost" => 0.0, "reason" => "…", "certification" => false,
#   "title" => nil, "video" => nil, "creator_id" => "…", "published" => true,
#   "inserted_at" => "2026-03-01T09:30:00Z", "updated_at" => "2026-03-01T09:30:00Z"}
```

`:q` is matched without regard to case against the name, the description, the external URL and the
code, as written (a `%` or `_` in it means nothing special); `:external_url` matches exactly; with
both, a course must match both. `:limit` is 20 by default, and Nova brings a number outside its range
into the range. At least one of `:q` and `:external_url` has to be a text that is not blank. Hidden
courses are never returned. **Courses that are still pending are**, so a program can find one it
created (`"published" => false`), and the result is not limited to the key's user. Nova gives no
counts of requests, completions or accesses. Nova also takes `query` as an alias of `q`; the client
does not (`search_courses(query: …)` raises `ArgumentError`).

Errors: `{:error, {:invalid_request, errors}}` (neither `:q` nor `:external_url` is a text that is
not blank: this is the one `422` that Nova says with a bare text, `"provide q or external_url"`,
and not with a map of fields, so the client gives it as `%{"base" => ["provide q or external_url"]}`
like the others; `"base"` is the name Nova itself uses in its `errors` for an error that is about
no field in particular), `{:error, :bad_request}` (a `:limit` that is not a
number), `{:error, :unauthorized}`, `{:error, :forbidden}` (the key lacks the Learning objects
scope) and `{:error, :search_courses_error}` (anything else).

#### Create a Learning Object

Adds a course, a talk or a path to the catalog. Needs the **Learning objects** scope; to create a
talk, the key's user also needs `manage_learning_objects`.

```elixir
{:ok, course} =
  BluetabConnect.Nova.Rest.create_learning_object(
    type: :mooc,
    name: "Elixir for the impatient",
    description: "A fast tour of the language",
    external_url: "https://example.com/elixir",
    language: "en",
    publish_date: ~D[2026-03-01],
    subject: "Programming",
    tags: ["elixir", "beginner"],
    details: %{duration: 12, real_cost: 0, reason: "It is how we start every Elixir project."}
  )

# A path of courses, in order (a map works too)
{:ok, path} =
  BluetabConnect.Nova.Rest.create_learning_object(%{
    type: :path,
    name: "Backend in Elixir",
    details: %{steps: [course["id"], other_course["id"]]}
  })

# The learning object as Nova sends it: the shape of a course of `search_courses/1`, with the
# details of its type, and "published" => false
```

| Field | Meaning |
|-------|---------|
| `:type` | **Required.** `:mooc` (a course), `:talk` or `:path`. The API has no blog |
| `:name` | **Required** |
| `:description`, `:image`, `:language`, `:external_url`, `:publish_date`, `:subject`, `:tags` | Optional. `:publish_date` is a `Date` or `"YYYY-MM-DD"` |
| `:details` | The details of the type. A course needs `duration` (hours), `real_cost` (euros) and `reason`, and can have `certification`, `title` and `video`. A talk has `subtype` (`"talk"`, `"lightning_talk"` or `"academy_course"`), `speakers` (user ids) and `video_url`. A path has `steps`, learning object ids in order |

It is created **pending**, with the owner of the key as its creator, and stays so until it is
approved in Nova; the API cannot approve, change, hide or delete anything. **Creating is not
idempotent**: the same call twice makes two learning objects (except a course with an
`:external_url`, which Nova refuses the second time), so look for the course first with
`search_courses/1`. For that reason the client **never retries** it, whatever `:req_options` say.
A field that is not in the table (a typo, or `:creator_id`, which Nova would ignore) raises
`ArgumentError`.

Errors: `{:error, {:invalid_request, errors}}` (Nova refused the data and made nothing; `errors` is
a map of fields to messages, nested for the details: `%{"details" => %{"duration" => ["is required"]}}`,
`%{"external_url" => ["a course with this address already exists"]}`), `{:error, :bad_request}`,
`{:error, :unauthorized}`, `{:error, :forbidden}` (the key lacks the Learning objects scope, **or**,
for a talk, its user lacks `manage_learning_objects`) and `{:error, :create_learning_object_error}`
(anything else, including Nova being unreachable: the client does not know whether it made the
learning object, so look for it before trying again).

In all four functions `{:error, {:invalid_request, errors}}` is a `422`, and `errors` is a map of
field to messages (an error that is about no field in particular is under `"base"`, as Nova files
it). Failures are logged with the HTTP status and Nova's error text, never with a
response body, a description, the people or the key.

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
- **Markt REST Client**: Maintains HTTP client with API key (Bearer) authentication
- **Nova REST Client**: Maintains HTTP client with API key (Bearer) authentication
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
