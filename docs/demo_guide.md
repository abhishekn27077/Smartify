# SMARTIFY — MCA Capstone Demonstration & Evaluation Guide

This guide provides evaluators, project supervisors, and demonstration teams with full operational instructions, verified fictional credentials, step-by-step role presentation workflows, and technical audit findings for **SMARTIFY: Campus Grievance Management System**.

---

## 1. Verified Fictional Demo Accounts

All demo accounts are pre-provisioned, pre-confirmed in Supabase GoTrue Auth (`auth.users` & `auth.identities`), and bound to server-enforced profile roles in `public.profiles`. **No real email delivery, SMTP, or confirmation links are required.**

| Role | Email Address | Fictional Password | Profile Name & Registration No. | Department & Tier Scope |
| :--- | :--- | :--- | :--- | :--- |
| **Student** | `student.demo@campus.edu` | `Demo@Campus2026!` | **Aarav Patel**<br>`MCA-2026-STU-042` | Academic Affairs<br>Default Student Privilege |
| **Authority** | `authority.demo@campus.edu` | `Demo@Campus2026!` | **Prof. Suresh Kumar**<br>`FAC-2026-ACAD-01` | Academic Affairs<br>Tier 1: Faculty Advisor / Hostel Warden |
| **Admin** | `admin.demo@campus.edu` | `Demo@Campus2026!` | **Dr. Aris Thorne (Dean)**<br>`ADM-2026-DEAN-01` | Academic Affairs<br>Tier 3: Dean of Student Welfare / Grievance Cell |

> [!NOTE]
> **Client-Side Role Switching Removed:**
> Production-facing and interactive client-side role switches have been completely removed from the user interface. Roles are queried strictly from trusted backend database records upon authentication. Demo quick-fill chips on the login screen only populate email fields to expedite presentation; authentication requires full credential validation against Supabase Auth.

---

## 2. Step-by-Step Presentation Workflows

### Workflow 1: Student Grievance Submission & Tracking
1. **Login:** Log in with `student.demo@campus.edu` / `Demo@Campus2026!`.
2. **Landing:** The app loads the **Register Grievance** screen with institutional redressal protocols.
3. **7-Calendar-Day Retrospective Constraint:**
   - Tap the date picker.
   - Notice that dates older than 7 calendar days from today and future dates are disabled. Both client-side date selection and PostgreSQL triggers enforce `incident_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE`.
4. **Draft Submission:**
   - Select Category (e.g., *Academic Affairs* or *Infrastructure*).
   - Enter Title (≥ 5 characters) and Description (≥ 20 characters).
   - Tap **SUBMIT GRIEVANCE**.
5. **Confirmation & Reference Generation:**
   - The confirmation screen presents a unique tracking number (`SMT-2026-XXXXX`), human-readable status (*Pending Intake* instead of raw `PENDING`), and starting Tier (*Level 1*).
   - Tap **COPY REFERENCE** to test clipboard integration.
   - Tap **BACK TO HOME** to return safely to the student dashboard.
6. **Grievance Tracking:**
   - Navigate to the **Grievances** tab.
   - View grievance cards with dynamic SLA countdown badges and filter chips (*Pending*, *Under Review*, *In Progress*, *Escalated*, *Cutoff Paused*, *Resolved*, *Rejected*).
   - Tap a card to inspect the chronological redressal timeline and review actions.

---

### Workflow 2: Authority Triage & Escalation
1. **Login:** Log out from Student and log in with `authority.demo@campus.edu` / `Demo@Campus2026!`.
2. **Dashboard Routing:**
   - The application automatically opens the **Authority Triage Dashboard** (Triage, Analytics, Alerts, Profile tabs).
   - The queue displays grievances strictly scoped to the authority's assigned department.
3. **Action Dialog & State Machine Enforcement:**
   - Select an assigned grievance in *Under Review*.
   - Tap **TAKE ACTION** to open the state machine dialog:
     - Permitted target states: *In Progress*, *Escalated*, *Resolved*, *Rejected*.
     - Notice invalid backwards transitions (e.g., reverting to *Pending*) are disallowed.
   - When choosing *Resolved*, resolution notes are strictly mandatory (minimum 10 characters).
4. **Hierarchy Forwarding:**
   - Forwarding from Level 1 automatically advances the grievance to Level 2 (Head of Department) with refreshed SLA countdown.

---

### Workflow 3: Admin Cutoff Review & Resumption
1. **Login:** Log in with `admin.demo@campus.edu` / `Demo@Campus2026!`.
2. **Admin Portal Navigation:**
   - Access 5 specialized administrative tabs: **Admin**, **Cutoff**, **Analytics**, **Alerts**, and **Profile**.
3. **20-Day Cutoff Freeze Inspection:**
   - Tap the **Cutoff** tab.
   - Review cases where total elapsed time reached 20 calendar days from initial submission without resolution.
   - The system locks automated background cron jobs from escalating the case, setting status to `CUTOFF_PAUSED`.
4. **Authorized Resumption:**
   - Select `SMT-2026-PAUSED`.
   - Tap **RESUME GRIEVANCE**.
   - Input administrative justification notes (enforced ≥ 10 characters).
   - Resumption transitions the status back to `UNDER_REVIEW`, refreshes the tier SLA deadline, and records an immutable `RESUMPTION_AUTHORIZED` entry in `public.audit_logs`.

