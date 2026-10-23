# SMARTIFY — Demo Accounts & Credentials Reference

All accounts are real, verified institutional accounts running on live Supabase Auth.
Authentication uses actual Supabase GoTrue token exchange (email + password).
There is zero bypass authentication or role spoofing.

**Global Password for All Demo Accounts:**
```text
Demo@Campus2026!
```

> 💡 **Need fast copy-paste boxes?** Check the master root file: [LOGIN_DETAILS.md](../../LOGIN_DETAILS.md) for 1-click individual copy boxes and step-by-step evaluator testing scripts!

---

## 1. Students (By Academic Program)

| Email | Full Name | Academic Program | Department | Registration No. | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `student.demo@campus.edu` | Aarav Patel | MCA | Department of MCA | `MCA-2026-001` | Submit MCA academic & campus-wide operational grievances |
| `mba.student@campus.edu` | Rohan Verma | MBA | Department of MBA | `MBA-2026-002` | Submit MBA academic & campus-wide operational grievances |
| `mcom.student@campus.edu` | Priya Sharma | M.Com | Department of M.Com | `MCOM-2026-003` | Submit M.Com academic & campus-wide operational grievances |

---

## 2. Academic Redressal Hierarchy

### Master of Computer Applications (MCA)
| Tier | Email | Full Name | Role | Department | Level | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **L1** | `faculty.demo@campus.edu` | Prof. Suresh Kumar | AUTHORITY | Department of MCA | Level 1 | First-line redressal for MCA academic matters |
| **L2** | `hod.demo@campus.edu` | Dr. Radhika Sharma | AUTHORITY | Department of MCA | Level 2 | Head of Department (HoD) for forwarded MCA grievances |
| **L3** | `dean.demo@campus.edu` | Prof. M. K. Nair | AUTHORITY | Department of MCA | Level 3 | Dean of Academic Affairs / Grievance Cell |

### Master of Business Administration (MBA)
| Tier | Email | Full Name | Role | Department | Level | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **L1** | `mba.faculty@campus.edu` | Dr. Amit Trivedi | AUTHORITY | Department of MBA | Level 1 | First-line redressal for MBA academic matters |
| **L2** | `mba.hod@campus.edu` | Dr. Neha Gupta | AUTHORITY | Department of MBA | Level 2 | Head of Department (HoD) for forwarded MBA grievances |
| **L3** | `mba.dean@campus.edu` | Prof. Rajesh Khanna | AUTHORITY | Department of MBA | Level 3 | Dean of Management Studies / Grievance Cell |

### Master of Commerce (M.Com)
| Tier | Email | Full Name | Role | Department | Level | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **L1** | `mcom.faculty@campus.edu` | Prof. Vikram Malhotra | AUTHORITY | Department of M.Com | Level 1 | First-line redressal for M.Com academic matters |
| **L2** | `mcom.hod@campus.edu` | Dr. Sunita Rao | AUTHORITY | Department of M.Com | Level 2 | Head of Department (HoD) for forwarded M.Com grievances |
| **L3** | `mcom.dean@campus.edu` | Prof. K. S. Pillai | AUTHORITY | Department of M.Com | Level 3 | Dean of Commerce / Grievance Cell |

---

## 3. Operational Services Redressal Hierarchy (L1 Triage)

Operational grievances (Wi-Fi, Hostel, Billing, Facilities) route strictly to their responsible operational department regardless of the student's academic program.

| Department | Email | Full Name | Role | Authority Level | Focus Areas |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Library & IT Services** | `it.demo@campus.edu` | Systems & IT Admin | AUTHORITY | Level 1 | Wi-Fi, Student Portal, Digital Library, Computer Labs |
| **Hostel & Residential Life** | `authority.demo@campus.edu` | Prof. Ananya Sen (Warden) | AUTHORITY | Level 1 | Hostel Rooms, Mess Food Quality, Water Supply, Cleanliness |
| **Accounts & Finance** | `finance.demo@campus.edu` | Accounts Officer | AUTHORITY | Level 1 | Tuition Fee Receipts, Scholarships, Caution Deposit Refund |
| **Infrastructure & Campus Facilities** | `infra.demo@campus.edu` | Campus Facility Officer | AUTHORITY | Level 1 | Projectors, AV Equipment, Restrooms, Campus Lighting, Parking |

---

## 4. Campus Administration & Governance

| Email | Full Name | Role | Scope | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `admin.demo@campus.edu` | Campus Administrator | ADMIN | Institute-wide | Governance oversight, 20-day cutoff review & resumption, audit trails, analytics. Does NOT act as routine grievance reviewer. |

---

## 5. Summary of System Roles
SMARTIFY maintains strictly **3 Application Roles**:
1. `STUDENT`
2. `AUTHORITY` (differentiated by `department_id`, `authority_level_id`, and `academic_program`)
3. `ADMIN` (governance, configuration, audit)

There are NO custom roles such as `WARDEN`, `HOD`, `DEAN`, or `IT_ROLE`. Authority hierarchy is structurally enforced via relational keys and database Row Level Security (RLS).
