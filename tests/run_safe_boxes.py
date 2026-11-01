"""Run insurance-box entitlement and real inventory checks with an isolated save."""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
engine = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
if not engine:
    engine = str(pathlib.Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot")
try:
    result = subprocess.run(
        [engine, "--headless", "--path", str(ROOT), "--script", "res://tests/safe_boxes_case.gd"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45,
    )
except subprocess.TimeoutExpired as exc:
    print(exc.stdout.decode() if isinstance(exc.stdout, bytes) else exc.stdout)
    sys.exit("FAIL: safe-box tests timed out.")
print(result.stdout)
if result.returncode or "SAFE BOX PASS:" not in result.stdout or "ERROR:" in result.stdout:
    sys.exit(1)
