# Employee Absences API

## Overview

The Employee Absences API provides a RESTful endpoint for querying approved employee absences synchronized from SAP SuccessFactors. Access requires service account, admin, or business operations.

**Endpoint:** `GET /api/employee-absences`  
**Authentication:** Bearer token (service account required)

## Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `employee_number` | integer | Filter by SAP employee number |
| `from_date` | string (`YYYY-MM-DD`) | Start of the search range |
| `to_date` | string (`YYYY-MM-DD`) | End of the search range |

Date filters use **overlap** semantics: an absence is included when it intersects the `[from_date, to_date]` range (`absence.start_date <= to_date` and `absence.end_date >= from_date`).

- Only `from_date`: absences with `end_date >= from_date`
- Only `to_date`: absences with `start_date <= to_date`
- No date filters: returns all absences
- If `from_date` is after `to_date`: `400` error
- Invalid date format: `400` error

## Response Fields

Each absence includes: `external_code`, `employee_number`, `ssff_user_id`, `time_type_code`, `time_type_name_en`, `time_type_name_es`, `start_date`, `end_date`, `quantity_in_days`, `quantity_in_hours`, `approval_status`.

Results are ordered by `start_date` descending, then `employee_number` ascending.

## Example

```http
GET /api/employee-absences?employee_number=10001&from_date=2026-01-01&to_date=2026-12-31
Authorization: Bearer YOUR_TOKEN_HERE
```

Response (200):

```json
{
  "absences": [
    {
      "external_code": "abs-1",
      "employee_number": 10001,
      "ssff_user_id": "SSFF001",
      "time_type_code": "VACATION",
      "time_type_name_en": "Vacation",
      "time_type_name_es": "Vacaciones",
      "start_date": "2026-03-10",
      "end_date": "2026-03-14",
      "quantity_in_days": 5.0,
      "quantity_in_hours": 0.0,
      "approval_status": "APPROVED"
    }
  ],
  "total": 1
}
```
