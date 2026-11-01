"""Verify raid mode balance, generation and AI with an isolated profile."""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
engine = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
if not engine:
    engine = str(pathlib.Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot")
args = [engine]
if "--capture-modes" not in sys.argv:
    args.append("--headless")
args += ["--path", str(ROOT), "--script", "res://tests/raid_modes_case.gd"]
if "--capture-modes" in sys.argv:
    args += ["--", "--capture-modes"]
try:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=45)
except subprocess.TimeoutExpired as exc:
    print(exc.stdout.decode() if isinstance(exc.stdout, bytes) else exc.stdout)
    sys.exit("FAIL: raid mode tests timed out.")
print(result.stdout)
if result.returncode or "RAID MODES PASS:" not in result.stdout or "ERROR:" in result.stdout:
    sys.exit(1)
