# SMARTIFY — Master Presentation & Evaluation Demo Flow

This document outlines the step-by-step evaluation workflow for presenting SMARTIFY to evaluators and external reviewers.

Global Demo Credentials Password:
```text
Demo@Campus2026!
```

---

## Act 1: Student Self-Registration & Grievance Submission

### 1.1 Student Registration / Login
- Launch SMARTIFY on Android device or emulator.
- **Login Option:**
  - Email: `student.demo@campus.edu`
  - Password: `Demo@Campus2026!`
- **Or Self-Registration Option:**
  - Tap **Register Here** on login screen.
  - Fill Full Name: `Aarav Patel`
  - Institutional Email: `student.new@campus.edu`
  - Select Academic Program: **MCA** *(Restricted to MCA, MBA, M.Com)*
  - Enter Password: `Demo@Campus2026!`
  - Tap **REGISTER ACCOUNT**. Account is created strictly as role `STUDENT`.

### 1.2 Submit an Academic Grievance (MCA)
- From Student Home, tap **File New Grievance**.
- Category: Select **Academic Affairs / Lecture Schedule**
- Title: `Lab Workstation Configuration Issue in MCA Lab 3`
- Description: `Required database drivers and SDKs are missing on Lab 3 terminal stations.`
- Select Incident Date: Within past 7 calendar days *(enforced by client date picker and PostgreSQL constraint)*.
- Tap **SUBMIT GRIEVANCE**.
- System assigns tracking number: `SMT-2026-XXXXX` and calculates initial 3-day SLA deadline.
- Routed automatically to: **Department of MCA** (Current Tier: Level 1 Faculty).

### 1.3 Track Status & Timeline
- Tap **Track Grievance** or select the newly submitted case.
- Review the Visual Order Tracker showing:
  - Step 1: Submission (Completed)
  - Step 2: Level 1 Faculty Review (Current)
  - Step 3: Level 2 HoD Review
  - Step 4: Level 3 Dean of Academic Affairs
  - Step 5: Resolution
- Expand **View detailed activity history** to inspect the chronological immutable audit trail.

---

## Act 2: Academic Redressal Flow (Department of MCA)

### 2.1 Level 1 Review & Forward (MCA Faculty Advisor)
- Sign out and log in as:
  - Email: `faculty.demo@campus.edu`
  - Password: `Demo@Campus2026!`
- Open **Authority Queue**.
- Tap the newly submitted MCA case.
- Tap **Mark Under Review** / **Accept Case**.
  - Timeline records: `Reviewed by: Prof. Suresh Kumar | Level 1: Faculty / Department Officer`.
- Tap **FORWARD TO LEVEL 2**.
- Enter Forwarding Reason: `Requires laboratory resource allocation approval from Head of Department.`
- Tap **CONFIRM FORWARD**.
- Case moves atomically to Level 2 (HoD).

### 2.2 Level 2 Review & Forward (MCA Head of Department)
- Sign out and log in as:
  - Email: `hod.demo@campus.edu`
  - Password: `Demo@Campus2026!`
- Open **Authority Queue**.
- The forwarded case appears in HoD's queue with priority status.
- Tap **FORWARD TO LEVEL 3** (or **RESOLVE**).
- Enter Reason: `Escalating to Dean of Academic Affairs for campus-wide software licensing.`
- Tap **CONFIRM FORWARD**.
- Case moves atomically to Level 3 (Dean).

### 2.3 Level 3 Resolution (Dean of Academic Affairs)
- Sign out and log in as:
  - Email: `dean.demo@campus.edu`
  - Password: `Demo@Campus2026!`
- Open **Authority Queue**.
- Open the escalated grievance.
- Tap **RESOLVE GRIEVANCE**.
- Enter Resolution Notes: `Licenses updated and workstations re-imaged across MCA Lab 3.`
- Tap **CONFIRM RESOLUTION**.
- Case transitions to terminal status `RESOLVED`.
- Submitting student receives instant in-app notification.

---

## Act 3: Operational Department Redressal (Hostel / IT / Finance / Infra)

Operational grievances route strictly to the responsible operational department regardless of the student's academic program.

### 3.1 Submit an Operational Grievance (Hostel or Wi-Fi)
- Log in as any student: `student.demo@campus.edu` (MCA) or `mba.student@campus.edu` (MBA).
- Category: Select **Hostel & Residential Life**
- Title: `Water Pressure Disruption in Block B Hostel`
- Submit grievance.
- Even though student is enrolled in MCA/MBA, case routes directly to **Hostel & Residential Life** Level 1.

### 3.2 Single-Tier Operational Redressal (Hostel Warden)
- Sign out and log in as:
  - Email: `authority.demo@campus.edu`
  - Password: `Demo@Campus2026!`
- Open Hostel Warden Queue.
- Tap the hostel grievance.
- Notice: Operational department is configured with single responsible Level 1 officer.
- Forward button displays **ESCALATE TO GOVERNANCE** (or shows clean message that no Level 2 authority exists, preventing database corruption).
- Tap **RESOLVE GRIEVANCE**.
- Enter Resolution Notes: `Plumbing valve replaced; normal water pressure restored.`
- Tap **CONFIRM RESOLUTION**.

---

## Act 4: Campus Governance & Administrative Oversight (ADMIN)

Central Administrator oversees institutional compliance and system integrity. Admin is **not** a routine grievance handler.

### 4.1 Admin Login & Governance Dashboard
- Sign out and log in as:
  - Email: `admin.demo@campus.edu`
  - Password: `Demo@Campus2026!`
- View **Governance Dashboard**:
  - Live campus grievance metrics across Academic & Operational departments.
  - Active vs Resolved vs Escalated breakdown.
  - SLA Compliance & Department Resolution Rates.

### 4.2 Department & Staff Management
- Navigate to **Authority Staff**:
  - View all registered authority officers, their departments, authority tiers, and Active/Inactive statuses.
  - Tap **Add Staff** (Floating Action Button):
    - Enter Full Name: `Prof. Additional MCA Faculty`
    - Email: `mca.faculty2@campus.edu`
    - Temporary Password: `Demo@Campus2026!`
    - Department: `Department of MCA`
    - Authority Tier: `Level 1`
    - Account Active: `true`
    - Role is strictly locked to `AUTHORITY`.
    - Tap **CREATE STAFF**.

### 4.3 20-Day Cutoff Review Center
- Open **20-Day Cutoff Review Center**.
- Demonstrates institutional compliance: Any case reaching 20 days without resolution freezes automated escalation (`status = CUTOFF_PAUSED`).
- Administrator can review frozen cases and provide authorized manual resumption with mandatory audit rationale.

---

## Summary of Key Technical Highlights for Evaluators

1. **Fixed MCA Capstone Stack:** Flutter + Dart (client), Provider (state), Supabase Auth + PostgreSQL (backend), Row Level Security (RLS).
2. **Strict 3-Role Model:** `STUDENT`, `AUTHORITY`, `ADMIN`. No artificial micro-roles (`HOD`, `DEAN`, `WARDEN` are attributes of `authority_level` and `department_id`).
3. **Decoupled Grievance Routing:** Student program is separate from grievance category. Operational issues route to operational officers; academic issues route to department tiers.
4. **Server-Authoritative Timestamps:** All SLA deadlines and audit trails use UTC PostgreSQL `timezone('utc'::text, now())`, rendered locally in IST (+05:30) via `.toLocal()`.
5. **Atomic Forwarding & RLS Security:** Forwarding RPC validates department, level, and next-tier existence atomically. RLS prevents students or unauthorized authorities from altering cases.
