# SMARTIFY — Development Setup & Portable Workflow Guide

This document is the definitive, step-by-step setup guide for running **SMARTIFY** on your Windows laptop or setting up a friend's machine from scratch.

SMARTIFY is an Android-first campus grievance-management application built with Flutter, Provider, Supabase Auth, PostgreSQL, and Supabase Storage for an MCA capstone project.

---

## 1. Quick Start: The One-Command Workflow

If you already have Flutter and Android tools installed, getting SMARTIFY running with live Hot Reload takes just one command:

```powershell
# In PowerShell (from project root):
.\scripts\run_smartify.ps1
```

### What This Script Does Automatically
1. **Verifies Project Integrity:** Confirms execution from the valid SMARTIFY root directory.
2. **Auto-Detects Development Tools:** Locates Flutter SDK and Android ADB in your PATH or standard installation folders.
3. **Synchronizes Dependencies:** Executes `flutter pub get` cleanly.
4. **Validates Configuration:** Reads `.env` safely (or falls back to safe demo mode defaults in `SupabaseConfig.dart`) without ever logging private passwords or keys.
5. **Detects & Selects Target Device:** Scans connected Android phones or running emulators. If multiple devices are present, provides an interactive selection menu.
6. **Launches with Hot Reload:** Starts the app in debug mode on your phone and keeps the session interactive.

---

## 2. Prerequisites for a New Laptop

To set up SMARTIFY on a friend's laptop or a fresh machine, install the following:

