# SMARTIFY — Master Grievance Routing Matrix

**Document Version:** 1.0.0 — Final Institutional Baseline  
**Project:** SMARTIFY (MCA Capstone Grievance Redressal System)  
**Database Authority:** Supabase PostgreSQL / Schema `public`  
**Security Boundary:** PostgreSQL Row Level Security (RLS) & Server Triggers  

---

## 1. Master Departmental Routing Matrix

| Department | Level 1 Authority (3 Days) | Level 2 Authority (4 Days) | Level 3 Authority (5 Days) | Level 4 Authority (5 Days) |
|---|---|---|---|---|
| **Hostel & Residential Life** (`HOSTEL`) | Hostel Warden / Block Supervisor | Head of Student Residences | Dean of Student Welfare / Grievance Cell | Arbitration Board / Principal |
| **Academic Affairs** (`ACADEMIC`) | Faculty Advisor / Department Officer | Head of Department (HoD) | Dean of Academic Affairs / Grievance Cell | Arbitration Board / Principal |
| **Infrastructure & Campus Facilities** (`INFRA`) | Campus Facilities Officer | Estate Officer / Chief Engineer | Dean of Infrastructure / Grievance Cell | Arbitration Board / Principal |
| **Accounts & Finance** (`FINANCE`) | Accounts Officer / Bursar | Finance Comptroller / HoD | Dean / Principal Review Cell | Arbitration Board / Principal |
| **Library & IT Services** (`IT_SERVICES`) | Systems Administrator / Librarian | Head of Digital Services | Dean / Grievance Cell | Arbitration Board / Principal |

---

## 2. Redressal Lifecycle & Actor Governance

### A. Who Can Submit?
- **Actor:** Any authenticated user with application role `STUDENT`.
- **Pre-Conditions:**
  1. Incident date must lie strictly within `[Current Date - 7 calendar days, Current Date]` (enforced via client `DateValidator` and server-authoritative trigger `trg_enforce_7_day_limit`).
  2. Required fields: Title (min 5 chars), Description (min 20 chars), Category, Department ID.
  3. Optional evidence: Image (JPG, PNG, WEBP) or PDF up to 10MB uploaded directly to private storage bucket `complaint-attachments`.
- **System Action upon Submission:**
  - Auto-generates unique tracking reference: `SMT-2026-XXXXX` via `generate_tracking_number()`.
  - Assigns initial status: `PENDING`.
  - Automatically initializes `current_authority_level_id` to Level 1.
  - Automatically computes initial `current_tier_deadline` (UTC now + Level 1 SLA days) and `cutoff_deadline` (UTC now + 20 calendar days).
  - Emits in-app student notification and immutable audit entry (`GRIEVANCE_SUBMITTED`).

---

### B. Who Can See?
- **Student Isolation:**
  - Enforced by PostgreSQL RLS Policy:
    ```sql
    CREATE POLICY "students_view_own" ON complaints
    FOR SELECT TO authenticated
    USING (student_id = auth.uid());
    ```
  - A student can **only** query and view their own grievances, status badges, timelines, and notifications.
  - Students **cannot** view complaints submitted by peers.
- **Authority Departmental Isolation:**
  - Enforced by PostgreSQL RLS Policy:
    ```sql
    CREATE POLICY "authority_view_queue" ON complaints
    FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'authority'
          AND p.is_active = true
          AND (
            -- Level 1 and 2 are strictly restricted to assigned department
            (p.authority_level_number IN (1, 2) AND complaints.department_id = p.department_id)
            -- Level 3 and 4 have institutional cross-department oversight
            OR p.authority_level_number >= 3
          )
      )
    );
    ```
  - Level 1 Hostel Warden sees **only** Hostel grievances.
  - Level 1 Academic Faculty Advisor sees **only** Academic grievances.
  - Cross-departmental viewing is strictly blocked at the database engine level.
- **Admin Visibility:**
  - Read access across grievances, SLA policies, staff assignments, and audit logs for centralized governance, cutoff management, and reporting.

---

