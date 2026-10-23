# ==============================================================================
# SMARTIFY - Development Environment Validator
# Validates Flutter SDK, Android Studio, ADB, Java, and project configuration.
# ==============================================================================
param(
    [switch]$Detailed,
    [switch]$Help
)

if ($Help) {
    Write-Host "SMARTIFY Environment Validator" -ForegroundColor Cyan
    Write-Host "Usage: .\scripts\check_setup.ps1 [-Detailed]" -ForegroundColor White
    Write-Host "  -Detailed  Display verbose diagnostics for Android and tools" -ForegroundColor Gray
    exit 0
}

# --- Step 0: Ensure correct project root ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}
Set-Location $ProjectRoot

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "SMARTIFY - Development Environment Pre-Flight Check" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan

$Issues = @()
$Warnings = @()

# --- Helper: Mask sensitive keys ---
function Get-MaskedValue {
    param([string]$Value)
    if (-not $Value) { return "(not set)" }
    if ($Value.Length -le 10) { return "********" }
    $prefix = $Value.Substring(0, 8)
    return "$prefix...[REDACTED]"
}

# --- 1. Validate Flutter SDK ---
Write-Host "[1/6] Checking Flutter SDK..." -ForegroundColor White
$FlutterCmd = $null
$FlutterCmdInPath = Get-Command "flutter" -ErrorAction SilentlyContinue

if ($FlutterCmdInPath) {
    $FlutterCmd = $FlutterCmdInPath.Source
} else {
    $CommonFlutterPaths = @(
        "D:\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter.bat",
        (Join-Path $env:LOCALAPPDATA "flutter\bin\flutter.bat"),
        (Join-Path $env:USERPROFILE "flutter\bin\flutter.bat"),
        "C:\src\flutter\bin\flutter.bat"
    )
    if ($env:FLUTTER_ROOT) {
        $CommonFlutterPaths += (Join-Path $env:FLUTTER_ROOT "bin\flutter.bat")
    }

    foreach ($Candidate in $CommonFlutterPaths) {
        if (Test-Path $Candidate) {
            $FlutterCmd = $Candidate
            $FlutterBinDir = Split-Path -Parent $Candidate
            $env:PATH = "$FlutterBinDir;$env:PATH"
            Write-Host "  [i] Found Flutter at '$Candidate' and added to session PATH." -ForegroundColor Yellow
            $Warnings += "Flutter is not permanently in your system PATH. Add '$FlutterBinDir' to User Environment Variables."
            break
        }
    }
}

if ($FlutterCmd) {
    try {
        $FlutterVerRaw = & $FlutterCmd --version 2>&1
        $FlutterFirstLine = ($FlutterVerRaw | Select-Object -First 1)
        Write-Host "  [OK] $FlutterFirstLine" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Flutter executable located but failed to run." -ForegroundColor Red
        $Issues += "Flutter execution failed: $_"
    }
} else {
    Write-Host "  [X] Flutter SDK NOT found in PATH or standard directories." -ForegroundColor Red
    $Issues += "Flutter SDK missing. Download from https://docs.flutter.dev/get-started/install/windows and add flutter\bin to PATH."
}

# --- 2. Checking Dart SDK ---
Write-Host "[2/6] Checking Dart SDK..." -ForegroundColor White
$DartCmdInPath = Get-Command "dart" -ErrorAction SilentlyContinue
if ($DartCmdInPath) {
    $DartVer = & dart --version 2>&1
    Write-Host "  [OK] $DartVer" -ForegroundColor Green
} elseif ($FlutterCmd) {
    Write-Host "  [OK] Dart SDK bundled within Flutter SDK." -ForegroundColor Green
} else {
    Write-Host "  [X] Dart SDK unavailable without Flutter." -ForegroundColor Red
    $Issues += "Dart SDK is missing."
}

# --- 3. Checking Java / JDK & Android Studio JBR ---
Write-Host "[3/6] Checking Java Development Kit (JDK)..." -ForegroundColor White
$JavaCmd = Get-Command "java" -ErrorAction SilentlyContinue
$JavaFound = $false

