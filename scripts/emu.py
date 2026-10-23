import sys
import os
import subprocess
import time

ADB = r"C:\Users\Abhis\AppData\Local\Android\Sdk\platform-tools\adb.exe"
DEVICE = "emulator-5554"

def adb(*args, timeout=10):
    cmd = [ADB, "-s", DEVICE] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return res.stdout.strip(), res.stderr.strip()

def action_unlock():
    adb("shell", "input", "keyevent", "224")
    adb("shell", "wm", "dismiss-keyguard")
    adb("shell", "input", "keyevent", "82")
    print("Unlocked emulator")

def action_start():
    out, err = adb("shell", "am", "start", "-n", "com.smartify.campus/.MainActivity")
    print("Start app:", out)

def action_stop():
    out, err = adb("shell", "am", "force-stop", "com.smartify.campus")
    print("Stop app:", out)

def action_restart():
    action_stop()
    time.sleep(1)
    action_start()

def action_tap(x, y):
    adb("shell", "input", "tap", str(x), str(y))
    print(f"Tapped at ({x}, {y})")

def action_key(code):
    adb("shell", "input", "keyevent", str(code))
    print(f"Sent key {code}")

def action_text(txt):
    adb("shell", "input", "text", str(txt))
    print(f"Sent text: {txt}")

def action_screenshot(name):
    out_dir = r"D:\work\SMARTIFY\artifacts\qa"
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, f"emulator_{name}.png")
    res = subprocess.run([ADB, "-s", DEVICE, "exec-out", "screencap", "-p"], capture_output=True, timeout=10)
    with open(out_file, "wb") as f:
        f.write(res.stdout)
    print(f"Saved screenshot to {out_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: emu.py <action> [args...]")
        sys.exit(1)
    
    act = sys.argv[1].lower()
    if act == "unlock":
        action_unlock()
    elif act == "start":
        action_start()
    elif act == "stop":
        action_stop()
    elif act == "restart":
        action_restart()
    elif act == "tap":
        action_tap(int(sys.argv[2]), int(sys.argv[3]))
    elif act == "key":
        action_key(sys.argv[2])
    elif act == "text":
        action_text(sys.argv[2])
    elif act == "screenshot":
        name = sys.argv[2] if len(sys.argv) > 2 else "screen"
        action_screenshot(name)
    else:
        print("Unknown action:", act)
