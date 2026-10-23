# SMARTIFY — Security Architecture & Guidelines

---

## 1. Core Security Tenets

1. **Defense-in-Depth:** Every security boundary is defended at the database level (PostgreSQL RLS, triggers, check constraints), storage level (Storage RLS), and client presentation level.
2. **Principle of Least Privilege:** Users receive strictly the permissions necessary for their assigned campus role (`student`, `authority`, `admin`).
3. **Server-Authoritative Authority:** Client device clocks and client payloads are never trusted for dates, status transitions, SLA calculations, or role assignments.
4. **Zero Production Secrets in Client Code:** No database credentials or service-role keys are ever packaged with the Flutter application, Android APK, or committed to Git.

---

## 2. Row Level Security (RLS) Policies

All 9 application tables have RLS explicitly enabled. Unauthenticated or public requests are completely rejected.

### Policy Enforcement Matrix

| Table | Student Permissions | Authority Permissions | Admin Permissions |
| :--- | :--- | :--- | :--- |
| `departments` | SELECT (active only) | SELECT (active only) | SELECT, INSERT, UPDATE, DELETE |
| `authority_levels` | SELECT (all) | SELECT (all) | SELECT, INSERT, UPDATE, DELETE |
| `profiles` | SELECT (self), UPDATE (personal info only) | SELECT (self & complainants) | Full SELECT, UPDATE |
| `complaints` | SELECT (own), INSERT (own, PENDING), UPDATE (own, PENDING only) | SELECT (dept/assigned queue), UPDATE (status, notes) | Full SELECT, UPDATE, DELETE |
| `complaint_attachments` | SELECT (own), INSERT (own) | SELECT (dept/assigned queue) | Full SELECT, DELETE |
| `complaint_escalations` | SELECT (own) | SELECT (dept), INSERT (escalate) | Full SELECT, INSERT |
| `complaint_status_history`| SELECT (own) | SELECT (dept), INSERT (via trigger) | Full SELECT |
| `notifications` | SELECT (own), UPDATE (own read status), DELETE (own) | SELECT (own), UPDATE (own read status) | Full SELECT |
| `audit_logs` | No Access | No Access | SELECT only (Append-only) |

---

## 3. Storage Security: `complaint-attachments` Bucket

* **Bucket Visibility:** Strictly private (`public = false`). Direct public URLs return HTTP 403 Forbidden.
* **MIME-Type Whitelist:** Only `image/jpeg`, `image/png`, `image/webp`, and `application/pdf` are accepted.
* **File Size Cap:** Enforced at 10MB per object on both client and storage policies.
* **Access Rules:**
  * Students can download only files associated with their own grievances.
  * Authorities can download only files for grievances assigned to their department or account.
  * Deletions are restricted exclusively to administrators.

---

## 4. Secret Management & Git Hygiene

* **Client Variables (Flutter App):**
  * `SUPABASE_URL`: Public Supabase project endpoint.
  * `SUPABASE_ANON_KEY`: Public client key. Safe for client distribution because RLS protects every database table.
* **Administrative Secrets (Server / Local Development Only):**
  * `DATABASE_URL`: Direct PostgreSQL connection string. Kept only in local `.env` for CLI migrations.
  * `SUPABASE_SERVICE_ROLE_KEY`: Service role token. Never imported into Dart code or client configurations.
* **Git Exclusions (`.gitignore`):**
  * `.env`, `.env.*` (with explicit exception for `.env.example`), `key.properties`, `*.jks`, `*.keystore`, and local IDE credential stores are permanently excluded from version control.