if ($JavaCmd) {
    $JavaVerOutput = & java -version 2>&1 | Select-Object -First 1
    Write-Host "  [OK] Java (in PATH): $JavaVerOutput" -ForegroundColor Green
    $JavaFound = $true
} else {
    $CommonJbrPaths = @(
        "C:\Program Files\Android\Android Studio\jbr\bin\java.exe",
        "C:\Program Files\Android\Android Studio1\jbr\bin\java.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Android Studio\jbr\bin\java.exe")
    )
    foreach ($Jbr in $CommonJbrPaths) {
        if (Test-Path $Jbr) {
            $JbrDir = Split-Path -Parent $Jbr
            $env:PATH = "$JbrDir;$env:PATH"
            $JavaVerOutput = & $Jbr -version 2>&1 | Select-Object -First 1
            Write-Host "  [OK] Android Studio JBR: $JavaVerOutput" -ForegroundColor Green
            $JavaFound = $true
            break
        }
    }
}

if (-not $JavaFound) {
    Write-Host "  [*] Java JDK not detected in PATH. Android builds require OpenJDK 17 or 21." -ForegroundColor Yellow
    $Warnings += "JDK not found in PATH. Install Android Studio with default JBR or download OpenJDK 21."
}

# --- 4. Checking Android SDK & ADB ---
Write-Host "[4/6] Checking Android SDK & ADB..." -ForegroundColor White
$AdbCmd = Get-Command "adb" -ErrorAction SilentlyContinue
$AdbPath = $null

