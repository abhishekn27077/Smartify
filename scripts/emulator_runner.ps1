# SMARTIFY Virtual Mobile Automation Helper
param(
    [Parameter(Position=0)]
    [string]$Action = "status",
    [Parameter(Position=1)]
    [string]$Param1 = "",
    [Parameter(Position=2)]
    [string]$Param2 = "",
    [int]$X = 0,
    [int]$Y = 0,
    [string]$Name = "",
    [string]$Text = ""
)

$adb = "C:\Users\Abhis\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$device = "emulator-5554"

function Ensure-Online {
    for ($i = 0; $i -lt 15; $i++) {
        $devs = & $adb devices 2>&1 | Out-String
        if ($devs -match "$device\s+device") {
            return $true
        }
        Start-Sleep -Milliseconds 700
    }
    return $false
}

$isOnline = Ensure-Online
if (-not $isOnline) {
    Write-Warning "Device $device not online yet. Status: $(& $adb devices | Out-String)"
}


switch ($Action) {
    "unlock" {
        & $adb -s $device shell input keyevent 224
        & $adb -s $device shell wm dismiss-keyguard
        & $adb -s $device shell input keyevent 82
        Write-Host "Dismissed keyguard and woke up emulator"
    }
    "status" {
        & $adb devices
    }
    "start-app" {
        & $adb -s $device shell am start -n com.smartify.campus/.MainActivity
    }
    "stop-app" {
        & $adb -s $device shell am force-stop com.smartify.campus
    }
    "screenshot" {
        $n = if ($Name) { $Name } elseif ($Param1) { $Param1 } else { "screen" }
        $outPath = "artifacts/qa/emulator_$n.png"
        & $adb -s $device shell screencap -p /sdcard/screen.png
        & $adb -s $device pull /sdcard/screen.png $outPath
        Write-Host "Screenshot saved to $outPath"
    }
    "dump" {
        $n = if ($Name) { $Name } elseif ($Param1) { $Param1 } else { "view" }
        $outPath = "artifacts/qa/emulator_$n.xml"
        & $adb -s $device shell uiautomator dump /sdcard/view.xml
        & $adb -s $device pull /sdcard/view.xml $outPath
        Write-Host "View hierarchy dumped to $outPath"
    }
    "tap" {
        $targetX = if ($X -ne 0) { $X } else { [int]$Param1 }
        $targetY = if ($Y -ne 0) { $Y } else { [int]$Param2 }
        & $adb -s $device shell input tap $targetX $targetY
        Write-Host "Tapped at ($targetX, $targetY)"
    }
    "swipe" {
        $coords = if ($Param1) { $Param1 } else { "$X $Y" }
        & $adb -s $device shell input swipe $coords
    }
    "type" {
        $msg = if ($Text) { $Text } else { $Param1 }
        & $adb -s $device shell input text "$msg"
    }
    "key" {
        $code = if ($Param1) { $Param1 } else { "4" }
        & $adb -s $device shell input keyevent $code
    }
    "inspect" {
        $n = if ($Name) { $Name } elseif ($Param1) { $Param1 } else { "capture" }
        & $adb -s $device shell screencap -p /sdcard/screen.png
        & $adb -s $device pull /sdcard/screen.png "artifacts/qa/emulator_$n.png"
        & $adb -s $device shell uiautomator dump /sdcard/view.xml
        & $adb -s $device pull /sdcard/view.xml "artifacts/qa/emulator_$n.xml"
        Write-Host "Captured emulator_$n.png and emulator_$n.xml"
    }
    default {
        Write-Host "Unknown action: $Action"
    }
}
