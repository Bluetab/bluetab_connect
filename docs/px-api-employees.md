# Employees API

## Overview

The Employees API provides a RESTful endpoint for querying employee information. Access requires service account, admin, or business operations. Organizational hierarchy is available via the **Positions API**, not on employee records.

**Endpoint:** `GET /api/employees`  
**Authentication:** Bearer token (service account required)

## Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `employee_number` | integer | Filter by employee number |
| `email` | string | Filter by email |

If no parameters are provided, returns all employees.

## Response Fields

Each employee includes: `sap_employee_number`, `email`, `full_name`, `first_name`, `last_name`, `ssff_id`, `category`, `category_name`, `weekly_hours`, `hub`, `is_active`, `start_date`, `termination_date`.

**Removed:** `manager_employee_number`. Use the Positions API for reporting structure.

## Example

```http
GET /api/employees?employee_number=10001
Authorization: Bearer YOUR_TOKEN_HERE
```

Response (200):

```json
{
  "employees": [
    {
      "sap_employee_number": 10001,
      "email": "john@example.com",
      "full_name": "John Doe",
      "first_name": "John",
      "last_name": "Doe",
      "ssff_id": "SSFF001",
      "category": "CAT_A",
      "category_name": "Category A",
      "weekly_hours": 40,
      "hub": "Madrid",
      "is_active": true,
      "start_date": "2020-01-15",
      "termination_date": null
    }
  ],
  "total": 1
}
```
