# SMARTIFY — Project Charter & Agent Rules

## 1. Project Identity & Fixed Stack
SMARTIFY is an Android-first campus grievance-management application built for an MCA capstone.
The technology stack is fixed and non-negotiable:
- **Client Framework:** Flutter + Dart (Android-first target; Android Studio for builds, emulator/device testing, and APK generation).
- **State Management:** Provider (ChangeNotifier / ChangeNotifierProvider / Consumer / Selector).
- **Backend & Database:** Supabase Auth, PostgreSQL, Supabase Storage, SQL migrations.
- **Server-Side Automation:** Supabase PostgreSQL functions, triggers, and scheduled jobs (`pg_cron` / Edge Functions).
- **Data Visualization & Export:** `fl_chart`, `pdf`, `csv`.
- **Version Control:** Git.

### Strict Prohibitions
- No rewriting in native Java/Kotlin, React Native, or switching to another framework.
- No replacing Flutter with a web app wrapper.
- No introduction of alternative state management libraries (no Bloc, no Riverpod, no GetX).
- No unapproved third-party backend alternatives (no Firebase, no AWS Amplify).
- No hardcoded secrets, test credentials, or production tokens in the codebase.
- Never expose the Supabase `service_role` key to the Flutter application.

---

## 2. Architecture & File Organization

### Architectural Pattern: Feature-First Layered Architecture
Every business domain lives in `lib/features/<feature_name>/` and is divided into three distinct layers:
1. **Data Layer (`models/`, `services/`, `repositories/`):** Network calls, Supabase queries, and entity mapping.
2. **Domain/State Layer (`providers/`):** ChangeNotifier business logic, validation, state machines, and view states.
3. **Presentation Layer (`screens/`, `widgets/`):** UI widgets, forms, dialogs, and responsive layouts. Reusable app-wide widgets live in `lib/core/widgets/`.

### Directory Layout
```text
smartify/
├── AGENTS.md
├── README.md
├── .gitignore
├── .env.example
├── analysis_options.yaml
├── pubspec.yaml
├── android/
├── assets/
│   ├── images/
│   ├── icons/
│   └── fonts/
├── docs/
│   ├── architecture.md
│   ├── database-schema.md
│   ├── security.md
│   └── design-system.md
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── config/
│   │   ├── constants/
│   │   ├── routing/
│   │   ├── theme/
│   │   ├── errors/
│   │   ├── utils/
│   │   └── widgets/
│   ├── models/
│   ├── services/
│   ├── providers/
│   └── features/
│       ├── auth/
│       ├── home/
│       ├── complaints/
│       ├── tracking/
│       ├── authority/
│       ├── escalation/
│       ├── analytics/
│       ├── notifications/
│       ├── admin/
│       └── profile/
├── supabase/
│   ├── config.toml
│   ├── migrations/
│   ├── functions/
│   └── tests/
└── test/
    ├── unit/
    ├── widget/
    └── integration/
```

### File & Symbol Naming Conventions
- **Files & Directories:** `snake_case` (e.g., `grievance_model.dart`, `complaint_submission_provider.dart`).
- **Classes, Types & Enums:** `PascalCase` (e.g., `GrievanceStatus`, `ComplaintRepository`).
- **Variables, Getters & Methods:** `camelCase` (e.g., `isLoading`, `submitComplaint()`).
- **Constants:** `lowerCamelCase` or `SCREAMING_SNAKE_CASE` for global static constants (e.g., `kMaxRetrospectiveDays = 7`).
- **File Length:** Target ≤ 250 lines per file. Break complex screens into dedicated sub-widgets.

---

## 3. Design System & UI/UX Standards

SMARTIFY uses a deliberate, high-contrast, multi-token **Academic Slate & Deep Emerald** theme. Never rely on generic white backgrounds with a single accent color.

### A. Semantic Color Palette
- **Primary / Brand:**
  - `primary`: `#0D9488` (Teal 600) / Dark: `#14B8A6` (Teal 500)
  - `onPrimary`: `#FFFFFF` / Dark: `#042F2E`
  - `primaryContainer`: `#CCFBF1` (Teal 100) / Dark: `#134E4A`
  - `onPrimaryContainer`: `#115E59` (Teal 800) / Dark: `#5EEAD4`
- **Secondary / Authority Hierarchy:**
  - `secondary`: `#4F46E5` (Indigo 600) / Dark: `#818CF8`
  - `onSecondary`: `#FFFFFF` / Dark: `#1E1B4B`
  - `secondaryContainer`: `#E0E7FF` (Indigo 100) / Dark: `#312E81`
  - `onSecondaryContainer`: `#3730A3` (Indigo 800) / Dark: `#C7D2FE`
- **Surfaces & Backgrounds (Dark Mode):**
  - `background`: `#0F172A` (Slate 900)
  - `surface`: `#1E293B` (Slate 800)
  - `surfaceElevated`: `#334155` (Slate 700)
  - `onSurface`: `#F8FAFC` (Slate 50)
  - `outline`: `#475569` (Slate 600)
- **Surfaces & Backgrounds (Light Mode):**
  - `background`: `#F8FAFC` (Slate 50)
  - `surface`: `#FFFFFF`
  - `surfaceElevated`: `#FFFFFF`
  - `onSurface`: `#0F172A` (Slate 900)
  - `outline`: `#CBD5E1` (Slate 300)
