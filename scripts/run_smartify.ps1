# ==============================================================================
# SMARTIFY - One-Command Development Launcher with Hot Reload
# MCA Campus Grievance Management System
# ==============================================================================
param(
    [string]$DeviceId = "",
    [switch]$SkipPubGet,
    [switch]$Release,
    [switch]$Help
)

if ($Help) {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "SMARTIFY - Development Launcher" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\scripts\run_smartify.ps1                  # Auto-detects device & launches with Hot Reload" -ForegroundColor Yellow
    Write-Host "  .\scripts\run_smartify.ps1 -DeviceId <id>   # Directs launch to specific device ID" -ForegroundColor Gray
    Write-Host "  .\scripts\run_smartify.ps1 -SkipPubGet      # Skips running 'flutter pub get'" -ForegroundColor Gray
    Write-Host "  .\scripts\run_smartify.ps1 -Release         # Runs in release mode (faster, no hot reload)" -ForegroundColor Gray
    Write-Host "  .\scripts\run_smartify.ps1 -Help            # Shows this help manual" -ForegroundColor Gray
    exit 0
}

# --- Step 0: Set Working Directory to Project Root ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}
Set-Location $ProjectRoot

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "SMARTIFY - Campus Grievance Redressal Development Launcher" -ForegroundColor Cyan
Write-Host "Working Directory: $ProjectRoot" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan

# --- Step 1: Verify Project Integrity ---
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
    Write-Host "[X] ERROR: pubspec.yaml not found in '$ProjectRoot'." -ForegroundColor Red
    Write-Host "    Please ensure you execute this script from within the SMARTIFY project repository." -ForegroundColor Yellow
    exit 1
}

$PubspecContent = Get-Content $PubspecPath -Raw
if ($PubspecContent -notmatch "name:\s*smartify") {
    Write-Host "[X] ERROR: The current directory does not appear to be the SMARTIFY project." -ForegroundColor Red
    exit 1
}

# --- Step 2: Locate Flutter SDK ---
Write-Host "[*] Locating Flutter SDK..." -ForegroundColor White
$FlutterCmd = $null
$FlutterCmdInPath = Get-Command "flutter" -ErrorAction SilentlyContinue

if ($FlutterCmdInPath) {
    $FlutterCmd = $FlutterCmdInPath.Source
} else {
    $CommonFlutterLocations = @(
        "D:\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter.bat",
        (Join-Path $env:LOCALAPPDATA "flutter\bin\flutter.bat"),
        (Join-Path $env:USERPROFILE "flutter\bin\flutter.bat"),
        "C:\src\flutter\bin\flutter.bat"
    )
    if ($env:FLUTTER_ROOT) {
        $CommonFlutterLocations += (Join-Path $env:FLUTTER_ROOT "bin\flutter.bat")
    }

    foreach ($Candidate in $CommonFlutterLocations) {
        if (Test-Path $Candidate) {
            $FlutterCmd = $Candidate
            $FlutterBinDir = Split-Path -Parent $Candidate
            $env:PATH = "$FlutterBinDir;$env:PATH"
            Write-Host "  [i] Discovered Flutter at '$Candidate' and added to session PATH." -ForegroundColor Yellow
            break
        }
    }
}

if (-not $FlutterCmd) {
    Write-Host ""
    Write-Host "[X] CRITICAL: Flutter SDK was not found on this machine." -ForegroundColor Red
    Write-Host "    Setup Steps for your laptop:" -ForegroundColor Yellow
    Write-Host "    1. Download Flutter SDK (>=3.24) from: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor White
    Write-Host "    2. Extract the archive (e.g., to C:\flutter or D:\flutter)." -ForegroundColor White
    Write-Host "    3. Add the bin folder (e.g., D:\flutter\bin) to your User 'Path' environment variable." -ForegroundColor White
    Write-Host "    4. Restart PowerShell and re-run: .\scripts\run_smartify.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Locate ADB if available
$AdbCmd = Get-Command "adb" -ErrorAction SilentlyContinue
if (-not $AdbCmd) {
    $CommonAdb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $CommonAdb) {
        $AdbDir = Split-Path -Parent $CommonAdb
        $env:PATH = "$AdbDir;$env:PATH"
    }
}

# --- Step 3: Synchronize Flutter Dependencies ---
if (-not $SkipPubGet) {
    Write-Host "[*] Synchronizing Flutter dependencies (flutter pub get)..." -ForegroundColor White
    & $FlutterCmd pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] ERROR: 'flutter pub get' failed with code $LASTEXITCODE." -ForegroundColor Red
        Write-Host "    Check your internet connection and verify pubspec.yaml syntax." -ForegroundColor Yellow
        exit $LASTEXITCODE
    }
    Write-Host "  [OK] Dependencies verified." -ForegroundColor Green
} else {
    Write-Host "  [i] Skipping 'flutter pub get' per -SkipPubGet flag." -ForegroundColor Gray
}