---

### Workflow 4: Executive Analytics & DDE-Safe Export
1. **Analytics Dashboard:**
   - Open the **Analytics** tab.
   - Review KPI metrics: *TOTAL LODGED*, *RESOLUTION RATE*, *AVG RESOLUTION*, and *OVERDUE / BREACHED*.
   - All status breakdown slices sum exactly to the total lodged cases (**32 + 5 + 4 + 3 + 2 + 1 + 1 = 48**).
2. **CSV & PDF Report Export:**
   - Tap the **CSV** or **PDF** export icon in the top app bar.
   - All cell exports sanitize dangerous spreadsheet triggers (`=`, `+`, `-`, `@`) by prepending a single quote (`'`), neutralizing CSV formula injection (DDE attacks).

---

### Workflow 5: In-App Notifications & Case Navigation
1. **Alerts Tab:**
   - Open the **Alerts** tab.
   - View categorized notification cards (*Escalation*, *Deadline Warning*, *Resumption*, *Status Change*).
2. **Deep-Link Case Navigation:**
   - Tapping an unread notification marks it as read and automatically opens the full case detail screen for that grievance (`ComplaintDetailScreen`).

---

## 3. Critical Bug Investigations & Audit Resolutions

### 1. Root Cause of "48 Total Cases vs 47 Visible Breakdown"
- **Investigation:** In `lib/features/analytics/widgets/status_distribution_pie_chart.dart`, the pie chart slices were hardcoded or filtered without accounting for `totalEscalated` (count = 1).
- **Resolution:** Added `totalEscalated` slice to the PieChart data sections and legend. All 7 status dimensions now accurately sum to the total lodged:
  $$\text{Resolved (32)} + \text{Under Review (5)} + \text{In Progress (4)} + \text{Pending (3)} + \text{Paused (2)} + \text{Rejected (1)} + \text{Escalated (1)} = 48$$

### 2. Investigation of `SMT-2026-PAUSED` vs `SMT-2026-PAUSED1`
- **Investigation:** A typo occurred in `lib/features/escalation/services/escalation_service.dart:135`, appending a trailing `'1'` to the tracking number in mock data.
- **Resolution:** Corrected to the canonical tracking number `SMT-2026-PAUSED`. Both database seeds and client models use this consistent reference.

### 3. Layout Overflow & Filter Clipping Elimination
- In `lib/features/tracking/screens/my_complaints_screen.dart` and `authority_dashboard_screen.dart`, added missing status chips (*Rejected*, *Resolved*) and applied `visualDensity: VisualDensity.compact` with `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`.
- In `lib/features/analytics/screens/analytics_dashboard_screen.dart`, adjusted `childAspectRatio` from `1.2` to `1.05` and set `maxLines: 2` with line height `1.2` in `AnalyticsKpiCard` to completely eliminate vertical text clipping and render overflow warnings across diverse device densities.

### 4. Root Navigation Stack Preservation
- In `lib/features/complaints/screens/complaint_registration_screen.dart`, replaced `pushReplacement` with standard `push` when displaying `SubmissionConfirmationScreen`.
- In `lib/features/complaints/screens/submission_confirmation_screen.dart`, updated `BACK TO HOME` and `REGISTER ANOTHER GRIEVANCE` to check `Navigator.canPop()` and fallback to `pushAndRemoveUntil(..., (route) => false)` targeting `PortalNavigationShell`, preventing blank or black screens on back navigation.
- Replaced raw database status string `'PENDING'` with the user-friendly localized badge label `'Pending Intake'`.

---

## 4. Verification Evidence & Quality Gates

| Verification Gate | Command Executed | Result |
| :--- | :--- | :--- |
| **Static Analysis** | `flutter analyze` | **PASSED: 0 errors, 0 warnings, 0 infos** (12.5s) |
| **Flutter Test Suite** | `flutter test` | **PASSED: 57 / 57 tests passed** (11.0s) |
| **QA & Security Audit** | `node test/final_qa_and_security_runner.js` | **PASSED: 211 / 211 assertions passed** (100%) |
| **SQL Migrations & RLS** | `node test/sql_validator.js` | **PASSED: 42 / 42 assertions passed** (100%) |
| **Complaint Validation** | `node test/phase5_complaint_validator.js` | **PASSED: 39 / 39 checks passed** (100%) |
| **Tracking & Authority** | `node test/phase6_workflow_validator.js` | **PASSED: 66 / 66 tests passed** (100%) |
| **Escalation Engine** | `node test/phase7_escalation_validator.js` | **PASSED: 36 / 36 tests passed** (100%) |
| **Analytics & Governance** | `node test/phase8_all_features_validator.js` | **PASSED: 59 / 59 tests passed** (100%) |
| **Android APK Build** | `flutter build apk --debug` | **PASSED: Built `app-debug.apk` (207.8 MB)** (73.9s) |

---

## 5. Built Artifacts

- **Android Debug APK Path:**  
  `D:\work\SMARTIFY\build\app\outputs\flutter-apk\app-debug.apk`  
  *Size:* 207,806,316 bytes  
  *Target Architecture:* ARM64, ARMv7, x86_64 universal debug bundle
- **Database Migrations:**  
  `supabase/migrations/20261012000001_core_schema.sql` through `20261012000005_analytics_notifications_admin.sql`
