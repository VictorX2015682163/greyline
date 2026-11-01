"""Run meaningful Godot integration checks without touching the real player save."""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
engine = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
if not engine:
    mac_engine = pathlib.Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"
    if mac_engine.exists():
        engine = str(mac_engine)
if not engine:
    sys.exit("Set GODOT_BIN to the Godot 4 executable.")

try:
    result = subprocess.run(
        [engine, "--headless", "--path", str(ROOT), "--", "--smoke-test"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45,
    )
except subprocess.TimeoutExpired as exc:
    print(exc.stdout.decode() if isinstance(exc.stdout, bytes) else exc.stdout)
    sys.exit("FAIL: engine timed out, possibly due to a failed assertion.")

print(result.stdout)
if result.returncode or "SMOKE PASS:" not in result.stdout or "ERROR:" in result.stdout:
    sys.exit(1)