if ($AdbCmd) {
    $AdbPath = $AdbCmd.Source
} else {
    $CommonAdbPaths = @(
        (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"),
        "C:\Android\Sdk\platform-tools\adb.exe"
    )
    if ($env:ANDROID_HOME) {
        $CommonAdbPaths += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe")
    }

    foreach ($CandidateAdb in $CommonAdbPaths) {
        if (Test-Path $CandidateAdb) {
            $AdbPath = $CandidateAdb
            $AdbDir = Split-Path -Parent $CandidateAdb
            $env:PATH = "$AdbDir;$env:PATH"
            break
        }
    }
}

if ($AdbPath) {
    $AdbVerRaw = & $AdbPath version 2>&1 | Select-Object -First 1
    Write-Host "  [OK] ADB Tool: $AdbVerRaw" -ForegroundColor Green
} else {
    Write-Host "  [*] ADB not found in standard Android SDK path." -ForegroundColor Yellow
    $Warnings += "ADB missing from PATH. Install Android Studio Platform Tools (Android SDK > platform-tools)."
}

# --- 5. Checking Connected Devices & Emulators ---
Write-Host "[5/6] Checking Connected Devices & Emulators..." -ForegroundColor White
$AndroidDevices = @()
$OtherDevices = @()

if ($FlutterCmd) {
    try {
        $DevicesJson = & $FlutterCmd devices --machine 2>$null | Out-String
        if ($DevicesJson) {
            $ParsedDevices = $DevicesJson | ConvertFrom-Json
            foreach ($Dev in $ParsedDevices) {
                $plat = $Dev.targetPlatform
                $dName = $Dev.name
                $dId = $Dev.id
                if ($plat -like "android*") {
                    $AndroidDevices += $Dev
                    Write-Host "  [OK] Android Target: $dName ($dId) [$plat]" -ForegroundColor Green
                } else {
                    $OtherDevices += $Dev
                    Write-Host "  [i] Other Target: $dName ($dId) [$plat]" -ForegroundColor Gray
                }
            }
        }
    } catch {
        Write-Host "  [!] Device detection query encountered an issue." -ForegroundColor Yellow
    }
}

if ($AndroidDevices.Count -eq 0) {
    Write-Host "  [*] No Android phone or active emulator connected." -ForegroundColor Yellow
    Write-Host "      Tip: Connect Android phone via USB and enable 'USB Debugging' in Developer Options." -ForegroundColor Gray
    
    # Check for available offline emulators
    if ($FlutterCmd) {
        $EmulatorsRaw = & $FlutterCmd emulators 2>&1 | Out-String
        if ($EmulatorsRaw -match "available emulator") {
            Write-Host "      Emulators available in Android Studio. Launch one from Device Manager." -ForegroundColor Gray
        }
    }
    $Warnings += "No Android device currently attached. Connect phone via USB or start Android Studio emulator before launching."
}

# --- 6. Checking Project Configuration & Supabase Setup ---
Write-Host "[6/6] Checking Project Configuration & Security..." -ForegroundColor White
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
if (Test-Path $PubspecPath) {
    $PubspecContent = Get-Content $PubspecPath -Raw
    if ($PubspecContent -match "name:\s*smartify") {
        Write-Host "  [OK] Valid SMARTIFY project root confirmed." -ForegroundColor Green
    } else {
        $Issues += "pubspec.yaml does not match SMARTIFY project name."
    }
} else {
    $Issues += "Missing pubspec.yaml in $ProjectRoot."
}

# Check .env / SupabaseConfig
$EnvPath = Join-Path $ProjectRoot ".env"
$EnvExamplePath = Join-Path $ProjectRoot ".env.example"

if (Test-Path $EnvPath) {
    Write-Host "  [OK] Local .env file detected." -ForegroundColor Green
    $EnvLines = Get-Content $EnvPath
    $FoundUrl = ""
    $FoundKey = ""
    foreach ($Line in $EnvLines) {
        $T = $Line.Trim()
        if (($T -eq "") -or ($T.StartsWith("#"))) { continue }
        $Parts = $T -split "=", 2
        if ($Parts.Length -eq 2) {
            $K = $Parts[0].Trim()
            $V = $Parts[1].Trim()
            if ($K -eq "SUPABASE_URL") { $FoundUrl = $V }
            if ($K -eq "SUPABASE_ANON_KEY") { $FoundKey = $V }
        }
    }
    if ($FoundUrl) {
        Write-Host "  [OK] SUPABASE_URL configured: $FoundUrl" -ForegroundColor Green
    } else {
        Write-Host "  [!] SUPABASE_URL missing in .env." -ForegroundColor Yellow
        $Warnings += ".env is missing SUPABASE_URL."
    }
    if ($FoundKey) {
        $Masked = Get-MaskedValue -Value $FoundKey
        Write-Host "  [OK] SUPABASE_ANON_KEY configured: $Masked" -ForegroundColor Green
    } else {
        Write-Host "  [!] SUPABASE_ANON_KEY missing in .env." -ForegroundColor Yellow
        $Warnings += ".env is missing SUPABASE_ANON_KEY."
    }
} else {
    Write-Host "  [i] No local .env file found. App will use safe built-in demo defaults from SupabaseConfig." -ForegroundColor Yellow
    if (Test-Path $EnvExamplePath) {
        Write-Host "      To configure custom credentials, copy .env.example to .env." -ForegroundColor Gray
    }
}

# Verify dependencies synced
$PackagesConfig = Join-Path $ProjectRoot ".dart_tool\package_config.json"
if (Test-Path $PackagesConfig) {
    Write-Host "  [OK] Flutter package dependencies are synced (.dart_tool)." -ForegroundColor Green
} else {
    Write-Host "  [*] Flutter dependencies not yet resolved. Run 'flutter pub get'." -ForegroundColor Yellow
    $Warnings += "Dependencies not resolved. Run 'flutter pub get'."
}

# --- Summary Report ---
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

if ($Issues.Count -eq 0 -and $Warnings.Count -eq 0) {
    Write-Host "[OK] ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host "Your development environment is completely ready to run SMARTIFY." -ForegroundColor Green
    Write-Host "To start the app, execute: .\scripts\run_smartify.ps1" -ForegroundColor Cyan
} elseif ($Issues.Count -eq 0) {
    Write-Host "[OK] CORE SYSTEM READY (With $($Warnings.Count) Recommendation(s))" -ForegroundColor Green
    Write-Host ""
    Write-Host "Recommendations / Next Steps:" -ForegroundColor Yellow
    foreach ($w in $Warnings) {
        Write-Host "  * $w" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "You can proceed to run SMARTIFY via: .\scripts\run_smartify.ps1" -ForegroundColor Cyan
} else {
    Write-Host "[X] ENVIRONMENT BLOCKERS DETECTED ($($Issues.Count) Issue(s))" -ForegroundColor Red
    Write-Host ""
    Write-Host "Required Actions Before Running:" -ForegroundColor Red
    foreach ($issue in $Issues) {
        Write-Host "  * $issue" -ForegroundColor Red
    }
    if ($Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Additional Warnings:" -ForegroundColor Yellow
        foreach ($w in $Warnings) {
            Write-Host "  * $w" -ForegroundColor Yellow
        }
    }
    exit 1
}

exit 0
