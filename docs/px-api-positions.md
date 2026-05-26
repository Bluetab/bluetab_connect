# Positions API

## Overview

The Positions API provides read-only access to organizational positions, current reporting relationships between positions, and employees assigned to each position. Use this API for org structure; employee records no longer include hierarchy fields.

**Authentication:** Bearer token (service account required)

## Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/positions` | List positions with relationships and assigned employees |
| GET | `/api/positions/<id>` | Get position by ID |

## Query Parameters (`GET /api/positions`)

| Parameter | Type | Description |
|-----------|------|-------------|
| `position_id` | integer | Filter by position ID |
| `employee_number` | integer | Positions assigned to or default for this employee |
| `is_active` | boolean | Filter by active status (true/false) |
| `is_default` | boolean | Filter default vs non-default positions |

Relationships returned are current only (no historical end dates).

## Response Fields

**Position object:** `id`, `name`, `is_default`, `is_active`, `employee_number`, `default_for_employee_number`, `manager_position_id`, `assigned_employee`.

**assigned_employee** (when `employee_number` is set): `sap_employee_number`, `email`, `full_name`, `first_name`, `last_name`, `is_active`.

**Relationship object:** `position_id`, `manager_position_id` (null for root positions with an explicit no-manager row).

## Example

```http
GET /api/positions
Authorization: Bearer YOUR_TOKEN_HERE
```

Response (200):

```json
{
  "positions": [
    {
      "id": 10,
      "name": "Jane Doe",
      "is_default": true,
      "is_active": true,
      "employee_number": 10001,
      "default_for_employee_number": 10001,
      "manager_position_id": 5,
      "assigned_employee": {
        "sap_employee_number": 10001,
        "email": "jane@example.com",
        "full_name": "Jane Doe",
        "first_name": "Jane",
        "last_name": "Doe",
        "is_active": true
      }
    }
  ],
  "relationships": [
    {
      "position_id": 10,
      "manager_position_id": 5
    }
  ],
  "total_positions": 1,
  "total_relationships": 1
}
```
