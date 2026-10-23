# SMARTIFY — CRITICAL GRIEVANCE ROUTING & ACCOUNT LOGIC AUDIT REPORT

**Project:** `D:\work\SMARTIFY`  
**Audit Target:** End-to-End Grievance Routing, Account Model, Authority Queue, RLS Policies, SLA Escalation, and 20-Day Cutoff Logic  
**Date:** October 16, 2026  
**Auditor:** Antigravity Senior Systems Architect & Security QA Auditor  
**Status:** Audit Completed — **NO CODE CHANGES MADE**

---

## EXECUTIVE SUMMARY

A comprehensive architectural and code-level audit was conducted on the SMARTIFY MCA capstone grievance management system. The investigation examined the entire lifecycle of a grievance: student registration, database schema, trigger execution, Row Level Security (RLS) policies, authority queue fetching, detail screen inspection, status transitions, SLA forwarding, apex tier handling, and the 20-day cutoff freeze.

### Key Finding
**The grievance routing mechanism is partially broken in live production/demo environments due to department isolation, unassigned authority defaults, RLS level-agnostic policies, and identity conflation between System Administrators and Institutional Deans.**

1. **Non-Academic Grievances Fall into a Black Hole:** When a student submits a grievance under *Hostel & Residential Life*, *Campus Infrastructure*, *Accounts & Billing*, or *Library & IT Services*, the record is successfully written to PostgreSQL with `department_id = <dept_uuid>` and `assigned_authority_id = NULL`. However, because the sole demo authority account (`authority.demo@campus.edu`) is strictly assigned to `Academic Affairs`, Supabase RLS silently filters out all non-academic grievances. **No authority account exists in the demo setup to view or triage Hostel, Infrastructure, Finance, or IT grievances.**
2. **Authority Queues Ignore Authority Levels:** PostgreSQL RLS policies on `public.complaints` filter exclusively by `department_id = get_user_department_id()` and `assigned_authority_id = auth.uid()`. RLS **never** checks whether `current_authority_level_id` matches the authority's level. Consequently, a Level 1 Faculty Advisor in Academic Affairs can see, modify, and resolve grievances that have escalated to Level 2 (HoD), Level 3 (Dean), or Level 4 (Ombudsman).
3. **Institutional Escalations to Level 3 / Level 4 Fail Assignment:** The escalation engine (`process_daily_complaint_escalations`) attempts to assign escalated grievances using `WHERE department_id = v_complaint.department_id AND authority_level_id = v_next_level.id`. Because Deans (Level 3) and Ombudsmen (Level 4) are campus-wide institutional officers rather than departmental staff, this query returns `NULL` for all non-academic grievances.
4. **Admin and Dean Identities are Conflated:** The account `admin.demo@campus.edu` combines the `admin` application role with the `Level 3 (Dean)` authority tier. Because `app.dart` uses `role == 'admin'`, this user is directed to the Admin Governance Center (Staff Roles, Tier SLAs, Audit Trail, Cutoff Review) and **cannot access the Authority Redressal Queue (`AuthorityDashboardScreen`)** to triage grievances.
5. **Admin Has No All-Grievances Master Queue:** The system administrator has access to aggregated analytics and cutoff-paused complaints, but **SMARTIFY completely lacks an All-Grievances Master View or Search Queue for Administrators**.

---

## 1. CURRENT ACCOUNT STRUCTURE

SMARTIFY maintains a three-tiered relational identity model across PostgreSQL and Flutter. It is vital to distinguish between **Application Roles**, **Authority Levels**, and **Departments**:

```
+-----------------------------------------------------------------------------------+
|                                 APPLICATION ROLES                                 |
|                                (Enum: app_role)                                   |
|               +------------------+------------------+---------------+             |
|               |     student      |    authority     |     admin     |             |
|               +------------------+------------------+---------------+             |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+------------------------------------+       +--------------------------------------+
|            DEPARTMENTS             |       |           AUTHORITY LEVELS           |
|      (Table: public.departments)   |       |    (Table: public.authority_levels)  |
| +--------------------------------+ |       | +----------------------------------+ |
| | Academic Affairs (ACAD)        | |       | | Level 1: Faculty Advisor/Warden  | |
| | Hostel & Residential (HOSTEL)  | |       | | Level 2: Head of Department(HoD) | |
| | Infrastructure (INFRA)         | |       | | Level 3: Dean of Student Welfare | |
| | Accounts & Finance (FIN)       | |       | | Level 4: Principal / Ombudsman   | |
| | Library & IT Services (IT)     | |       | +----------------------------------+ |
| +--------------------------------+ |       +--------------------------------------+
+------------------------------------+
```

### A. Application Roles (Enum: `app_role`)
Defined in PostgreSQL (`supabase/migrations/20261012000001_core_schema.sql:9`):
- `student`: Standard campus user. Can submit grievances, upload evidence, track personal grievances, and view personal notifications. Cannot access authority queues or administrative settings.
- `authority`: Redressal officer. Can view department grievance queues, triage complaints, update statuses (`UNDER_REVIEW`, `IN_PROGRESS`, `RESOLVED`, `REJECTED`), forward to higher tiers, and access department analytics.
- `admin`: System governance administrator. Can manage user roles, configure tier SLA days, review immutable audit trails, access institutional analytics, and authorize the resumption of 20-day cutoff frozen grievances.

### B. Authority Levels (Table: `public.authority_levels`)
Defined in `supabase/migrations/20261012000001_core_schema.sql:60` and seeded in `20261012000003_storage_and_escalation_foundation.sql:17`:
- **Level 1:** `Faculty Advisor / Hostel Warden` (SLA: 3 calendar days, `can_resolve = true`)
- **Level 2:** `Head of Department (HoD)` (SLA: 4 calendar days, `can_resolve = true`)
- **Level 3:** `Dean of Student Welfare / Grievance Cell` (SLA: 5 calendar days, `can_resolve = true`)
- **Level 4:** `Principal / Campus Ombudsman Board` (SLA: 5 calendar days, `can_resolve = true`, Apex Tier)

### C. Departments (Table: `public.departments`)
Defined in `supabase/migrations/20261012000001_core_schema.sql:50` and seeded in `20261012000003_storage_and_escalation_foundation.sql:8`:
- `Academic Affairs` (Code: `ACAD`)
- `Hostel & Residential` (Code: `HOSTEL`)
- `Infrastructure & Campus Facilities` (Code: `INFRA`)
- `Accounts & Finance` (Code: `FIN`)
- `Library & IT Services` (Code: `IT`)

