# Absence Project Mappings API

## Overview

The Absence Project Mappings API returns the mapping between absence codes (SAP SuccessFactors time types) and projects, as configured in Operations > Absence Settings. Access requires a service account.

**Endpoint:** `GET /api/absence-project-mappings`  
**Authentication:** Bearer token (service account required)

## Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `only_mapped` | boolean | `true` returns only the codes that have a project assigned |
| `is_active` | boolean | Filter by the active flag of the time type (`true` / `false`) |

If no parameters are provided, all absence codes are returned, including those without a project. Invalid boolean values return `400`.

## Response Fields

Each mapping includes: `time_type_code`, `name_en`, `name_es`, `is_active`, `doc_num`, `project_name`, `representation_letter`, `color`, `counts_for_vacation_balance`.

`doc_num` is the project identifier (same value used by the Planned Hours API). `doc_num` and `project_name` are `null` when the absence code has no project assigned.

Results are ordered by `time_type_code` ascending.

## Example

```http
GET /api/absence-project-mappings?only_mapped=true
Authorization: Bearer YOUR_TOKEN_HERE
```

Response (200):

```json
{
  "mappings": [
    {
      "time_type_code": "VACATION",
      "name_en": "Vacation",
      "name_es": "Vacaciones",
      "is_active": true,
      "doc_num": 1234,
      "project_name": "Internal - Vacation",
      "representation_letter": "V",
      "color": "#3A86FF",
      "counts_for_vacation_balance": true
    }
  ],
  "total": 1
}
```
