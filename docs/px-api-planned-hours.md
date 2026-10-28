# Planned Hours API

## Overview

The Planned Hours API returns the hours planned for employees on projects, aggregated per employee, project and month. Access requires service account, admin, or business operations.

**Endpoint:** `GET /api/planned-hours`  
**Authentication:** Bearer token (service account required)

## Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `employee_number` | integer, list | Filter by SAP employee number(s) |
| `doc_num` | integer, list | Filter by project (`doc_num`, same as in the Projects API) |
| `months` | string (`YYYY-MM`), list | Filter by month(s) |

List parameters accept comma-separated values (`months=2026-03,2026-04`) or repeated parameters (`months=2026-03&months=2026-04`). Filters are combined with AND; omitted filters do not restrict the result. Invalid values return `400`.

## Response Fields

Each item includes: `employee_number`, `doc_num`, `project_name`, `month` (`YYYY-MM`), `hours`.

Hours are the sum of the planned hours of the employee on the project for that month. Results are ordered by `employee_number`, `doc_num` and `month`.

## Example

```http
GET /api/planned-hours?employee_number=10001&doc_num=12345&months=2026-03,2026-04
Authorization: Bearer YOUR_TOKEN_HERE
```

Response (200):

```json
{
  "planned_hours": [
    {
      "employee_number": 10001,
      "doc_num": 12345,
      "project_name": "Example Project",
      "month": "2026-03",
      "hours": 80.0
    },
    {
      "employee_number": 10001,
      "doc_num": 12345,
      "project_name": "Example Project",
      "month": "2026-04",
      "hours": 40.5
    }
  ],
  "total": 2
}
```