### D. Relational Profile Linkage (Table: `public.profiles`)
Every authenticated user in `auth.users` maps 1:1 to `public.profiles` (`20261012000001_core_schema.sql:70`):
- `role`: `app_role NOT NULL DEFAULT 'student'`
- `department_id`: `UUID REFERENCES public.departments(id) ON DELETE SET NULL`
- `authority_level_id`: `UUID REFERENCES public.authority_levels(id) ON DELETE SET NULL`

---

## 2. CURRENT DEMO ACCOUNTS

The application preconfigures three primary demo authentication chips on the login screen ([`lib/features/auth/screens/login_screen.dart:218-249`](file:///D:/work/SMARTIFY/lib/features/auth/screens/login_screen.dart#L218-L249)). In addition, mock profiles are defined in [`lib/features/admin/services/admin_service.dart:183-227`](file:///D:/work/SMARTIFY/lib/features/admin/services/admin_service.dart#L183-L227).

### Verified Demo Account Inventory

| Email / Identifier | Application Role | Department | Authority Level | Designation / Full Name | Usable in App? | Correctly Mapped to Scope? |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `student.demo@campus.edu` | `student` | `Academic Affairs` | `None` (`NULL`) | Aarav Patel (`MCA-2026-STU-042`) | **YES** | **YES**: Correctly restricted to personal complaints and tracking. |
| `authority.demo@campus.edu` | `authority` | `Academic Affairs` | `Level 1` (Faculty Advisor) | Prof. Suresh Kumar (`FAC-2026-ACAD-01`) | **YES** (Academic Only) | **PARTIAL / MISMATCHED SCOPE**: Mapped strictly to `Academic Affairs`. Cannot view or triage Hostel, Infrastructure, Finance, or IT grievances. |
| `admin.demo@campus.edu` | `admin` | `Academic Affairs` | `Level 3` (Dean of Student Welfare) | Dr. Aris Thorne (Dean) (`ADM-2026-DEAN-01`) | **YES** (Admin Only) | **INCOHERENT / MIXED IDENTITY**: Combines System Admin with Institutional Dean. Directed to Admin Governance Center; cannot access Authority Triage Queue. |

### Secondary Mock Profiles (Defined in `AdminService._getMockProfiles`)
These accounts appear in the Admin Staff Roles list when mock fallback activates, but **do not exist as accessible auth accounts** in the login UI:
- `dean.academic@campus.edu`: Role: `admin`, Dept: `Academic Affairs`, Level: `Level 3` (Dr. Aris Thorne)
- `suresh.hod@campus.edu`: Role: `authority`, Dept: `Academic Affairs`, Level: `Level 2` (Dr. Suresh Kumar)
- `warden.hostel@campus.edu`: Role: `authority`, Dept: `Hostel & Residential`, Level: `Level 1` (Prof. Ananya Sen)
- `aarav.student@campus.edu`: Role: `student`, Dept: `None`, Level: `None` (Aarav Patel)

---

## 3. CURRENT DEPARTMENTS

The PostgreSQL database initializes five operational campus departments (`supabase/migrations/20261012000003_storage_and_escalation_foundation.sql:8`):

```sql
INSERT INTO public.departments (name, code, description) VALUES
    ('Academic Affairs', 'ACAD', 'Curriculum, lectures, examinations, evaluation and faculty grievances'),
    ('Hostel & Residential', 'HOSTEL', 'Hostel accommodation, hygiene, mess food quality and warden concerns'),
    ('Infrastructure & Campus Facilities', 'INFRA', 'Classrooms, labs, water supply, electricity and campus upkeep'),
    ('Accounts & Finance', 'FIN', 'Tuition fees, scholarships, refunds and student billing'),
    ('Library & IT Services', 'IT', 'Campus Wi-Fi, computer labs, library books and digital portal access')
ON CONFLICT (code) DO NOTHING;
```

In the Flutter client ([`lib/features/complaints/models/complaint_category_model.dart`](file:///D:/work/SMARTIFY/lib/features/complaints/models/complaint_category_model.dart)), these five departments correspond directly to the five predefined student complaint categories:
1. **Academic Affairs** (`ACAD`): Class Scheduling, Examination & Hall Tickets, Evaluation & Grade Sheets, Curriculum & Syllabus, Faculty Interaction.
2. **Hostel & Residential Life** (`HOSTEL`): Room Allotment & Keys, Hostel Hygiene & Cleaning, Mess & Food Quality, Drinking Water Supply, Warden / Staff Behavior.
3. **Campus Infrastructure** (`INFRA`): Classroom Projectors & AV, Laboratory Equipment, Restrooms & Sanitation, Campus Lighting, Transport & Parking.
4. **Accounts & Billing** (`FIN`): Tuition Fee Receipts, Scholarship Disbursal, Caution Deposit Refund, Hostel Fee Reconciliation.
5. **Library & IT Services** (`IT`): Campus Wi-Fi Connectivity, Student Portal Login, Digital Library Access, Lab Computer Systems.

---

## 4. CURRENT AUTHORITY LEVELS

Defined in `supabase/migrations/20261012000003_storage_and_escalation_foundation.sql:17`:

```sql
INSERT INTO public.authority_levels (level_number, title, sla_days, can_resolve) VALUES
    (1, 'Level 1: Faculty Advisor / Hostel Warden', 3, true),
    (2, 'Level 2: Head of Department (HoD)', 4, true),
    (3, 'Level 3: Dean of Student Welfare / Grievance Cell', 5, true),
    (4, 'Level 4: Principal / Campus Ombudsman Board', 5, true)
ON CONFLICT (level_number) DO NOTHING;
```

### Authority Tier Specifications
- **Tier 1 (Level 1):** Frontline redressal. Faculty advisor for academic issues, hostel warden for residential life, facility engineer for infrastructure. Max initial resolution window: **3 calendar days**.
- **Tier 2 (Level 2):** Departmental leadership. Head of Department (HoD) or Chief Warden. Activated upon Tier 1 SLA breach or manual referral. Max resolution window: **4 calendar days**.
- **Tier 3 (Level 3):** Institutional executive. Dean of Student Welfare, Grievance Redressal Cell Chairman. Activated upon Tier 2 SLA breach or complex dispute. Max resolution window: **5 calendar days**.
- **Tier 4 (Level 4):** Apex institutional authority. Principal, Campus Ombudsman Board. Terminal internal appeal tier. Max resolution window: **5 calendar days**.
- **Can Resolve:** All four tiers have `can_resolve = true`. Any tier holding the grievance can mark it `RESOLVED` with mandatory resolution notes or `REJECTED` with a formal rejection memo.

---

## 5. STUDENT SUBMISSION FLOW

The complete path of a student grievance from form entry to database persistence was traced:

```
[Student UI: ComplaintRegistrationScreen]
                    |
                    v
[Provider: ComplaintSubmissionProvider]
   - Validates title (>= 5 chars) & description (>= 20 chars)
   - Enforces 7-calendar-day retrospective incident date constraint
   - Maps selected category title to defaultDepartmentCode (e.g., HOSTEL -> UUID)
                    |
                    v
[Service: ComplaintService.submitComplaint]
   - Fetches starting Level 1 authority UUID via fetchLevelOneAuthorityId()
   - Constructs insertPayload (assigned_authority_id is omitted / NULL)
   - Executes: client.from('complaints').insert(insertPayload).select().single()
                    |
                    v
[PostgreSQL Database Execution]
   1. trg_validate_complaint_incident_date: Verifies incident_date >= CURRENT_DATE - 7 days
   2. trg_initialize_complaint_defaults:
      - Generates tracking_number: 'SMT-YYYY-XXXXX' via sequence complaint_tracking_seq
      - Computes current_tier_deadline: now() + 3 days (Level 1 SLA)
      - Computes cutoff_deadline: now() + 20 days (Campus Cutoff)
   3. trg_log_complaint_status_change:
      - Inserts record into public.complaint_status_history (status: PENDING)
                    |
                    v
[Evidence Upload: _uploadAttachment (if provided)]
   - Uploads file to private storage bucket 'complaint-attachments' under {complaint_id}/{filename}
   - Inserts row into public.complaint_attachments
```

---

## 6. DATABASE FIELDS USED FOR ROUTING

The routing and filtering engine depends on eight specific columns in `public.complaints` ([`supabase/migrations/20261012000001_core_schema.sql:85-108`](file:///D:/work/SMARTIFY/supabase/migrations/20261012000001_core_schema.sql#L85-L108)):

1. `department_id` (`UUID NOT NULL REFERENCES departments(id)`):
   - **Primary Routing Key.** Designates the domain department (Academic, Hostel, Infra, Finance, IT).
   - Used by RLS policy: `c.department_id = public.get_user_department_id()`.
2. `current_authority_level_id` (`UUID NOT NULL REFERENCES authority_levels(id)`):
   - **Hierarchy Tier Key.** Indicates which tier currently owns the complaint (Level 1, 2, 3, or 4).
   - Incremented during SLA escalation (`level_number + 1`).
3. `assigned_authority_id` (`UUID REFERENCES profiles(id) ON DELETE SET NULL`):
   - **Specific Assignee Key.** User ID of the individual redressal officer.
   - **CRITICAL DEFECT:** Set to `NULL` upon student submission. When `NULL`, routing relies purely on `department_id`.
   - Updated to `auth.uid()` when an authority transitions the complaint to `UNDER_REVIEW`.
   - Cleared back to `NULL` when an authority uses `forwardToNextTier()`.
4. `status` (`complaint_status ENUM`):
   - Values: `PENDING`, `UNDER_REVIEW`, `IN_PROGRESS`, `ESCALATED`, `CUTOFF_PAUSED`, `RESOLVED`, `REJECTED`.
   - Filters the active triage queue in the client.
5. `current_tier_deadline` (`TIMESTAMPTZ NOT NULL`):
   - Active SLA deadline for the current tier.
   - Examined by `process_daily_complaint_escalations`: `WHERE v_now >= c.current_tier_deadline`.
6. `cutoff_deadline` (`TIMESTAMPTZ NOT NULL`):
   - Immutable campus cutoff: exactly `created_at + INTERVAL '20 days'`.
   - Examined by cutoff engine: `WHERE v_now >= c.cutoff_deadline`.
7. `is_cutoff_paused` (`BOOLEAN NOT NULL DEFAULT false`):
   - When `true`, locks the complaint from automated escalations and freezes all SLA timers.
8. `resumed_by` (`UUID REFERENCES profiles(id)`):
   - Records the administrative user who authorized resuming a frozen complaint.

---

## 7. AUTHORITY QUEUE QUERY

In [`lib/features/authority/services/authority_service.dart:30-46`](file:///D:/work/SMARTIFY/lib/features/authority/services/authority_service.dart#L30-L46), the authority queue query is executed as follows:

```dart
var query = client.from('complaints').select('''
  *,
  departments:department_id(name, code),
  authority_levels:current_authority_level_id(level_number, title, sla_days),
  student_profile:student_id(full_name),
  complaint_attachments(file_path)
''');

if (statusFilter != null && statusFilter != 'ALL') {
  query = query.eq('status', statusFilter);
}
if (priorityFilter != null && priorityFilter != 'ALL') {
  query = query.eq('priority', priorityFilter);
}

final response = await query.order('current_tier_deadline', ascending: true);
```

### Critical Architectural Observation
**The Dart client query contains NO `.eq('department_id', ...)` and NO `.eq('current_authority_level_id', ...)` filters.**
The client relies **entirely** on Supabase PostgreSQL Row Level Security (RLS) to restrict rows. If RLS allows a row, it appears in the queue; if RLS blocks a row, it vanishes silently.

---

## 8. RLS POLICIES

Row Level Security is defined in [`supabase/migrations/20261012000002_rls_and_security.sql:148-194`](file:///D:/work/SMARTIFY/supabase/migrations/20261012000002_rls_and_security.sql#L148-L194):

### A. Complaints SELECT Policy
```sql
CREATE POLICY "Students can view only their own complaints"
    ON public.complaints FOR SELECT
    TO authenticated
    USING (
        student_id = auth.uid()
        OR (
            public.is_authority() AND (
                department_id = public.get_user_department_id()
                OR assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    );
```

### B. Complaints UPDATE Policy
```sql
CREATE POLICY "Complaint update policy"
    ON public.complaints FOR UPDATE
    TO authenticated
    USING (
        (student_id = auth.uid() AND status = 'PENDING')
        OR (
            public.is_authority() AND (
                department_id = public.get_user_department_id()
                OR assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    )
    WITH CHECK (
        (student_id = auth.uid() AND status = 'PENDING')
        OR (
            public.is_authority() AND (
                department_id = public.get_user_department_id()
                OR assigned_authority_id = auth.uid()
                OR public.is_admin()
            )
        )
    );
```

### Security Definer Helper Functions
```sql
CREATE OR REPLACE FUNCTION public.is_authority()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role IN ('authority', 'admin')
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_user_department_id()
RETURNS UUID AS $$
    SELECT department_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

### Critical RLS Vulnerabilities & Flaws Identified

1. **Department Isolation Filter Blocks Unassigned Grievances of Other Departments:**
   - If a complaint has `department_id = Hostel` and `assigned_authority_id = NULL`:
   - An authority from `Academic Affairs` has `get_user_department_id() = Academic`.
   - Evaluation: `Hostel == Academic` (**FALSE**), `NULL == auth.uid()` (**FALSE**), `is_admin()` (**FALSE**).
   - **Result: RLS completely hides the grievance.**
2. **RLS Completely Omits Authority Level Scoping:**
   - Notice that the policy checks `department_id = get_user_department_id()`, but **does NOT check `current_authority_level_id`**.
   - An authority assigned to Level 1 in Academic Affairs can view and update grievances that have escalated to Level 2 (HoD), Level 3 (Dean), or Level 4 (Ombudsman) as long as they share the same department.
3. **Institutional Higher Tiers (Level 3 & 4) Blocked by Department Scope:**
   - Deans and Ombudsmen oversee all campus departments.
   - If a Dean has `role: 'authority'` and `department_id = Academic Affairs`, RLS blocks that Dean from seeing any Hostel, Infrastructure, Finance, or IT grievance, even when those grievances escalate to Level 3.

---

## 9. HOSTEL ROUTING TEST

**Scenario:** Student logs in → Submits grievance under "Hostel & Residential Life" (e.g. Mess hygiene issue) → Targets Hostel Warden Level 1.

| Step | Action | Expected State | Actual Database / Code State | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Student Submits Form | Form validated; category `HOSTEL` selected. | `ComplaintSubmissionProvider.selectCategory` sets `_departmentId = <HOSTEL_UUID>`. | **PASS** |
| 2 | Record Inserted | `complaints` row created with Level 1 tier. | Row inserted: `department_id = HOSTEL`, `current_authority_level_id = lvl-1`, `assigned_authority_id = NULL`. | **PASS** |
| 3 | Initial Assignment | Assigned to Hostel Warden Level 1. | `assigned_authority_id` remains `NULL`. System does not assign a warden user. | **DEFECT** |
| 4 | Authority Queue Query | Grievance visible in Hostel Warden queue. | `authority.demo@campus.edu` logs in. Account has `department_id = ACAD`. RLS evaluates `HOSTEL = ACAD` -> `FALSE`. Row is hidden. | **FAIL** |
| 5 | Demo Account Verification | Warden logs in to review. | **No Hostel Warden demo account exists.** Evaluator cannot log in as Hostel Warden. | **FAIL** |

**Conclusion:** **DOES NOT WORK.** The Hostel grievance is successfully stored in the database but is completely invisible to the available authority demo account and cannot be triaged without manual database manipulation.

---

## 10. ACADEMIC ROUTING TEST

**Scenario:** Student logs in → Submits grievance under "Academic Affairs" (e.g. Class scheduling conflict) → Targets Faculty Advisor Level 1.

| Step | Action | Expected State | Actual Database / Code State | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Student Submits Form | Category `ACAD` selected. | `_departmentId` set to `ACAD` UUID. | **PASS** |
| 2 | Record Inserted | `complaints` row created. | Row inserted: `department_id = ACAD`, `current_authority_level_id = lvl-1`, `assigned_authority_id = NULL`. | **PASS** |
| 3 | Authority Queue Query | Appears in Academic Authority queue. | `authority.demo@campus.edu` logs in (`department_id = ACAD`). RLS evaluates `ACAD = ACAD` -> `TRUE`. Row appears in Triage Queue. | **PASS** |
| 4 | Triage Action | Authority opens triage dialog. | Taps "TRIAGE ACTION" -> Selects "Under Review" -> `AuthorityService.updateStatus` sets `assigned_authority_id = currentUser.id`. | **PASS** |
| 5 | Resolution | Authority resolves grievance. | Taps "TRIAGE ACTION" -> Selects "Resolved" with notes -> Status updated to `RESOLVED`, `resolved_at` stamped. | **PASS** |

**Conclusion:** **WORKS FOR LEVEL 1 ACADEMIC GRIEVANCES.** This is the single routing pathway fully supported by the existing demo account configuration.

---

## 11. INFRASTRUCTURE ROUTING TEST

**Scenario:** Student logs in → Submits grievance under "Campus Infrastructure" (e.g. Projector failure in Lab 3) → Targets Infrastructure Level 1.

| Step | Action | Expected State | Actual Database / Code State | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Student Submits Form | Category `INFRA` selected. | `_departmentId` set to `INFRA` UUID. | **PASS** |
| 2 | Record Inserted | `complaints` row created. | Row inserted: `department_id = INFRA`, `current_authority_level_id = lvl-1`, `assigned_authority_id = NULL`. | **PASS** |
| 3 | Authority Queue Query | Appears in Infra Authority queue. | `authority.demo@campus.edu` has `department_id = ACAD`. Blocked by RLS (`INFRA = ACAD` -> `FALSE`). | **FAIL** |
| 4 | Demo Account Verification | Infrastructure Officer logs in. | **No Infrastructure demo account exists.** | **FAIL** |

**Conclusion:** **DOES NOT WORK.** Stored in database but invisible to existing authority account.

---

## 12. IT/LIBRARY ROUTING TEST

**Scenario:** Student logs in → Submits grievance under "Library & IT Services" (e.g. Campus Wi-Fi outage) → Targets IT Officer Level 1.

| Step | Action | Expected State | Actual Database / Code State | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Student Submits Form | Category `IT` selected. | `_departmentId` set to `IT` UUID. | **PASS** |
| 2 | Record Inserted | `complaints` row created. | Row inserted: `department_id = IT`, `current_authority_level_id = lvl-1`, `assigned_authority_id = NULL`. | **PASS** |
| 3 | Authority Queue Query | Appears in IT Authority queue. | `authority.demo@campus.edu` has `department_id = ACAD`. Blocked by RLS (`IT = ACAD` -> `FALSE`). | **FAIL** |
| 4 | Demo Account Verification | IT Officer logs in. | **No IT / Library demo account exists.** | **FAIL** |

**Conclusion:** **DOES NOT WORK.** Stored in database but invisible to existing authority account.

---

## 13. SLA ESCALATION FLOW

Automated SLA monitoring and tier forwarding are governed by `process_daily_complaint_escalations(p_simulated_now)` in [`supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql:150-335`](file:///D:/work/SMARTIFY/supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql#L150-L335).

### Execution Mechanism
1. The engine iterates over overdue complaints:
   ```sql
   WHERE v_now >= c.current_tier_deadline
     AND c.status IN ('PENDING', 'UNDER_REVIEW', 'IN_PROGRESS', 'ESCALATED')
     AND c.is_cutoff_paused = false
   ORDER BY c.current_tier_deadline ASC
   FOR UPDATE SKIP LOCKED;
   ```
2. Finds next level:
   ```sql
   SELECT id, level_number, title, sla_days INTO v_next_level
   FROM public.authority_levels
   WHERE level_number = v_complaint.current_level_number + 1;
   ```
3. Searches for next authority:
   ```sql
   SELECT id, full_name INTO v_next_authority
   FROM public.profiles
   WHERE department_id = v_complaint.department_id
     AND authority_level_id = v_next_level.id
     AND role IN ('authority', 'admin')
   LIMIT 1;
   ```
4. Updates complaint row:
   ```sql
   UPDATE public.complaints
   SET current_authority_level_id = v_next_level.id,
       assigned_authority_id = v_next_authority.id,
       status = 'ESCALATED',
       current_tier_deadline = v_now + (v_next_level.sla_days || ' days')::INTERVAL,
       updated_at = v_now
   WHERE id = v_complaint.id;
   ```

### Trace: Academic Level 1 SLA Expiry → Level 2 (HoD)
- Starting state: Academic grievance at Level 1 breaches 3-day SLA.
- Escalation engine executes: Next level is Level 2 (`sla_days = 4`).
- Query for next authority: Looks for `department_id = ACAD` AND `authority_level_id = Level 2`.
- **Finding:** No profile in the demo database has `authority_level_id = Level 2`. `v_next_authority.id` evaluates to `NULL`.
- Database update: `current_authority_level_id` is set to Level 2, `assigned_authority_id` is set to `NULL`, `status` is set to `ESCALATED`.
- Queue visibility: `authority.demo@campus.edu` (Level 1 Faculty Advisor) **can still see and resolve the complaint** because RLS checks only `department_id = ACAD`, not `authority_level_id`! No separate HoD login exists.

### Trace: Level 2 SLA Expiry → Level 3 (Dean)
- Starting state: Complaint at Level 2 breaches 4-day SLA.
- Escalation engine executes: Next level is Level 3 (`sla_days = 5`).
- Query for next authority: Looks for `department_id = v_complaint.department_id` AND `authority_level_id = Level 3`.
- **For Academic complaints:** Matches `admin.demo@campus.edu` (Dr. Aris Thorne, who has `department_id = ACAD` and `authority_level_id = Level 3`). `assigned_authority_id` is set to Dr. Thorne's ID.
  - **DEFECT:** Dr. Thorne has `role: admin`. When Dr. Thorne logs in, `app.dart` directs them to the Admin Governance Center. They cannot access the Authority Triage Queue to act as a Level 3 Dean!
- **For Non-Academic complaints (Hostel, Infra, etc.):** Dr. Thorne's department is `Academic Affairs`. The query searches for `department_id = Hostel` AND `authority_level_id = Level 3`. **None exists.** `assigned_authority_id` remains `NULL`. Under RLS, because `department_id = Hostel` and `assigned_authority_id` is `NULL`, no authority (including Dr. Thorne) can see the grievance!

### Trace: Level 3 SLA Expiry → Level 4 (Ombudsman)
- Starting state: Complaint at Level 3 breaches 5-day SLA.
- Escalation engine executes: Next level is Level 4 (`sla_days = 5`).
- Query for next authority: Looks for `department_id = v_complaint.department_id` AND `authority_level_id = Level 4`.
- **Finding:** No account exists with `authority_level_id = Level 4`. `assigned_authority_id` remains `NULL`. Grievance is updated to Level 4, but cannot be seen or acted on by any dedicated Level 4 user.

### Trace: Level 4 SLA Expiry (Apex Level Reached)
- When Level 4 breaches its 5-day SLA, `v_next_level` is `NOT FOUND` (`level_number = 5` does not exist).
- The engine executes the `ELSE` branch:
  - Does NOT crash or corrupt state.
  - Inserts `APEX_TIER_SLA_BREACHED` into `public.audit_logs`.
  - Dispatches high-priority notifications to all campus administrators (`role = 'admin'`).
  - Leaves the complaint at Level 4 pending administrative intervention.

---

## 14. 20-DAY CUTOFF FLOW

The 20-day cutoff is an MCA project-mandated governance rule: regardless of tier or status, any unresolved grievance reaching 20 calendar days from creation must automatically freeze, locking out cron jobs.

```
+-----------------------------------------------------------------------------------+
|               AUTOMATED 20-DAY CUTOFF FREEZE & ADMINISTRATIVE RESUMPTION          |
+-----------------------------------------------------------------------------------+
  c.cutoff_deadline <= now()
              |
              v
  [process_daily_complaint_escalations (Step 1)]
      - UPDATE public.complaints:
          status = 'CUTOFF_PAUSED'
          is_cutoff_paused = true
          paused_at = now()
      - INSERT INTO public.complaint_status_history ('CUTOFF_PAUSED')
      - INSERT INTO public.audit_logs ('CUTOFF_LIMIT_REACHED')
      - Dispatch notifications to Student, Assigned Authority, and Admins
              |
              v
  [Grievance Frozen: Automated Escalation Locked Out]
              |
              v
  [Admin Portal: AdminCutoffReviewScreen]
      - Administrator inspects frozen grievance (e.g. SMT-2026-PAUSED)
      - Taps "AUTHORIZE RESUMPTION"
      - Enters mandatory audit notes (>= 10 characters)
              |
              v
  [Database RPC: resume_paused_complaint]
      - Validates public.is_admin()
      - UPDATE public.complaints:
          status = 'UNDER_REVIEW'
          is_cutoff_paused = false
          resumed_at = now()
          resumed_by = auth.uid()
          current_tier_deadline = now() + (sla_days || ' days')::INTERVAL
          cutoff_deadline = now() + INTERVAL '20 days'
      - Records immutable status history and audit log entry
```

### Trace Verification
1. **Precedence Over SLA Forwarding:** In `process_daily_complaint_escalations`, Step 1 (Cutoff Freeze) executes **before** Step 2 (Tier SLA Forwarding). A complaint that has reached 20 days is immediately paused; it is never forwarded to another tier.
2. **Resumption RPC Check:** In [`supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql:348-425`](file:///D:/work/SMARTIFY/supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql#L348-L425), `resume_paused_complaint()` successfully resets `is_cutoff_paused = false`, updates `status = 'UNDER_REVIEW'`, grants a fresh tier SLA deadline, and extends `cutoff_deadline` by an additional 20 days.
3. **Flaw:** The function checks `IF NOT public.is_admin()`. If a Dean is properly configured with `role: 'authority'` and `authority_level: 3`, the Dean is blocked from executing `resume_paused_complaint`.

---

## 15. ADMIN VISIBILITY

### A. RLS Privileges
Under the PostgreSQL RLS policy on `public.complaints`:
```sql
public.is_authority() AND (
    department_id = public.get_user_department_id()
    OR assigned_authority_id = auth.uid()
    OR public.is_admin()
)
```
Because `public.is_admin()` evaluates to `TRUE` for users with `role = 'admin'`, **PostgreSQL allows an administrator to SELECT and UPDATE every complaint in the entire database**, across all departments, all tiers, and all statuses.

### B. Actual Flutter Application UI Visibility
In [`lib/app.dart:79-112`](file:///D:/work/SMARTIFY/lib/app.dart#L79-L112), logging in as `admin.demo@campus.edu` renders a bottom navigation bar with five destinations:
1. **Admin** (`AdminControlCenterScreen`): Staff Roles tab, Tier SLAs tab, Audit Trail tab.
2. **Cutoff** (`AdminCutoffReviewScreen`): Queries `complaints` where `status = 'CUTOFF_PAUSED' OR is_cutoff_paused = true`. Shows frozen complaints and resumption dialog.
3. **Analytics** (`AnalyticsDashboardScreen`): Calls RPC `get_grievance_analytics`. Displays aggregate charts and metrics.
4. **Alerts** (`NotificationsScreen`): In-app notifications for the admin user.
5. **Profile** (`ProfileScreen`): Administrator profile details and sign out.

### Critical Finding: Admin Has NO All-Grievances View
**SMARTIFY DOES NOT HAVE AN ALL-GRIEVANCES VIEW OR SEARCH QUEUE FOR ADMINISTRATORS.**
An administrator cannot:
- View active grievances in `PENDING`, `UNDER_REVIEW`, `IN_PROGRESS`, or `ESCALATED` status.
- Search for a grievance by tracking number (e.g. `SMT-2026-01005`) unless it happens to be cutoff-paused.
- View grievance details, complainant details, or attachments for general complaints.
**This is an exact missing feature, not an existing capability.**

---

## 16. WHY EXISTING GRIEVANCES MAY NOT APPEAR

During previous testing passes, synthetic grievances created by students were reported missing from the Authority queue. The audit traced five root causes:

1. **Department Isolation Filter in RLS (Primary Cause):**
   When an evaluator uses the Student profile to submit a "Hostel" or "Infrastructure" grievance, the row receives `department_id = <HOSTEL_UUID>`. When the evaluator subsequently logs in with `authority.demo@campus.edu`, that account is bound to `Academic Affairs`. The RLS policy evaluates `department_id = get_user_department_id()` (`Hostel == Academic` -> `FALSE`). The row is filtered out by PostgreSQL.
2. **Unassigned Authority Intake Default:**
   Student submissions do not assign an individual authority (`assigned_authority_id = NULL`). Therefore, the secondary RLS check `assigned_authority_id = auth.uid()` also evaluates to `FALSE`.
3. **Client-Side Chip Filter Default:**
   In `AuthorityDashboardScreen`, horizontal filter chips allow selecting "All Active", "Pending Intake", and "Under Review". If a synthetic grievance was transitioned to `RESOLVED` or `REJECTED`, selecting "Pending Intake" or "Under Review" filters it out.
4. **Mock Data Fallback on Auth/Network Error:**
   In `AuthorityService.fetchAuthorityQueue()` ([`lib/features/authority/services/authority_service.dart:54-64`](file:///D:/work/SMARTIFY/lib/features/authority/services/authority_service.dart#L54-L64)), if an unauthenticated session or query exception occurs, the service catches the exception and falls back to `_mockAuthorityQueue` (`SMT-2026-01001`, `SMT-2026-01044`). In that state, live database grievances are completely replaced by mock records.
5. **Level 3 Escalation Vanishing:**
   When an Academic grievance escalates to Level 3, it is assigned to `admin.demo@campus.edu`. Because `admin.demo` cannot open `AuthorityDashboardScreen`, the grievance disappears from `authority.demo`'s queue and cannot be viewed in any authority queue.

---

## 17. EXACT LOGIC BUGS

### BUG-001: Escalation Engine Queries Department-Bound Profile for Institutional Levels
- **File:** `supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql`
- **Function/Query:** `process_daily_complaint_escalations()`, lines 185–190:
  ```sql
  SELECT id, full_name INTO v_next_authority
  FROM public.profiles
  WHERE department_id = v_complaint.department_id
    AND authority_level_id = v_next_level.id
    AND role IN ('authority', 'admin')
  LIMIT 1;
  ```
- **Current Behavior:** Institutional tiers (Level 3 Dean, Level 4 Ombudsman) are campus-wide positions. Because profiles are assigned to a single department (e.g. `Academic Affairs`), when a Hostel or Infrastructure grievance escalates to Level 3 or 4, this query returns `NULL`. The grievance remains unassigned.
- **Expected Behavior:** Institutional tiers (Levels 3 & 4) must match campus-wide officers regardless of department (e.g. `WHERE (department_id = v_complaint.department_id OR department_id IS NULL OR v_next_level.level_number >= 3)`).
- **Severity:** **CRITICAL**
- **Recommended Fix:** Update the query in `process_daily_complaint_escalations()` to allow Level 3 and 4 officers to hold a `NULL` department representing campus-wide jurisdiction, and search for them across all departments.

---

### BUG-002: RLS Policies Do Not Enforce Authority Level Scoping
- **File:** `supabase/migrations/20261012000002_rls_and_security.sql`
- **Policy:** `"Students can view only their own complaints"` (lines 148–160) and `"Complaint update policy"` (lines 170–194)
- **Current Behavior:** The `USING` clause checks:
  ```sql
  c.department_id = public.get_user_department_id() 
  OR c.assigned_authority_id = auth.uid() 
  OR public.is_admin()
  ```
  It **never checks `c.current_authority_level_id`**. A Level 1 Faculty Advisor can view, update, and resolve grievances that have escalated to Level 2 (HoD), Level 3 (Dean), or Level 4 (Ombudsman).
- **Expected Behavior:** Authority users should only be permitted to view and update complaints matching their configured tier (`c.current_authority_level_id = (SELECT authority_level_id FROM public.profiles WHERE id = auth.uid())`), or complaints explicitly assigned to them.
- **Severity:** **HIGH**
- **Recommended Fix:** Update RLS select and update policies on `public.complaints` to enforce authority level matching.

---

### BUG-003: Student Submission Omits Authority Assignment
- **File:** [`lib/features/complaints/services/complaint_service.dart:95-105`](file:///D:/work/SMARTIFY/lib/features/complaints/services/complaint_service.dart#L95-L105) & `supabase/migrations/20261012000001_core_schema.sql:217-245`
- **Function:** `submitComplaint()` & `initialize_complaint_defaults()`
- **Current Behavior:** `insertPayload` does not include `assigned_authority_id`. The database trigger also does not assign a default Level 1 officer. The complaint sits in an unassigned department pool with `assigned_authority_id = NULL`.
- **Expected Behavior:** The database trigger `initialize_complaint_defaults()` should automatically assign an active Level 1 authority in that department (or round-robin), or the UI must provide a formal "Claim Grievance" intake workflow.
- **Severity:** **HIGH**
- **Recommended Fix:** In `initialize_complaint_defaults()`, query `public.profiles` for an active Level 1 authority in `NEW.department_id` and set `NEW.assigned_authority_id = v_l1_authority_id`.

---

### BUG-004: Authority Forwarding Clears Assignee, Breaking Cross-Department Higher Tiers
- **File:** [`lib/features/authority/services/authority_service.dart:167-173`](file:///D:/work/SMARTIFY/lib/features/authority/services/authority_service.dart#L167-L173)
- **Function:** `forwardToNextTier()`
- **Current Behavior:** When an authority manually forwards a complaint to the next tier, it executes:
  ```dart
  'assigned_authority_id': null, // Open for next level triage
  ```
  Because `assigned_authority_id` becomes `NULL`, higher-tier officers outside that department (e.g. Dean of Student Welfare) are blocked by RLS from accessing the forwarded grievance.
- **Expected Behavior:** Forwarding should identify the next tier's designated authority and assign them, or RLS must allow higher tiers campus-wide visibility.
- **Severity:** **HIGH**
- **Recommended Fix:** Update `forwardToNextTier` to resolve and assign the next tier's authority, and update RLS to grant Level 3/4 authorities access across all departments.

---

### BUG-005: Conflation of System Admin and Dean Identities
- **File:** [`lib/app.dart:79-112`](file:///D:/work/SMARTIFY/lib/app.dart#L79-L112), [`lib/features/auth/services/auth_service.dart:163-180`](file:///D:/work/SMARTIFY/lib/features/auth/services/auth_service.dart#L163-L180), `supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql:363-367`
- **Location:** Portal routing shell and demo profile modeling
- **Current Behavior:** `admin.demo@campus.edu` is modeled as `role: 'admin'` and `authority_level: 'Level 3 (Dean)'`. In `app.dart`, `role == 'admin'` routes exclusively to Admin Governance screens. The Dean cannot open `AuthorityDashboardScreen` to triage Level 3 complaints.
- **Expected Behavior:** Clean architectural separation: System Admin is `role: 'admin'` (system maintenance). Dean is `role: 'authority'` with `authority_level_id = Level 3` (grievance redressal).
- **Severity:** **HIGH**
- **Recommended Fix:** Introduce a separate `dean.demo@campus.edu` account (`role: 'authority'`, `authority_level = 3`, campus-wide), leaving `admin.demo@campus.edu` as pure system administration.

---

### BUG-006: Cutoff Resumption RPC Requires `is_admin()`, Locking Out Deans
- **File:** `supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql`
- **Function:** `resume_paused_complaint()`, lines 363–367:
  ```sql
  IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'Unauthorized: Only an administrator or designated Dean can resume a paused grievance.';
  END IF;
  ```
- **Current Behavior:** Although documentation states Deans can authorize resumption, the SQL check strictly enforces `public.is_admin()`. A Dean modeled as `role: 'authority'` cannot execute resumption.
- **Expected Behavior:** The function should allow administrators AND Level 3/4 authorities:
  ```sql
  IF NOT (public.is_admin() OR (SELECT level_number FROM public.authority_levels WHERE id = (SELECT authority_level_id FROM public.profiles WHERE id = auth.uid())) >= 3) THEN
  ```
- **Severity:** **MEDIUM**
- **Recommended Fix:** Expand the permission check in `resume_paused_complaint()` to include Level 3 and Level 4 authorities.

---

## 18. EXACT MISSING FEATURES

1. **Admin Master Grievances Queue / Search View:**
   The admin portal has tabs for Staff Roles, Tier SLAs, Audit Trail, Cutoff Review, and Analytics. It **completely lacks an All-Grievances Triage/Search Queue** where an administrator can view all active complaints across the campus.
2. **Department Authority Demo Accounts:**
   The application only includes one authority login (`authority.demo@campus.edu` in Academic Affairs). It lacks demo accounts for:
   - Hostel Warden (Hostel Level 1)
   - Infrastructure Officer (Infra Level 1)
   - Finance / Accounts Officer (Finance Level 1)
   - IT Services Officer (IT Level 1)
   - Head of Department (Academic Level 2)
   - Principal / Campus Ombudsman (Level 4 Apex)
3. **Campus-Wide Multi-Department Authority Jurisdiction:**
   The `profiles.department_id` column is a mandatory single foreign key. SMARTIFY lacks support for campus-wide authorities (Dean, Principal, Ombudsman) who have jurisdiction over all departments.
4. **Authority "Claim Grievance" / Self-Assignment Button:**
   Because complaints are created with `assigned_authority_id = NULL`, frontline authorities need an explicit "Claim Grievance" button on unassigned cards in `AuthorityDashboardScreen`.

---

## 19. RECOMMENDED ACCOUNT STRUCTURE

To fully support end-to-end multi-department routing, SLA escalations, and role-based testing, the demo setup should be expanded to the following clean structure:

| Email / Identifier | Application Role | Department Scope | Authority Level | Designation | Usability Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `student.demo@campus.edu` | `student` | `Academic Affairs` | `None` | Aarav Patel (Student) | Submit complaints, upload evidence, track status, view notifications. |
| `faculty.demo@campus.edu` | `authority` | `Academic Affairs` | `Level 1` | Prof. Suresh Kumar (Faculty Advisor) | Triage frontline Academic grievances (3-day SLA). |
| `warden.demo@campus.edu` | `authority` | `Hostel & Residential` | `Level 1` | Prof. Ananya Sen (Hostel Warden) | Triage frontline Hostel grievances (3-day SLA). |
| `infra.demo@campus.edu` | `authority` | `Campus Infrastructure` | `Level 1` | Er. Rajesh Sharma (Facilities Engineer) | Triage frontline Infrastructure grievances (3-day SLA). |
| `it.demo@campus.edu` | `authority` | `Library & IT Services` | `Level 1` | Smt. Priya Nair (Systems Admin) | Triage frontline IT & Wi-Fi grievances (3-day SLA). |
| `hod.demo@campus.edu` | `authority` | `Academic Affairs` | `Level 2` | Dr. Vikram Malhotra (Head of Dept) | Triage escalated Academic grievances (4-day SLA). |
| `dean.demo@campus.edu` | `authority` | `Campus-Wide` (`NULL`) | `Level 3` | Dr. Aris Thorne (Dean of Students) | Triage Level 3 escalated grievances across all departments (5-day SLA); authorize cutoff resumptions. |
| `ombudsman.demo@campus.edu` | `authority` | `Campus-Wide` (`NULL`) | `Level 4` | Prof. K. R. Narayanan (Principal) | Apex institutional review for Level 4 grievances (5-day SLA). |
| `admin.demo@campus.edu` | `admin` | `System-Wide` | `None` | Institutional IT Administrator | Manage user roles, configure SLAs, inspect audit logs, review cutoff grievances, view master analytics. |

---

## 20. RECOMMENDED END-TO-END FLOW

```
1. STUDENT SUBMISSION:
   Student logs in (student.demo) -> Selects Category (e.g. Hostel & Residential)
   -> Form auto-resolves Department UUID (HOSTEL)
   -> ComplaintService.submitComplaint inserts row into public.complaints:
        department_id = HOSTEL
        current_authority_level_id = Level 1 (3-day SLA)
        assigned_authority_id = warden.demo user ID (auto-assigned by trigger)
        status = 'PENDING'
        current_tier_deadline = now() + 3 days
        cutoff_deadline = now() + 20 days

2. LEVEL 1 TRIAGE:
   Hostel Warden logs in (warden.demo) -> Opens Authority Redressal Queue
   -> RLS permits viewing (department_id = HOSTEL and authority_level = Level 1)
   -> Warden clicks "TRIAGE ACTION" -> Selects "Under Review" (status = 'UNDER_REVIEW')
   -> If resolved: Enters resolution notes -> Status updated to 'RESOLVED' (Terminal)
   -> If unresolved within 3 days: SLA expires -> Proceed to Step 3.

3. LEVEL 1 -> LEVEL 2 ESCALATION:
   process_daily_complaint_escalations runs (simulated or cron)
   -> Detects now() >= current_tier_deadline and status != 'RESOLVED'
   -> Finds Level 2 (HoD / Chief Warden, 4-day SLA)
   -> Assigns Level 2 authority for Hostel department
   -> Updates status = 'ESCALATED', current_tier_deadline = now() + 4 days
   -> Inserts complaint_escalations and audit_logs records
   -> Sends notifications to Student, Level 1 Warden, and Level 2 Chief Warden.

4. LEVEL 2 -> LEVEL 3 ESCALATION:
   If Level 2 SLA expires (4 days) without resolution:
   -> Engine forwards to Level 3 (Dean of Student Welfare, 5-day SLA)
   -> Assigns dean.demo (Campus-Wide Level 3 officer)
   -> Updates status = 'ESCALATED', current_tier_deadline = now() + 5 days
   -> Dean logs in with dean.demo -> Opens Authority Triage Queue
   -> Dean inspects timeline and can resolve or refer to Ombudsman.

5. LEVEL 3 -> LEVEL 4 ESCALATION:
   If Level 3 SLA expires (5 days) without resolution:
   -> Engine forwards to Level 4 (Principal / Ombudsman Board, 5-day SLA)
   -> Assigns ombudsman.demo (Campus-Wide Level 4 officer)
   -> Updates status = 'ESCALATED', current_tier_deadline = now() + 5 days.

6. APEX LEVEL 4 BREACH:
   If Level 4 SLA expires without resolution:
   -> Engine detects no higher tier exists (level_number = 5 is NULL)
   -> Logs APEX_TIER_SLA_BREACHED in public.audit_logs
   -> Dispatches urgent alerts to all administrators for immediate intervention.

7. 20-DAY CUTOFF FREEZE (HIGHEST PRECEDENCE):
   At any point in the lifecycle, if now() >= cutoff_deadline (20 calendar days):
   -> Engine executes Step 1 Cutoff Freeze BEFORE tier escalation
   -> Updates status = 'CUTOFF_PAUSED', is_cutoff_paused = true, paused_at = now()
   -> Automated cron jobs freeze for this complaint
   -> Administrator or Dean inspects in AdminCutoffReviewScreen
   -> Authorizes resumption with mandatory notes via resume_paused_complaint()
   -> Grievance resumes at status = 'UNDER_REVIEW' with refreshed 20-day cutoff.
```

---

## ROUTING & ESCALATION ARCHITECTURE DIAGRAM

```
                       STUDENT SUBMISSION
                    (student.demo@campus.edu)
                                |
                                v
                       SELECT DEPARTMENT
       +------------------------+------------------------+
       |                        |                        |
[Academic Affairs]    [Hostel & Residential]   [Campus Infrastructure]
       |                        |                        |
       v                        v                        v
LEVEL 1: Faculty Advisor   LEVEL 1: Hostel Warden   LEVEL 1: Facilities Eng
  (SLA: 3 Days)            (SLA: 3 Days)            (SLA: 3 Days)
       |                        |                        |
       +------------------------+------------------------+
                                |
               (SLA Breached / Unresolved in 3 Days)
                                |
                                v
                   LEVEL 2: Head of Department
                      (SLA: 4 Days / Dept-Scoped)
                                |
               (SLA Breached / Unresolved in 4 Days)
                                |
                                v
               LEVEL 3: Dean of Student Welfare
                  (SLA: 5 Days / Campus-Wide Scope)
                                |
               (SLA Breached / Unresolved in 5 Days)
                                |
                                v
             LEVEL 4: Principal / Ombudsman Board
                  (SLA: 5 Days / Apex Institutional)
                                |
       +------------------------+------------------------+
       |                                                 |
(Any Tier Resolves)                              (Reaches 20 Days)
       |                                                 |
       v                                                 v
  [ RESOLUTION ]                                 [ 20-DAY CUTOFF FREEZE ]
- Mandatory Resolution Notes                     - Automated escalation paused
- Resolved timestamp recorded                    - Status: CUTOFF_PAUSED
- Closed status badge in UI                      - Admin / Dean formal sign-off
- Verified timeline trail                        - Resumes via resume_paused_complaint
```

---

GRIEVANCE ROUTING AUDIT COMPLETE — NO CODE CHANGES MADE.
