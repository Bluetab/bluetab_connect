# Projects API

## Overview

The Projects API provides a RESTful endpoint for querying project information with authentication via service accounts. The API supports pagination, filtering, and selective field retrieval.

To update project planning, see the **Project Plan API** (`project-plan.md`).

**Endpoint:** `GET /api/projects`  
**Authentication:** Bearer token (service account required)

## Required Fields

The following fields are always returned for each project:

- `name` — Project name
- `sap_id` — Project AbsEntry (SAP identifier)
- `doc_num` — Project ID (DocNum from SAP)
- `start_date` — Project start date
- `end_date` — Project closing date
- `status` — Project status
- `is_time_off` — Whether the project is marked as time off
- `block_date` — Project block date (`YYYY-MM-DD`), or `null` if not configured. Hours and expenses dated after this day cannot be approved.

## Query Parameters

### Pagination

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: 1) |
| `per_page` | integer | Items per page (default: 100, no maximum limit) |

### Filters

| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | Filter by project status (e.g. `pst_Started`, `pst_Closed`) |
| `sap_id` | integer | Filter by project AbsEntry |
| `doc_num` | integer | Filter by DocNum |
| `start_date_from` | string | Start date from (YYYY-MM-DD) |
| `start_date_to` | string | Start date to (YYYY-MM-DD) |
| `end_date_from` | string | End date from (YYYY-MM-DD) |
| `end_date_to` | string | End date to (YYYY-MM-DD) |
| `client_id` | integer | Filter by client ID |
| `cluster_id` | integer | Filter by internal cluster ID |
| `owner` | integer | Filter by owner employee number |
| `is_time_off` | string | `1` time-off only, `0` non-time-off only, omit for all |
| `tags` | string | Comma-separated tag IDs (e.g. `12,15`). Returns projects that have any of those tags or any of their descendant tags |

### Field Selection

| Parameter | Type | Description |
|-----------|------|-------------|
| `fields` | string | Comma-separated additional fields. Required fields, `is_time_off` and `block_date` are always included. |

### Available Additional Fields

`client_id`, `cluster_id`, `financial_project`, `reason`, `owner`, `owner_name`, `assistant`, `assistant_name`, `project_type`, `tipo_facturacion`, `itr_type`, `isico`, `ico_type`, `ico_docnum`, `expected_gp`, `sap_budget`, `ratecard_id`, `created_at`, `updated_at`, `end_date_sap`, `representation_letter`, `color`, `automatic_billing_schedule`, `tags`

`tags` returns the tags assigned to the project as a list of objects with `id`, `name`, `dimension_id`, `dimension_name`, `parent_id` and `path` (an empty list when the project has none).

Tags are hierarchical. `parent_id` is the ID of the parent tag (`null` for a root tag) and `path` is the full path from the dimension, e.g. `Tech > Cloud > AWS`. Only the tags directly assigned to the project are returned, not their ancestors: a project tagged `AWS` does not list `Cloud`. The `tags` filter works the other way round and includes descendants (filtering by `Cloud` also returns projects tagged `AWS`).

## Example Requests

```http
GET /api/projects
Authorization: Bearer YOUR_TOKEN_HERE
```

```http
GET /api/projects?page=1&per_page=20
Authorization: Bearer YOUR_TOKEN_HERE
```

```http
GET /api/projects?status=pst_Started&start_date_from=2023-01-01&client_id=789&is_time_off=1
Authorization: Bearer YOUR_TOKEN_HERE
```

```http
GET /api/projects?fields=client_id,cluster_id,owner_name,financial_project,tags
Authorization: Bearer YOUR_TOKEN_HERE
```

```http
GET /api/projects?tags=12,15&fields=tags
Authorization: Bearer YOUR_TOKEN_HERE
```

## Example Response

```json
{
  "projects": [
    {
      "name": "Digital Transformation Project",
      "sap_id": 12345,
      "doc_num": 67890,
      "start_date": "2023-01-01",
      "end_date": "2023-12-31",
      "status": "pst_Started",
      "is_time_off": false,
      "block_date": "2026-07-15",
      "client_id": 789,
      "cluster_id": 12,
      "owner_name": "John Doe",
      "financial_project": "FIN-001",
      "tags": [
        {
          "id": 12,
          "name": "AWS",
          "dimension_id": 3,
          "dimension_name": "Tech",
          "parent_id": 11,
          "path": "Tech > Cloud > AWS"
        }
      ]
    }
  ],
  "pagination": {
    "page": 1,
    "pages": 5,
    "per_page": 20,
    "total": 100,
    "has_next": true,
    "has_prev": false
  }
}
```

## Error Handling

| Status | Description |
|--------|-------------|
| 200 | Success |
| 401 | Unauthorized — missing or invalid token |
| 500 | Internal server error |

Example error:

```json
{
  "error": "Invalid or expired API token"
}
```