# --- Step 4: Validate Application Configuration (Safe Masked Display) ---
Write-Host "[*] Validating Supabase Backend Configuration..." -ForegroundColor White
$EnvFile = Join-Path $ProjectRoot ".env"
$DartDefines = @()
$ConfiguredUrl = ""
$ConfiguredKey = ""

if (Test-Path $EnvFile) {
    $EnvLines = Get-Content $EnvFile
    foreach ($Line in $EnvLines) {
        $T = $Line.Trim()
        if (($T -eq "") -or ($T.StartsWith("#"))) { continue }
        $Parts = $T -split "=", 2
        if ($Parts.Length -eq 2) {
            $K = $Parts[0].Trim()
            $V = $Parts[1].Trim()
            if (($V.StartsWith('"') -and $V.EndsWith('"')) -or ($V.StartsWith("'") -and $V.EndsWith("'"))) {
                $V = $V.Substring(1, $V.Length - 2)
            }
            if ($K -eq "SUPABASE_URL") { $ConfiguredUrl = $V }
            if ($K -eq "SUPABASE_ANON_KEY") { $ConfiguredKey = $V }
        }
    }
}

if ($ConfiguredUrl -and $ConfiguredKey) {
    $MaskedKey = if ($ConfiguredKey.Length -gt 10) { "$($ConfiguredKey.Substring(0, 8))...[REDACTED]" } else { "********" }
    Write-Host "  [OK] Local .env active:" -ForegroundColor Green
    Write-Host "       SUPABASE_URL: $ConfiguredUrl" -ForegroundColor Gray
    Write-Host "       SUPABASE_ANON_KEY: $MaskedKey" -ForegroundColor Gray
    $DartDefines += "--dart-define=SUPABASE_URL=$ConfiguredUrl"
    $DartDefines += "--dart-define=SUPABASE_ANON_KEY=$ConfiguredKey"
} else {
    Write-Host "  [i] Using built-in demo environment defaults (SupabaseConfig.dart)." -ForegroundColor Yellow
    Write-Host "      (Optional: Copy .env.example to .env to customize remote Supabase credentials)." -ForegroundColor Gray
}

# --- Step 5: Detect Connected Target Device ---
Write-Host "[*] Checking for connected devices & emulators..." -ForegroundColor White
$TargetDeviceId = $DeviceId