- **Status Indicators (Multi-Token):**
  - `statusPending`: `#D97706` (Amber 600)
  - `statusUnderReview`: `#2563EB` (Blue 600)
  - `statusInProgress`: `#0284C7` (Sky 600)
  - `statusEscalated`: `#EA580C` (Orange 600)
  - `statusSlaBreached`: `#DC2626` (Red 600)
  - `statusCutoffPaused`: `#7C3AED` (Purple 600) — 20-day cutoff freeze
  - `statusResolved`: `#059669` (Emerald 600)
  - `statusRejected`: `#64748B` (Slate 500)

### B. Typography & Spacing
- **Font Family:** Plus Jakarta Sans or system Inter/Roboto.
- **Hierarchy:** Display: 28sp Bold, Headline: 22sp SemiBold, Title Large: 18sp SemiBold, Body Large: 15sp Regular, Body Medium: 14sp Regular, Label: 12sp Medium.
- **Spacing Grid (8pt):** `4dp`, `8dp`, `12dp`, `16dp`, `24dp`, `32dp`, `48dp`.
- **Corner Radii:** Small: `8dp`, Medium: `12dp`, Large: `16dp`, Pill: `999dp`.
- **Touch Target Law:** Minimum `48dp × 48dp` for all interactive elements.

### C. State Handling
Every screen that loads or manipulates data must explicitly handle 5 distinct states:
1. **Loading:** Layout-matched shimmer skeleton.
2. **Empty:** Contextual SVG/icon + clear explanation + primary action button.
3. **Error:** Non-intrusive alert/banner + user-friendly error message + retry action.
4. **Success:** Immediate visual feedback + clear confirmation + haptic response.
5. **Disabled:** Visual muted contrast (40% opacity) on incomplete validations.

---

## 4. Coding, Quality & Maintenance Standards

- **Inspect First & Preserve Working Code:** Always inspect existing files and understand current architecture before modifying. Never delete working functionality or overwrite user code carelessly.
- **Null Safety:** 100% sound null safety. No `!` force unwrap unless proven by an immediate runtime invariant.
- **Const Constructors:** Use `const` on all immutable widget constructors to prevent redundant rebuilds.
- **Provider Hygiene:** Use `select` or `Consumer` scoped to the smallest widget subtree that actually depends on the changed value.
- **Error Handling:** Map all exceptions into strongly-typed `Failure` objects. No silent empty `catch` blocks.
- **Input Validation:** Enforce trim and sanitation on all text inputs. Validate email formats, password rules, and file extensions.
- **No Production Secrets in Git:** All API keys and endpoints must be passed via compile-time `--dart-define` or `.env` excluded from version control.
- **Zero Duplicate Logic:** Shared utility functions, formatters, and network clients must reside exclusively in `lib/core/`.

---

## 5. Security & Business Logic Invariants

1. **Supabase Row Level Security (RLS):**
   - RLS must be enabled on every table without exception.
   - Students can only SELECT and INSERT their own grievances and view non-confidential timeline updates.
   - Authority roles can only view and update grievances assigned to their department/tier.
   - Audit logs are append-only. No UPDATE or DELETE policies for any client role.
2. **Server-Authoritative Timestamps:**
   - All complaint submission dates, status updates, escalation timestamps, and audit events use PostgreSQL `timezone('utc'::text, now())`.
   - Never trust client device clocks for SLA calculations.
3. **7-Calendar-Day Retrospective Constraint:**
   - Complaint incident dates can only be selected within `[Current Date - 7 days, Current Date]`.
   - Enforced client-side in the date picker AND strictly enforced server-side via PostgreSQL trigger.
4. **Authority Hierarchy & 20-Day Cutoff Freeze:**
   - Multi-tier escalation: Level 1 (Faculty/Hostel Warden) → Level 2 (Head of Department) → Level 3 (Dean / Principal) → Level 4 (Arbitration Board).
   - Each tier has a deadline (e.g., 3 to 5 calendar days).
   - **20-Calendar-Day Cutoff:** If a grievance reaches 20 calendar days from initial submission without resolution, automated escalation MUST freeze (`status = 'CUTOFF_PAUSED'`). Automated cron jobs are locked out.
   - Resumption requires authorized manual sign-off by a designated Dean or Administrator with an immutable audit entry.
5. **Storage Security:**
   - Evidence files stored in private Supabase Storage buckets (`complaint-attachments`).
   - Files are accessible solely via short-lived signed URLs generated on the server or validated through storage RLS policies.

---

## 6. Verification Gates for All Phases

Before declaring any implementation phase complete, the following verification gates must pass:
1. **Inspection Gate:** Review all modified and newly created files for syntax, structure, and rule compliance.
2. **Formatting Gate:** Code must pass `dart format --output=none --set-exit-if-changed .` (when Dart SDK is available).
3. **Static Analysis Gate:** Code must pass `flutter analyze` with zero errors and zero warnings (when Flutter SDK is available).
4. **Test Gate:** All unit and widget tests must pass cleanly (`flutter test` or local validator scripts).
5. **Build Gate:** Android build check must succeed (`flutter build apk --debug`).
6. **Honesty Rule:** Never claim a test, check, or build has passed unless it was actually executed and verified with the tool output.
