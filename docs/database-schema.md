# SMARTIFY — Database Schema & Data Dictionary

---

## 1. Schema Overview

The database is built on PostgreSQL inside Supabase, enforcing sound relational normalization (3NF), foreign key referential integrity, and Row Level Security (RLS) across all tables.

### Tables Inventory

| Table Name | Description | RLS Enabled |
| :--- | :--- | :---: |
| `departments` | Campus academic, residential, and operational departments | Yes |
| `authority_levels` | Configurable multi-tier escalation hierarchy and SLAs | Yes |
| `profiles` | Extended user identity, role, and department associations | Yes |
| `complaints` | Core grievance records with tracking numbers and deadlines | Yes |
| `complaint_attachments` | Metadata for evidence files stored in private Supabase bucket | Yes |
| `complaint_escalations` | History of tier transitions, reasons, and elapsed days | Yes |
| `complaint_status_history` | Append-only audit trail of every status transition | Yes |
| `notifications` | In-app alerts for status changes and escalation events | Yes |
| `audit_logs` | Immutable system security and administrative action logs | Yes |

---

## 2. Table Specifications

### A. `departments`
* `id` (UUID, PK, `gen_random_uuid()`)
* `name` (TEXT, UNIQUE, NOT NULL): e.g., 'Academic Affairs', 'Hostel & Residential'
* `code` (TEXT, UNIQUE, NOT NULL): e.g., 'ACAD', 'HOSTEL'
* `description` (TEXT)
* `is_active` (BOOLEAN, NOT NULL, DEFAULT `true`)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### B. `authority_levels`
* `id` (UUID, PK, `gen_random_uuid()`)
* `level_number` (INT, UNIQUE, NOT NULL, CHECK `1 <= level_number <= 4`)
* `title` (TEXT, NOT NULL): e.g., 'Level 1: Faculty Advisor / Warden'
* `sla_days` (INT, NOT NULL, CHECK `sla_days > 0`)
* `can_resolve` (BOOLEAN, NOT NULL, DEFAULT `true`)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### C. `profiles`
* `id` (UUID, PK, FK `auth.users(id) ON DELETE CASCADE`)
* `email` (TEXT, UNIQUE, NOT NULL)
* `full_name` (TEXT, NOT NULL)
* `role` (`app_role` ENUM: `'student'`, `'authority'`, `'admin'`, DEFAULT `'student'`)
* `department_id` (UUID, FK `departments(id) ON DELETE SET NULL`)
* `authority_level_id` (UUID, FK `authority_levels(id) ON DELETE SET NULL`)
* `registration_number` (TEXT): Student Roll Number or Staff ID
* `phone` (TEXT)
* `avatar_url` (TEXT)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)
* `updated_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### D. `complaints`
* `id` (UUID, PK, `gen_random_uuid()`)
* `tracking_number` (TEXT, UNIQUE, NOT NULL): e.g., `SMT-2026-01001`
* `student_id` (UUID, NOT NULL, FK `profiles(id) ON DELETE CASCADE`)
* `department_id` (UUID, NOT NULL, FK `departments(id)`)
* `current_authority_level_id` (UUID, NOT NULL, FK `authority_levels(id)`)
* `assigned_authority_id` (UUID, FK `profiles(id) ON DELETE SET NULL`)
* `title` (TEXT, NOT NULL, CHECK `length(trim(title)) BETWEEN 5 AND 200`)
* `description` (TEXT, NOT NULL, CHECK `length(trim(description)) >= 20`)
* `category` (TEXT, NOT NULL)
* `incident_date` (DATE, NOT NULL): Validated strictly within `[CURRENT_DATE - 7 days, CURRENT_DATE]`
* `status` (`complaint_status` ENUM: `'PENDING'`, `'UNDER_REVIEW'`, `'IN_PROGRESS'`, `'ESCALATED'`, `'CUTOFF_PAUSED'`, `'RESOLVED'`, `'REJECTED'`)
* `priority` (`complaint_priority` ENUM: `'LOW'`, `'MEDIUM'`, `'HIGH'`, `'URGENT'`)
* `current_tier_deadline` (TIMESTAMPTZ, NOT NULL)
* `cutoff_deadline` (TIMESTAMPTZ, NOT NULL): Initialized to `created_at + INTERVAL '20 days'`
* `is_cutoff_paused` (BOOLEAN, NOT NULL, DEFAULT `false`)
* `paused_at` (TIMESTAMPTZ)
* `resumed_at` (TIMESTAMPTZ)
* `resumed_by` (UUID, FK `profiles(id)`)
* `resolution_notes` (TEXT)
* `resolved_at` (TIMESTAMPTZ)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)
* `updated_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### E. `complaint_attachments`
* `id` (UUID, PK, `gen_random_uuid()`)
* `complaint_id` (UUID, NOT NULL, FK `complaints(id) ON DELETE CASCADE`)
* `uploader_id` (UUID, NOT NULL, FK `profiles(id)`)
* `file_path` (TEXT, NOT NULL)
* `file_name` (TEXT, NOT NULL)
* `file_type` (TEXT, NOT NULL)
* `file_size_bytes` (BIGINT, NOT NULL, CHECK `file_size_bytes <= 10485760`)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### F. `complaint_escalations`
* `id` (UUID, PK, `gen_random_uuid()`)
* `complaint_id` (UUID, NOT NULL, FK `complaints(id) ON DELETE CASCADE`)
* `from_level_id` (UUID, NOT NULL, FK `authority_levels(id)`)
* `to_level_id` (UUID, NOT NULL, FK `authority_levels(id)`)
* `escalated_by` (UUID, FK `profiles(id) ON DELETE SET NULL`)
* `is_automated` (BOOLEAN, NOT NULL, DEFAULT `true`)
* `reason` (TEXT, NOT NULL)
* `tier_days_spent` (INT, NOT NULL, DEFAULT 0)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### G. `complaint_status_history`
* `id` (UUID, PK, `gen_random_uuid()`)
* `complaint_id` (UUID, NOT NULL, FK `complaints(id) ON DELETE CASCADE`)
* `changed_by` (UUID, FK `profiles(id) ON DELETE SET NULL`)
* `old_status` (`complaint_status`)
* `new_status` (`complaint_status`, NOT NULL)
* `remarks` (TEXT)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### H. `notifications`
* `id` (UUID, PK, `gen_random_uuid()`)
* `user_id` (UUID, NOT NULL, FK `profiles(id) ON DELETE CASCADE`)
* `complaint_id` (UUID, FK `complaints(id) ON DELETE CASCADE`)
* `title` (TEXT, NOT NULL)
* `message` (TEXT, NOT NULL)
* `notification_type` (`notification_type` ENUM)
* `is_read` (BOOLEAN, NOT NULL, DEFAULT `false`)
* `read_at` (TIMESTAMPTZ)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