### C. Who Can Act?
- **Permitted Operational Actors:** Active `AUTHORITY` users matching the grievance's active tier and department.
- **Permitted State Transitions:**
  - From `PENDING` ➔ `UNDER_REVIEW`, `REJECTED`.
  - From `UNDER_REVIEW` ➔ `IN_PROGRESS`, `ESCALATED` (Forwarded), `RESOLVED`, `REJECTED`.
  - From `IN_PROGRESS` ➔ `ESCALATED` (Forwarded), `RESOLVED`, `REJECTED`.
  - `RESOLVED` and `REJECTED` are strictly terminal.
  - Mandatory remarks are enforced before submission. Resolving requires a formal resolution memo.
- **Admin Operational Boundary:**
  - Admin is a **governance** actor, not a routine ticket approver.
  - Admin oversees staff roles, SLA policy limits, audit trails, and authorizes resumption for 20-day cutoff frozen grievances.

---

### D. What Causes Escalation?
1. **Automated SLA Timeout:**
   - If an operational tier fails to resolve or transition a grievance before `current_tier_deadline` (e.g. 3 days at Level 1, 4 days at Level 2, 5 days at Level 3), the grievance breaches SLA.
   - Escalation routine advances `current_authority_level_id` to the sequential tier (Level 1 ➔ Level 2 ➔ Level 3 ➔ Level 4).
   - Recalculates new tier deadline from the escalation timestamp.
   - Emits timeline node, audit event (`AUTOMATED_TIER_ESCALATION`), and student notification.
2. **Manual Forwarding by Authority:**
   - An authority can forward the grievance to the next tier with written justification before SLA expiry if higher administrative intervention is required.
3. **Apex Boundary:**
   - Level 4 is the apex arbitration tier. No further automated or manual escalation is permitted.

---

### E. What Happens at the 20-Day Cutoff?
- **Institutional Rule:** If any grievance remains unresolved after 20 calendar days from initial submission, automated escalation must freeze immediately.
- **System State:**
  - `status` set to `'CUTOFF_PAUSED'`.
  - `is_cutoff_paused` set to `true`.
  - Automated cron jobs and tier forwarding are locked out.
- **Administrative Governance:**
  - Grievance enters the Admin Cutoff Governance queue.
  - Campus Administrator reviews full timeline, departmental notes, and reasons for delay.
  - Admin issues authorized resumption with a mandatory formal justification memo (min 10 characters).
  - Status returns to `UNDER_REVIEW`, granting a refreshed 5-day handling buffer and extended cutoff.
  - Full audit record recorded: `RESUMPTION_AUTHORIZED`.

---

## 3. Verified Demo Accounts Matrix

| Name / Persona | Email | Password | Role | Department | Hierarchy Tier | Queue Scope |
|---|---|---|---|---|---|---|
| **Priya Sharma** | `student.demo@campus.edu` | *(configured in auth)* | `student` | *N/A* | *None* | Own submitted grievances only |
| **Hostel Warden** | `authority.demo@campus.edu` | *(configured in auth)* | `authority` | Hostel & Residential Life | Level 1: Faculty Advisor / Hostel Warden | Hostel grievances at Level 1 |
| **Prof. Suresh Kumar** | `faculty.demo@campus.edu` | *(configured in auth)* | `authority` | Academic Affairs | Level 1: Faculty Advisor / Hostel Warden | Academic grievances at Level 1 |
| **Dr. Ramanathan** | `hod.demo@campus.edu` | *(configured in auth)* | `authority` | Academic Affairs | Level 2: Head of Department | Academic grievances escalated to Level 2 |
| **Dr. Aris Thorne** | `dean.demo@campus.edu` | *(configured in auth)* | `authority` | Cross-department | Level 3: Dean of Student Welfare | Cross-department grievances at Level 3 |
| **Campus Administrator** | `admin.demo@campus.edu` | *(configured in auth)* | `admin` | Central Governance | *None* (authority_level_id = NULL) | Staff roles, SLA limits, Cutoff review, Audit & Analytics |