| Component | Minimum Version | Recommended / Verified | Download Link |
|---|---|---|---|
| **OS** | Windows 10 (64-bit) | Windows 11 (64-bit) | Pre-installed |
| **Git** | 2.30+ | Git for Windows 2.45+ | [git-scm.com](https://git-scm.com/download/win) |
| **Flutter SDK** | 3.24.0+ | Flutter 3.47.7 (Dart 3.13.5) | [flutter.dev](https://docs.flutter.dev/get-started/install/windows) |
| **Android Studio** | Ladybug / Koala | Android Studio Ladybug (2024.2+) | [developer.android.com/studio](https://developer.android.com/studio) |
| **Java JDK** | OpenJDK 17 | OpenJDK 21 or Android Studio JBR | Included in Android Studio |
| **Android SDK Platform** | API 34 | API 34 & Android SDK Build-Tools 34.0.0 | Via Android Studio SDK Manager |

---

## 3. Fresh Laptop Installation Guide (Step-by-Step)

### Step 3.1 — Install Git & Clone Repository
1. Download and install Git from [git-scm.com](https://git-scm.com/download/win).
2. Open PowerShell and clone the project:
   ```powershell
   git clone <repository-url>
   cd SMARTIFY
   ```

### Step 3.2 — Install Flutter SDK
1. Download the Flutter Windows SDK zip bundle from [flutter.dev/docs/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows).
2. Extract the zip to `C:\flutter` or `D:\flutter` (**do not** extract into `C:\Program Files\` to avoid Windows permissions issues).
3. Add Flutter to your User Environment Variable `Path`:
   - Press `Win + S` and search for **Environment Variables**.
   - Click **Edit environment variables for your account**.
   - Select `Path` under User variables, click **Edit**, click **New**, and paste `C:\flutter\bin` (or `D:\flutter\bin`).
   - Click **OK** to save.
4. Open a **new** PowerShell window and verify:
   ```powershell
   flutter --version
   ```

### Step 3.3 — Install Android Studio & Android SDK
1. Download and install Android Studio with standard settings.
2. Open Android Studio > **More Actions** (or **Tools**) > **SDK Manager**.
3. Under the **SDK Platforms** tab, ensure **Android 14.0 ("UpsideDownCake") / API 34** or **Android 15 / API 35** is checked.
4. Under the **SDK Tools** tab, check the following:
   - `Android SDK Build-Tools`
   - `Android SDK Command-line Tools (latest)`
   - `Android SDK Platform-Tools`
   - `Android Emulator`
5. Click **Apply** to install the components.
6. In PowerShell, accept the Android licenses:
   ```powershell
   flutter doctor --android-licenses
   ```
   (Press `y` to accept all prompt agreements).

### Step 3.4 — Validate Your Setup
SMARTIFY includes an automated diagnostic tool to verify all tools before running:
```powershell
.\scripts\check_setup.ps1
```
The script will display a 6-step pre-flight check covering Flutter, Dart, Java, ADB, connected devices, and configuration.

---

## 4. Connecting Your Android Phone

SMARTIFY is designed as an Android-first mobile application. You can test on a physical handset using either USB cable or Wireless Debugging.

### Method A: USB Cable Connection (Recommended)
1. **Enable Developer Options on Phone:**
   - Open phone **Settings** > **About Phone** (or **About Device**).
   - Find **Build Number** (sometimes under *Version* or *Software information*).
   - Tap **Build Number** 7 times rapidly until a toast appears: *"You are now a developer!"*.
2. **Enable USB Debugging:**
   - Go to phone **Settings** > **System** (or **Additional Settings**) > **Developer Options**.
   - Turn **ON** `USB Debugging`.
   - **For OPPO / Realme / ColorOS / OxygenOS:**
     - Turn ON `Install via USB`.
     - Turn ON `USB debugging (Security settings)`.
     - Turn ON `Disable Permission Monitoring`.
   - **For Xiaomi / Redmi / MIUI / HyperOS:**
     - Turn ON `Install via USB`.
     - Turn ON `USB debugging (Security settings)`.
3. **Connect to Laptop:**
   - Plug phone into laptop via a USB data cable.
   - Set USB mode to **File Transfer / MTP** (not "Charging only").
   - Unlock phone screen. When prompted: *"Allow USB debugging from this computer?"*, check **"Always allow from this computer"** and tap **Allow**.
4. **Verify ADB Detection:**
   ```powershell
   adb devices
   ```
   Output should show your device ID followed by `device` (e.g., `CPH2127 device`).

---

### Method B: Wireless Debugging (Android 11+)
If you prefer testing without cables:
1. Connect laptop and phone to the **same Wi-Fi network**.
2. On phone: **Developer Options** > Turn ON **Wireless Debugging**.
3. Tap **Wireless Debugging** > **Pair device with pairing code**.
4. On laptop PowerShell:
   ```powershell
   adb pair <IP_ADDRESS>:<PORT>
   # Enter the 6-digit Wi-Fi pairing code shown on phone
   adb connect <IP_ADDRESS>:<CONNECTION_PORT>
   ```
5. Confirm device appears in `adb devices`.

---

### Method C: Android Emulator (Virtual Device)
If no physical phone is available:
1. Open Android Studio > **Virtual Device Manager** (Device Manager icon).
2. Click **Create Device** > Select **Phone** (e.g., **Pixel 7** or **Pixel 6**).
3. Select system image (e.g., **UpsideDownCake / API 34**).
4. Finish wizard and click the **Play** button to launch the emulator.

---

## 5. Hot Reload & Developer Iteration Workflow

When you launch SMARTIFY with `.\scripts\run_smartify.ps1`, Flutter runs in interactive debug mode with Hot Reload enabled.

```text
================================================================================
SMARTIFY IS RUNNING (HOT RELOAD ACTIVE)
================================================================================
Interactive Keyboard Controls:
  r   -> Hot Reload (Updates UI changes within ~200-500ms without losing state)
  R   -> Hot Restart (Reinitializes application state and returns to login)
  h   -> Help (Shows full Flutter runtime options)
  d   -> Detach (Disconnects terminal while leaving app running on phone)
  q   -> Quit (Stops the application process)
================================================================================
```

### When to use Hot Reload vs Hot Restart vs Rebuild

| Action | Command | Triggered By | When to Use |
|---|---|---|---|
| **Hot Reload** | Press `r` in terminal | Code edits inside `build()` methods | Tweaking layout, colors, padding, button text, or localized formatting. Preserves active form data. |
| **Hot Restart** | Press `R` in terminal | Code edits in `initState()`, Provider state machines | Changing constructor parameters, altering initial state, resetting login session. |
| **Full Rebuild** | Terminate (`q`) and re-run `.\scripts\run_smartify.ps1` | Native changes, dependency updates | Modifying `pubspec.yaml`, adding new images/fonts in `assets/`, updating Android gradle files or permissions. |

---

## 6. Supabase Backend & Credentials Architecture

SMARTIFY is pre-configured with a secure multi-tenant architecture on Supabase.

### A. Safe Public Client Configuration
- Flutter clients connect using standard public credentials:
  - `SUPABASE_URL`: Institutional endpoint (`https://ypxhpoqkwvujwaogkkcq.supabase.co`)
  - `SUPABASE_ANON_KEY`: Public publishable key (`sb_publishable_...`)
- These values are safe to bundle with the mobile client because **Row Level Security (RLS)** is strictly enforced on all 9 PostgreSQL tables on the server.

### B. Fallback Demo Mode (Zero Setup Needed for Friends)
If a friend clones the project without a `.env` file:
- The app automatically falls back to the institutional demo credentials hardcoded safely in `lib/core/config/supabase_config.dart`.
- The app launches seamlessly into demo mode without crashing or requiring manual credential entry.

### C. Custom Environment Setup (Optional)
To point to a custom or staging Supabase instance:
1. Copy `.env.example` to `.env`:
   ```powershell
   Copy-Item .env.example .env
   ```
2. Edit `.env` with your custom project credentials:
   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your_publishable_anon_key
   ```
3. `.\scripts\run_smartify.ps1` will automatically detect `.env` and pass the parameters securely via `--dart-define`.

### D. Security Boundaries & Invariants
- **NEVER put `service_role` keys into `.env` on a client laptop.**
- **NEVER commit `.env` to Git.** (Protected by `.gitignore`).
- The `DATABASE_URL` direct connection string and `SUPABASE_SERVICE_ROLE_KEY` are only required by the project owner for running administrative SQL migrations in `supabase/migrations/`.

---

## 7. Fictional Demo Accounts for Testing

Use these pre-provisioned demo accounts to test all roles without needing real emails or SMTP:

| Role | Email Address | Password | Campus ID | Assigned Scope |
|---|---|---|---|---|
| **Student** | `student.demo@campus.edu` | `Demo@Campus2026!` | `MCA-2026-STU-042` | Academic Affairs (Student View) |
| **Authority** | `authority.demo@campus.edu` | `Demo@Campus2026!` | `FAC-2026-ACAD-01` | Academic Affairs (Tier 1 Faculty/Warden) |
| **Admin** | `admin.demo@campus.edu` | `Demo@Campus2026!` | `ADM-2026-DEAN-01` | Campus-Wide (Tier 3 Dean / Administrator) |

---

## 8. Common CLI Commands Reference

All commands must be executed from the project root (`D:\work\SMARTIFY`):

```powershell
# 1. Environment & Pre-Flight Check
.\scripts\check_setup.ps1

# 2. Run App on Phone (One Command)
.\scripts\run_smartify.ps1

# 3. Synchronize Dependencies
flutter pub get

# 4. Static Code Analysis (Zero warnings standard)
flutter analyze

# 5. Run Test Suite (57 unit & widget tests)
flutter test

# 6. Build Debug APK
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk

# 7. Build Lightweight Release APK (Split ARM64, ~22.6 MB)
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

## 9. Troubleshooting & FAQ

### Issue: `INSTALL_FAILED_VERSION_DOWNGRADE`
- **Cause:** Android OS prohibits installing a debug build over a previously installed release build or build with different signing keys.
- **Fix:** Uninstall the old version from the phone first:
  ```powershell
  adb uninstall com.smartify.campus
  ```
  Then re-run `.\scripts\run_smartify.ps1`.

### Issue: `adb: device unauthorized`
- **Cause:** Phone screen was locked or RSA fingerprint prompt was dismissed.
- **Fix:** Unlock phone, unplug and re-plug USB cable. When the dialog appears, check *"Always allow"* and tap **Allow**.

### Issue: `'flutter' is not recognized as a cmdlet...`
- **Cause:** Flutter's `bin` directory is not in your Windows system PATH.
- **Fix:** Add `C:\flutter\bin` (or `D:\flutter\bin`) to your User Environment Variables under `Path`, then restart your PowerShell terminal.

### Issue: `ADB server version does not match client`
- **Cause:** Another application (like an Android emulator or third-party phone manager) is running a conflicting `adb.exe`.
- **Fix:** Reset the ADB server:
  ```powershell
  adb kill-server
  adb start-server
  ```

---
*Maintained for MCA Capstone Project — SMARTIFY Campus Redressal Platform.*
