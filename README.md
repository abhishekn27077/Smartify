# SMARTIFY — Android-First Campus Grievance Redressal System

[![Flutter](https://img.shields.io/badge/Flutter-3.24%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%2015-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![Android](https://img.shields.io/badge/Platform-Android%20API%2034%2B-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![Architecture](https://img.shields.io/badge/State-Provider%20%2B%20Clean%20Architecture-teal)](https://pub.dev/packages/provider)
[![Tests](https://img.shields.io/badge/Tests-57%20Passed-success)](https://flutter.dev/docs/testing)

> **MCA Capstone Project**  
> SMARTIFY is an Android-first campus grievance-management application designed to provide institutional transparency, strict time-bound accountability (SLA), and automated escalation across academic and operational departments.

---

## 📌 Table of Contents

1. [Executive Summary & Problem Statement](#-executive-summary--problem-statement)
2. [Core Features & Business Rules](#-core-features--business-rules)
3. [Technology Stack](#-technology-stack)
4. [Quick Start: One-Command Launcher](#-quick-start-one-command-launcher)
5. [Fresh Laptop Setup Guide (Step-by-Step)](#-fresh-laptop-setup-guide-step-by-step)
6. [Hot Reload Developer Workflow](#-hot-reload-developer-workflow)
7. [Login Credentials & Demo Accounts](#-login-credentials--demo-accounts)
8. [System Architecture & Codebase Layout](#-system-architecture--codebase-layout)
9. [Database & Security Architecture](#-database--security-architecture)
10. [Verification, Quality Gates & Builds](#-verification-quality-gates--builds)
11. [Project Documentation Hub](#-project-documentation-hub)

---

## 📖 Executive Summary & Problem Statement

In conventional college and university environments, student grievance redressal is hindered by:
* **Paper-based bottlenecks & lost complaints:** Physical letters or unmonitored email inboxes without tracking IDs.
* **Opaque status tracking:** Students have no visibility into who is reviewing their grievance or what progress is made.
* **Lack of time-bound accountability (SLA):** Grievances languish indefinitely without escalation or deadline tracking.
* **Absence of department isolation:** Academic and operational matters get misrouted without clear ownership.

**SMARTIFY solves these challenges** by delivering a robust, mobile-first redressal platform built with Flutter and Supabase PostgreSQL. Every grievance is tracked with an immutable tracking ID, automatically bound to department-specific SLA countdowns, and systematically escalated if left unattended.

---

## 🛡️ Core Features & Business Rules

### 1. Server-Authoritative Role-Based Access Control (RBAC)
* **Single unified login screen:** The app contains zero insecure client-side role toggles.
* Upon login with campus credentials, the backend Supabase database authoritative record dictates whether the user is a `STUDENT`, `AUTHORITY`, or `ADMIN`.
* The application routes automatically to the respective authorized dashboard.

### 2. Strict 7-Calendar-Day Retrospective Rule
* Incident dates are strictly constrained to:
  $$\text{Incident Date} \in [\text{Today} - 7\text{ days}, \text{Today}]$$
* **Dual enforcement:** Restricted in the Flutter date-picker UI and enforced at the database level via a PostgreSQL `CHECK` constraint & validation trigger. Prevents retroactive lodging of stale complaints.

### 3. Multi-Tier Authority Hierarchy & Forwarding
* Grievances progress across a 3-tier hierarchy:
  * **Level 1:** Faculty Reviewer / Hostel Warden / Operational Officer (Intake & Triage)
  * **Level 2:** Head of Department (HoD) (Forwarded cases & department escalation)
  * **Level 3:** Dean / Principal (Final academic redressal authority)
* Each tier is bound to an active SLA deadline countdown (typically 3 to 5 calendar days).

### 4. 20-Calendar-Day Automated Cutoff Freeze (`CUTOFF_PAUSED`)
* If a grievance reaches **20 calendar days** from initial submission without resolution, automated background escalation is automatically halted.
* Status transitions to `CUTOFF_PAUSED`. Automated cron jobs are locked out to prevent endless escalation cycles.
* **Resumption Protocol:** Only an authorized Dean or Campus Administrator can unlock and resume the grievance, requiring mandatory justification notes (≥ 10 characters) and recording an immutable audit entry in `public.audit_logs`.

### 5. Strict Departmental Data Isolation (Row Level Security)
* Academic grievances (MCA, MBA, M.Com) route strictly to their respective department faculty and HoDs.
* Operational grievances (Library & IT, Hostel, Accounts & Finance, Campus Infrastructure) route strictly to operational officers regardless of the student's degree.
* Enforced at the PostgreSQL level using Supabase Row Level Security (RLS) policies.

### 6. Executive Analytics & DDE-Safe Reporting
* Real-time KPI metric cards (Total Lodged, Resolution Rate, Overdue Cases, Average Resolution Time).
* 7-dimension status breakdown pie chart powered by `fl_chart`.
* **DDE Formula Injection Protection:** Exported CSV and PDF reports sanitize dangerous spreadsheet formula triggers (`=`, `+`, `-`, `@`) by prepending a single quote (`'`), protecting administrators against CSV injection attacks.

### 7. Chronological Audit Trail & In-App Alerts
* Append-only history of status changes, forwarding actions, and administrative memos.
* Dynamic in-app notifications with deep linking directly to the affected grievance card.

---

## 💻 Technology Stack

| Domain | Technology / Package | Version / Detail | Purpose in SMARTIFY |
| :--- | :--- | :--- | :--- |
| **Mobile Client** | Flutter SDK | `3.24.0+` (Verified on `3.47.7`) | Android-first cross-platform application |
| **Language** | Dart | `3.13.5+` | Sound null-safe client application logic |
| **State Management** | Provider | `provider: ^6.1.2` | Clean reactive ChangeNotifier state architecture |
| **Backend / DB** | Supabase PostgreSQL | PostgreSQL 15 | Relational data, RLS security, triggers, functions |
| **Authentication** | Supabase Auth (GoTrue) | JWT Auth | Real token exchange, encrypted credentials |
| **File Storage** | Supabase Storage | `complaint-attachments` | Private evidence file attachments |
| **Visual Charts** | `fl_chart` | `^0.68.0` | Executive interactive analytics pie charts |
| **Document Export** | `pdf` & `csv` | `pdf: ^3.10.8`, `csv: ^6.0.0` | Sanitized DDE-safe report generation |
| **Design System** | Custom Theme | Academic Slate & Deep Emerald | High-contrast, accessible institutional UI |

---

## 🚀 Quick Start: One-Command Launcher

The fastest and easiest way to run SMARTIFY on your Windows machine with live **Hot Reload** is using the automated PowerShell launcher:

```powershell
# Open PowerShell in the project root:
.\scripts\run_smartify.ps1
```

### What This Script Does Automatically
1. **Finds Flutter & Android Tools:** Locates Flutter SDK even if it's not permanently in your system `PATH` (checks `D:\flutter`, `C:\flutter`, etc.).
2. **Synchronizes Dependencies:** Runs `flutter pub get` cleanly.
3. **Validates Backend Configuration:** Verifies `.env` safely without exposing secrets. Falls back to zero-setup demo mode if `.env` is absent.
4. **Detects Your Target Device:** Scans for connected physical Android phones via ADB or running emulators.
5. **Launches with Live Hot Reload:** Starts the app in interactive debug mode.

Before launching, you can run the diagnostic environment checker:
```powershell
.\scripts\check_setup.ps1
```

---

## 🛠️ Fresh Laptop Setup Guide (Step-by-Step)

Follow these steps if you are setting up SMARTIFY on a new Windows laptop:

### Step 1: Install Git
* Download and install Git from [git-scm.com](https://git-scm.com/download/win).
* Use the default installation settings.

### Step 2: Install Flutter SDK
1. Download Flutter SDK (>=3.24.0) from [flutter.dev](https://docs.flutter.dev/get-started/install/windows).
2. Extract the zip to `C:\flutter` or `D:\flutter` (*avoid `C:\Program Files` to prevent Windows permission issues*).
3. Add `bin` to your User Environment Variables:
   * Press `Win + S`, type **Environment Variables**, and select **Edit environment variables for your account**.
   * Under User variables, select **Path** > **Edit** > **New** > Add `C:\flutter\bin` (or `D:\flutter\bin`).
4. Open a new PowerShell window and confirm:
   ```powershell
   flutter --version
   ```

### Step 3: Install Android Studio & Android SDK
1. Download Android Studio from [developer.android.com/studio](https://developer.android.com/studio).
2. Open Android Studio > **More Actions** (or **Tools**) > **SDK Manager**.
3. Under **SDK Platforms**, ensure **Android 14.0 (API 34)** or **Android 15 (API 35)** is checked.
4. Under **SDK Tools**, check:
   * `Android SDK Build-Tools`
   * `Android SDK Command-line Tools (latest)`
   * `Android SDK Platform-Tools`
5. Accept Android licenses in PowerShell:
   ```powershell
   flutter doctor --android-licenses
   ```
   *(Press `y` to accept each license agreement)*.

### Step 4: Clone the Project
```powershell
git clone <repository-url>
cd SMARTIFY
```

### Step 5: Connect an Android Phone or Start Emulator

#### Option A: Physical Android Phone via USB (Recommended)
1. On your phone, open **Settings** > **About Phone**.
2. Tap **Build Number** 7 times rapidly until it says *"You are now a developer!"*.
3. Go to **Settings** > **Additional Settings / Developer Options** > Turn ON **USB Debugging**.
   * *For Xiaomi / Redmi:* Also turn ON **Install via USB** and **USB Debugging (Security settings)**.
   * *For Realme / OPPO:* Turn ON **Install via USB** and **Disable Permission Monitoring**.
4. Connect phone to laptop with a USB data cable (select **File Transfer / MTP** mode).
5. On the phone screen prompt, check **"Always allow from this computer"** and tap **Allow**.

#### Option B: Android Studio Emulator
1. In Android Studio, open **Device Manager** > Click **Create Virtual Device**.
2. Select **Pixel 7** or **Pixel 6** > Download **API 34 (UpsideDownCake)** > Click **Finish**.
3. Click the **Play** button to boot the emulator.

### Step 6: Launch SMARTIFY
```powershell
.\scripts\run_smartify.ps1
```

---

## ⚡ Hot Reload Developer Workflow

When running via `.\scripts\run_smartify.ps1`, the app runs with an active interactive session:

| Keyboard Key | Action | What It Does |
| :---: | :--- | :--- |
| **`r`** | **Hot Reload** | Sub-second UI refresh (~300ms). Updates widgets, padding, styling, and text without losing your active form inputs or login state. |
| **`R`** | **Hot Restart** | Rebuilds app state (~1.5s). Resets provider states and returns to the initial route. |
| **`h`** | **Help** | Displays all interactive Flutter runtime options. |
| **`q`** | **Quit** | Gracefully disconnects the session and exits. |

---

## 🔑 Login Credentials & Demo Accounts

> 👉 **For complete copy-paste blocks and evaluator scenarios, see [LOGIN_DETAILS.md](LOGIN_DETAILS.md).**

### Universal Password for All Demo Accounts
```text
Demo@Campus2026!
```

All 17 accounts are pre-seeded and verified on the live Supabase Auth backend. No registration or confirmation email is required.

### Quick Persona Reference

| Persona / Role | Email Address | Password | Department / Authority Scope |
| :--- | :--- | :--- | :--- |
| **MCA Student** | `student.demo@campus.edu` | `Demo@Campus2026!` | Student Grievance Portal (`MCA-2026-001`) |
| **MBA Student** | `mba.student@campus.edu` | `Demo@Campus2026!` | Student Grievance Portal (`MBA-2026-002`) |
| **M.Com Student** | `mcom.student@campus.edu` | `Demo@Campus2026!` | Student Grievance Portal (`MCOM-2026-003`) |
| **MCA L1 Faculty** | `faculty.demo@campus.edu` | `Demo@Campus2026!` | Dept of MCA • Level 1 (Faculty Reviewer) |
| **MCA HoD (L2)** | `hod.demo@campus.edu` | `Demo@Campus2026!` | Dept of MCA • Level 2 (Head of Department) |
| **MCA Dean (L3)** | `dean.demo@campus.edu` | `Demo@Campus2026!` | Dept of MCA • Level 3 (Dean of MCA) |
| **IT Officer (L1)** | `it.demo@campus.edu` | `Demo@Campus2026!` | Library & IT Services (Wi-Fi, Systems) |
| **Hostel Warden (L1)** | `authority.demo@campus.edu` | `Demo@Campus2026!` | Hostel & Residential Life (Mess, Rooms) |
| **Finance Officer (L1)** | `finance.demo@campus.edu` | `Demo@Campus2026!` | Accounts & Finance (Fees, Deposits) |
| **Infra Officer (L1)** | `infra.demo@campus.edu` | `Demo@Campus2026!` | Infrastructure & Campus Facilities |
| **Campus Admin** | `admin.demo@campus.edu` | `Demo@Campus2026!` | Institutional Governance, 20-Day Cutoff & Audit |

*(Open [LOGIN_DETAILS.md](LOGIN_DETAILS.md) for 1-click individual copy boxes and ready-to-test walkthrough scripts!)*

---

## 🏗️ System Architecture & Codebase Layout

SMARTIFY follows a **Feature-First Layered Architecture**:

```text
smartify/
├── AGENTS.md                    # Project Charter, invariants & coding standards
├── README.md                    # Main repository manual & documentation
├── LOGIN_DETAILS.md             # Complete credentials cheat sheet for quick copy-paste
├── .gitignore                   # Airtight exclusions (secrets, builds, IDE configs)
├── .env.example                 # Safe environment configuration template
├── pubspec.yaml                 # Locked dependencies manifest
├── android/                     # Android native configuration & Gradle scripts
├── assets/                      # App logos, vector icons & brand assets
├── docs/                        # In-depth architectural & evaluation manuals
│   ├── DEVELOPMENT_SETUP.md     # Multi-machine setup & troubleshooting guide
│   ├── demo_guide.md            # Evaluator demo script & feature checklist
│   ├── architecture.md          # Layered architecture deep-dive
│   ├── database-schema.md       # PostgreSQL schema, functions & triggers
│   ├── security.md              # RLS policies & authorization matrix
│   └── design-system.md         # Academic Slate & Deep Emerald design tokens
├── scripts/
│   ├── check_setup.ps1          # Diagnostic environment pre-flight validator
│   └── run_smartify.ps1         # One-command developer launcher with Hot Reload
├── lib/
│   ├── main.dart                # App bootstrap & Supabase initialization
│   ├── app.dart                 # Root MaterialApp, router & theme configuration
│   ├── core/                    # Shared infrastructure across features
│   │   ├── config/              # SupabaseConfig with resilient fallback
│   │   ├── constants/           # App routes, asset constants, strings
│   │   ├── errors/              # Typed Failure hierarchy (ServerFailure, AuthFailure)
│   │   ├── theme/               # Colors, typography, spacing tokens
│   │   ├── utils/               # Sanitizers, date formatters, validators
│   │   └── widgets/             # Reusable UI widgets (buttons, text fields, cards)
│   ├── models/                  # Global entities (User, Profile, Department)
│   ├── services/                # Global services (SupabaseClient, Storage)
│   ├── providers/               # Shared providers (AppTheme, AppState)
│   └── features/                # Domain-driven feature modules
│       ├── auth/                # Login, registration, AuthProvider
│       ├── home/                # Role-based dashboard shell & navigation
│       ├── complaints/          # Grievance registration, 7-day rule, forms
│       ├── tracking/            # Student complaints list, timeline, detail view
│       ├── authority/           # Authority triage queue, take action modal
│       ├── escalation/          # Multi-tier escalation, SLA countdown badges
│       ├── analytics/           # Executive KPI dashboard, pie charts, DDE export
│       ├── notifications/       # In-app alerts, badge counters, deep links
│       └── admin/               # 20-day cutoff review, manual resumption, audit
├── supabase/
│   ├── config.toml              # Supabase CLI configuration
│   └── migrations/              # Versioned SQL migrations (RLS, triggers, schema)
└── test/
    ├── unit/                    # Unit tests for models, providers, utilities
    ├── widget/                  # Widget tests for core UI components
    └── final_qa_runner.js       # End-to-end automated security & QA suite
```

---

## 🔒 Database & Security Architecture

### 9 Core PostgreSQL Tables
1. `profiles`: User identity, registration number, assigned department, authority level, and role.
2. `departments`: Institutional departments (Academic: MCA, MBA, M.Com; Operational: IT, Hostel, Finance, Infra).
3. `authority_levels`: Hierarchical tiers (Level 1 Reviewer, Level 2 HoD, Level 3 Dean).
4. `complaints`: Core grievance records with server timestamps, category, priority, status, and tracking ID.
5. `complaint_attachments`: Evidence file links stored in private Supabase Storage buckets.
6. `complaint_status_history`: Chronological transition log with reviewer notes and actor IDs.
7. `complaint_escalations`: Audit log of tier forwardings, escalation triggers, and reasons.
8. `audit_logs`: Immutable, append-only security log for administrative resumptions and policy changes.
9. `notifications`: In-app event alerts bound to user profiles.

### Security Invariants
* **100% Row Level Security (RLS):** Every table has strict RLS enabled. Students can only select their own complaints; authorities can only access complaints routed to their department/tier; admins can view institute-wide data.
* **No Client Secrets:** The mobile client only receives the public `SUPABASE_ANON_KEY`. The `SUPABASE_SERVICE_ROLE_KEY` is strictly administrative and is never embedded in the Flutter application.
* **Server-Authoritative Time:** All SLA deadlines and cutoff periods compute via `timezone('utc'::text, now())`, making client clock manipulation ineffective.

---

## 🧪 Verification, Quality Gates & Builds

SMARTIFY is maintained with zero-tolerance for compiler warnings, lint issues, or broken tests.

### Execute Verification Gates

```powershell
# 1. Static Code Analysis (0 errors, 0 warnings standard)
flutter analyze

# 2. Run Complete Unit & Widget Test Suite (57 tests)
flutter test

# 3. Automated Security & QA Validation Suite
node test/final_qa_and_security_runner.js

# 4. SQL Migration & Schema Validator
node test/sql_validator.js
```

### Build Production Artifacts

```powershell
# Build Debug APK (Includes hot reload VM & full debug symbols, ~207 MB)
flutter build apk --debug
# Path: build/app/outputs/flutter-apk/app-debug.apk

# Build Production Release APK (Split ARM64, optimized & obfuscated, ~22.6 MB)
flutter build apk --release --split-per-abi
# Path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

## 📚 Project Documentation Hub

| Document | Description |
| :--- | :--- |
| [docs/DEMO_FLOW.md](docs/DEMO_FLOW.md) | **Master Presentation Flow:** Step-by-step evaluator demonstration scripts & expected results |
| [docs/DEMO_ACCOUNTS.md](docs/DEMO_ACCOUNTS.md) | **Demo Credentials Reference:** Role-differentiated accounts (Student, Authority, Admin) |
| [LOGIN_DETAILS.md](LOGIN_DETAILS.md) | **Master Credential Reference:** 1-click copy boxes for all accounts & testing scenarios |
| [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) | Multi-machine setup guide, Android SDK tools, and troubleshooting |
| [docs/architecture.md](docs/architecture.md) | Layered architecture specification and Provider state management patterns |
| [docs/database-schema.md](docs/database-schema.md) | Complete PostgreSQL table definitions, triggers, and SQL functions |
| [docs/security.md](docs/security.md) | Row Level Security (RLS) policies, access control matrix, and DDE mitigation |
| [docs/design-system.md](docs/design-system.md) | Academic Slate & Deep Emerald design tokens, typography, and spacing grid |

---

## ⚠️ Known Limitations & Evaluation Boundaries

1. **In-App Realtime vs External FCM:** Push notifications use Supabase Realtime in-app notification streams. External Google Firebase Cloud Messaging (FCM) is excluded to avoid third-party proprietary dependencies per project charter.
2. **Operational Single-Tier Hierarchy:** Operational departments (Hostel, IT, Accounts & Finance, Infrastructure) operate with a single responsible Level 1 officer by default. If forwarded, cases escalate directly to Level 4 Institutional Governance without attempting invalid intermediate hops.
3. **7-Day Retrospective Window:** Grievance incident dates cannot exceed 7 calendar days into the past.
4. **20-Day Cutoff Freeze:** Grievances reaching 20 days without resolution halt automated cron escalation (`status = 'CUTOFF_PAUSED'`) and require authorized Administrator sign-off with mandatory audit rationale.

---

*SMARTIFY — MCA Capstone Campus Grievance Redressal System.*