### I. `audit_logs`
* `id` (UUID, PK, `gen_random_uuid()`)
* `actor_id` (UUID, FK `profiles(id) ON DELETE SET NULL`)
* `action` (TEXT, NOT NULL)
* `entity_type` (TEXT, NOT NULL)
* `entity_id` (UUID)
* `metadata` (JSONB, NOT NULL, DEFAULT `'{}'::jsonb`)
* `ip_address` (INET)
* `created_at` (TIMESTAMPTZ, NOT NULL, DEFAULT `now()`)

---

## 3. Server-Side Triggers & Automations

1. **`validate_complaint_incident_date` (BEFORE INSERT OR UPDATE):**
   * Verifies `incident_date` is strictly within `[CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE]`. Raises an exception if outside bounds.
2. **`initialize_complaint_defaults` (BEFORE INSERT):**
   * Generates sequential tracking number `SMT-YYYY-XXXXX`.
   * Calculates `current_tier_deadline` from Level 1 `sla_days`.
   * Sets immutable `cutoff_deadline = created_at + INTERVAL '20 days'`.
3. **`log_complaint_status_change` (AFTER INSERT OR UPDATE OF status):**
   * Inserts an immutable row in `complaint_status_history` whenever status changes.
4. **`protect_profile_privileged_fields` (BEFORE UPDATE):**
   * Prevents non-administrators from altering `role`, `department_id`, or `authority_level_id`.
5. **`handle_new_user` (AFTER INSERT on `auth.users`):**
   * Automatically creates user profile with role forced to `'student'`.
