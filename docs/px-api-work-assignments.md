# Work Assignments API

## Overview

The Work Assignments API returns the employee work assignment history: every row (current and past) linking an employee to a client, cluster or business unit. Access requires a service account.

**Endpoint:** `GET /api/work-assignments`  
**Authentication:** Bearer token (service account required)

## Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `employee_number` | integer | Filter by SAP employee number |
| `client_id` | integer | Assignments to that client |
| `cluster_id` | integer | Assignments to that cluster or to any client of its client groups |
| `business_unit_id` | integer | Assignments to that business unit, to its clusters, or to their clients |
| `start_date_from` | string | Earliest `effective_from`, inclusive (`YYYY-MM-DD`) |
| `start_date_to` | string | Latest `effective_from`, inclusive (`YYYY-MM-DD`) |

All filters are optional and combine with AND. If no parameters are provided, the whole history is returned. Invalid integers or dates, or `start_date_from` after `start_date_to`, return `400`.

## Response Fields

Each assignment includes: `id`, `employee_number`, `employee_name`, `target_type`, `source`, `effective_from`, `effective_to`, `is_current`, `client_id`, `client_name`, `client_group_id`, `client_group_name`, `cluster_id`, `cluster_name`, `business_unit_id`, `business_unit_name`, `total_hours`, `claim_days_count`, `computed_at`, `created_by`, `created_at`.

- `target_type` is `client`, `cluster` or `business_unit`; `source` is `automatic`, `manual` or `role`.
- `effective_to` is `null` (and `is_current` is `true`) for the assignment in force.
- The hierarchy fields are derived from the target: a client assignment also fills its client group, cluster and business unit; a cluster assignment fills the cluster and its business unit; fields above or beside the target are `null`.
- `total_hours`, `claim_days_count` and `computed_at` come from the automatic calculation and are `null` for other sources.

Results are ordered by `effective_from` descending, then `employee_number`.

## Example

```http
GET /api/work-assignments?employee_number=1234&start_date_from=2026-01-01
Authorization: Bearer YOUR_TOKEN_HERE
```

Response (200):

```json
{
  "work_assignments": [
    {
      "id": 57,
      "employee_number": 1234,
      "employee_name": "Jane Doe",
      "target_type": "cluster",
      "source": "automatic",
      "effective_from": "2026-09-01",
      "effective_to": null,
      "is_current": true,
      "client_id": null,
      "client_name": null,
      "client_group_id": null,
      "client_group_name": null,
      "cluster_id": 12,
      "cluster_name": "Banking",
      "business_unit_id": 3,
      "business_unit_name": "Financial Services",
      "total_hours": 812.5,
      "claim_days_count": 98,
      "computed_at": "2026-09-01T03:00:00",
      "created_by": 1,
      "created_at": "2026-09-01T03:00:00"
    }
  ],
  "total": 1
}
```
