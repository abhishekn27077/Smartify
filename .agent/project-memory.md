# SMARTIFY ?" Project Memory

## 1. System Overview & Technology Stack
- **Project**: SMARTIFY ?" Campus Grievance Redressal System (MCA Capstone)
- **Target Platform**: Android-first mobile application.
- **Client Framework**: Flutter + Dart (`lib/`, `pubspec.yaml`).
- **State Management**: `Provider` (`ChangeNotifier`, `Consumer`, `Selector`).
  - *Strict Rule*: No Bloc, no Riverpod, no GetX.
- **Backend**: Supabase (`supabase/`).
  - PostgreSQL with Row Level Security (RLS).
  - Storage buckets for grievance attachments.
  - Server-side automated escalation via PostgreSQL triggers/functions (`pg_cron`).
- **Data Export & Visualization**: `fl_chart`, `pdf`, `csv`.
- **Primary Repository Root**: `D:\work\SMARTIFY`

## 2. Architectural Blueprint
- **Pattern**: Feature-First Layered Architecture (`lib/features/<feature_name>/`).
  1. `models/` + `services/` + `repositories/`: Data & Supabase network layer.
  2. `providers/`: Domain logic, view states, error mapping, ChangeNotifier.
  3. `screens/` + `widgets/`: Presentation widgets (<= 250 lines per file).
- **Core Shared Utilities**: `lib/core/`
  - `errors/failures.dart`: Failure hierarchy (`ServerFailure`, `AuthFailure`, etc.).
  - `config/`, `constants/`, `theme/`, `utils/`, `widgets/`.

## 3. Critical Verification & Test Commands
- **Flutter Code Analysis**: `flutter analyze`
- **Targeted Unit/Widget Test**: `flutter test test/unit/<target>_test.dart`
- **Full Test Suite**: `flutter test`
- **SQL / Migration Validator**: `node test/sql_validator.js`
- **Android APK Build**: `flutter build apk --debug`

## 4. Strict Security & Coding Invariants
- Never expose Supabase `service_role` key to Flutter client; client uses `anon_key` with strict RLS.
- Parameterize all SQL functions. Never concatenate unescaped parameters.
- Handle all network calls through repository layer returning `Either<Failure, T>` or typed results.
- Keep UI files modular and adhere to Academic Slate & Deep Emerald design system.

## 5. Durable Lessons Learned
- *2026-10-16*: Project memory initialized. Agent operates with automatic skill routing: `debugging` on errors, `flutter-expert` on UI/state, `postgres-best-practices` on Supabase migrations.
