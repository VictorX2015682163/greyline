"""Exercise the real merchant signing tool and Godot redemption with temporary keys only."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("safe_box_admin", ROOT / "tools/safe_box_admin.py")
admin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(admin)
engine = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
if not engine:
    engine = str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot")


with tempfile.TemporaryDirectory(prefix="greyline-manual-safe-") as folder:
    temporary = Path(folder)
    merchant = temporary / "merchant"
    config = temporary / "manual.json"
    key = admin.setup(merchant, config)
    initial_key = key.read_bytes()
    admin.setup(merchant, config)
    assert initial_key == key.read_bytes(), "Setup cannot silently replace the merchant key"
    assert key.stat().st_mode & 0o077 == 0, "Merchant private keys are owner-readable only"
    buyer = "GL-0123456789ABCDEF0123"
    code = admin.issue(merchant, config, buyer, "isolated-test-receipt")
    assert admin.issue(merchant, config, buyer, "isolated-test-receipt") == code
    for invalid in ["another-buyer", "GL-0123456789ABCDEF0124"]:
        try:
            admin.issue(merchant, config, invalid, "isolated-test-receipt")
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid buyers or reused receipts must not receive a code")
    import base64
    raw = base64.urlsafe_b64decode(code.split(".")[1] + "==")
    payload = json.loads(raw)

    def altered(**changes):
        updated = dict(payload, **changes)
        message = json.dumps(updated, separators=(",", ":")).encode("ascii")
        signature = admin.openssl("dgst", "-sha256", "-sign", key, data=message)
        return "GL1." + admin.encode(message) + "." + admin.encode(signature)

    fixture = {"config": str(config), "buyer": buyer, "code": code,
               "tampered": "GL1." + admin.encode(raw + b" ") + "." + code.split(".")[2],
               "wrong_product": altered(product="another-product"),
               "wrong_amount": altered(amount_fen=1),
               "bad_transaction": altered(transaction="invalid")}
    foreign_config = temporary / "foreign.json"
    foreign_merchant = temporary / "foreign-merchant"
    admin.setup(foreign_merchant, foreign_config)
    fixture["foreign_key"] = admin.issue(foreign_merchant, foreign_config, buyer, "other-receipt")
    empty_config = temporary / "empty.json"
    empty_config.write_text("{}")
    fixture["empty_config"] = str(empty_config)
    fixture_path = temporary / "fixture.json"
    fixture_path.write_text(json.dumps(fixture))
    capture = "--capture-manual" in sys.argv
    command = [engine] + ([] if capture else ["--headless"])
    command += ["--path", str(ROOT), "--script", "res://tests/manual_safe_purchase_case.gd",
                "--", "--manual-fixture=" + str(fixture_path)]
    if capture:
        command.append("--capture-manual")
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=45)
    except subprocess.TimeoutExpired as exc:
        print(exc.stdout.decode() if isinstance(exc.stdout, bytes) else exc.stdout)
        sys.exit("FAIL: manual activation checks timed out.")
    print(result.stdout)
    if result.returncode or "MANUAL SAFE PASS:" not in result.stdout or "ERROR:" in result.stdout:
        sys.exit(1)