if (-not $TargetDeviceId) {
    $DevicesRaw = & $FlutterCmd devices --machine 2>$null | Out-String
    $ParsedDevices = @()
    if ($DevicesRaw) {
        try {
            $ParsedDevices = $DevicesRaw | ConvertFrom-Json
        } catch {}
    }

    $AndroidDevices = @()
    $OtherDevices = @()
    foreach ($Dev in $ParsedDevices) {
        if ($Dev.targetPlatform -like "android*") {
            $AndroidDevices += $Dev
        } else {
            $OtherDevices += $Dev
        }
    }

    if ($AndroidDevices.Count -eq 1) {
        $SingleDev = $AndroidDevices[0]
        $TargetDeviceId = $SingleDev.id
        $DevName = $SingleDev.name
        $DevPlat = $SingleDev.targetPlatform
        Write-Host "  [OK] Automatically selected Android target: $DevName ($TargetDeviceId) [$DevPlat]" -ForegroundColor Green
    } elseif ($AndroidDevices.Count -gt 1) {
        Write-Host ""
        Write-Host "Multiple Android devices detected. Please choose target:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $AndroidDevices.Count; $i++) {
            $d = $AndroidDevices[$i]
            $num = $i + 1
            Write-Host "  [$num] $($d.name) ($($d.id)) - $($d.targetPlatform)" -ForegroundColor White
        }
        $Selection = Read-Host "Enter device number [1-$($AndroidDevices.Count), default 1]"
        if ([string]::IsNullOrWhiteSpace($Selection)) { $Selection = "1" }
        $Idx = 0
        if ([int]::TryParse($Selection, [ref]$Idx) -and ($Idx -ge 1) -and ($Idx -le $AndroidDevices.Count)) {
            $TargetDeviceId = $AndroidDevices[$Idx - 1].id
            Write-Host "  [OK] Selected device: $($AndroidDevices[$Idx - 1].name)" -ForegroundColor Green
        } else {
            $TargetDeviceId = $AndroidDevices[0].id
            Write-Host "  [!] Defaulting to first device: $($AndroidDevices[0].name)" -ForegroundColor Yellow
        }
    } else {
        # No Android devices detected. Check offline emulators or other devices.
        Write-Host "  [*] No active Android phone or running emulator detected." -ForegroundColor Yellow
        
        $EmulatorsOutput = & $FlutterCmd emulators 2>&1 | Out-String
        $AvailableEmulators = @()
        if ($EmulatorsOutput -match "(?m)^([a-zA-Z0-9_\-]+)\s+•\s+([^\n\r]+)") {
            $Lines = $EmulatorsOutput -split "`r?`n"
            foreach ($L in $Lines) {
                if ($L -match "^([a-zA-Z0-9_\-]+)\s+•\s+(.+?)•\s+(.+?)•\s+android") {
                    $AvailableEmulators += $Matches[1].Trim()
                }
            }
        }

        if ($AvailableEmulators.Count -gt 0) {
            $EmuChoice = $AvailableEmulators[0]
            Write-Host ""
            Write-Host "Available Android Emulator found: $EmuChoice" -ForegroundColor Cyan
            $LaunchEmu = Read-Host "Would you like to launch '$EmuChoice'? [Y/n]"
            if ($LaunchEmu -ne "n" -and $LaunchEmu -ne "N") {
                Write-Host "[*] Launching Android emulator '$EmuChoice'..." -ForegroundColor Cyan
                & $FlutterCmd emulators --launch $EmuChoice
                Write-Host "[*] Waiting for emulator to start (this may take 20-30 seconds)..." -ForegroundColor Gray
                Start-Sleep -Seconds 15
                $TargetDeviceId = $EmuChoice
            }
        }

        if (-not $TargetDeviceId) {
            Write-Host ""
            Write-Host "================================================================================" -ForegroundColor Yellow
            Write-Host "HOW TO CONNECT YOUR ANDROID PHONE FOR TESTING:" -ForegroundColor Yellow
            Write-Host "================================================================================" -ForegroundColor Yellow
            Write-Host "1. Connect your phone to this laptop using a USB data cable." -ForegroundColor White
            Write-Host "2. Enable Developer Options on your phone:" -ForegroundColor White
            Write-Host "   - Open Settings > About Phone (or About Device)." -ForegroundColor Gray
            Write-Host "   - Tap 'Build Number' 7 times until you see 'You are now a developer!'." -ForegroundColor Gray
            Write-Host "3. Turn on USB Debugging:" -ForegroundColor White
            Write-Host "   - Go to Settings > System / Additional Settings > Developer Options." -ForegroundColor Gray
            Write-Host "   - Turn ON 'USB Debugging'." -ForegroundColor Gray
            Write-Host "   - If using OPPO / Realme / Xiaomi: also enable 'Install via USB' and" -ForegroundColor Gray
            Write-Host "     'Disable Permission Monitoring'." -ForegroundColor Gray
            Write-Host "4. Authorize Connection:" -ForegroundColor White
            Write-Host "   - Unlock your phone screen. A prompt will appear: 'Allow USB Debugging?'." -ForegroundColor Gray
            Write-Host "   - Check 'Always allow from this computer' and tap 'Allow'." -ForegroundColor Gray
            Write-Host "5. Re-run this launcher: .\scripts\run_smartify.ps1" -ForegroundColor Cyan
            Write-Host "================================================================================" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
    }
}

# --- Step 6: Launch SMARTIFY with Interactive Hot Reload ---
$RunArgs = @("run")
if ($TargetDeviceId) {
    $RunArgs += @("-d", $TargetDeviceId)
}
if ($Release) {
    $RunArgs += "--release"
}
if ($DartDefines.Count -gt 0) {
    $RunArgs += $DartDefines
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "LAUNCHING SMARTIFY (HOT RELOAD ACTIVE)" -ForegroundColor Green
Write-Host "Target Device: $TargetDeviceId" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "Flutter Hot Reload Keyboard Shortcuts:" -ForegroundColor Cyan
Write-Host "  [r] Hot Reload  -> Instantly updates UI changes after saving code" -ForegroundColor White
Write-Host "  [R] Hot Restart -> Rebuilds app state and resets to initial screen" -ForegroundColor White
Write-Host "  [h] Help        -> Shows full list of Flutter runtime shortcuts" -ForegroundColor White
Write-Host "  [d] Detach      -> Detaches the CLI without terminating the app" -ForegroundColor White
Write-Host "  [q] Quit        -> Stops the application and closes session" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""

& $FlutterCmd @RunArgs

$ExitCode = $LASTEXITCODE
if ($ExitCode -ne 0) {
    Write-Host ""
    Write-Host "[!] SMARTIFY session closed with code $ExitCode." -ForegroundColor Yellow
    Write-Host "    If you encountered 'INSTALL_FAILED_VERSION_DOWNGRADE', run:" -ForegroundColor Yellow
    Write-Host "    adb uninstall com.smartify.campus" -ForegroundColor Cyan
    Write-Host "    and re-run .\scripts\run_smartify.ps1" -ForegroundColor Cyan
}

exit $ExitCode
