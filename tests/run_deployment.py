"""Check permissive admission locally and across actual ENet peers."""
import subprocess
import sys

from run_multiplayer import ENGINE, ROOT, run_case

result = subprocess.run(
    [ENGINE, '--headless', '--path', str(ROOT), '--script',
     'res://tests/deployment_case.gd'],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
print(result.stdout, flush=True)
if result.returncode or 'ERROR:' in result.stdout or 'DEPLOYMENT PASS:' not in result.stdout:
    sys.exit(1)
try:
    run_case(['host', 'client'], script='deployment_case.gd')
    run_case(['fallback'], script='deployment_case.gd')
    run_case(['host', 'client'], script='deployment_case.gd', mode='机密')
    run_case(['dedicated', 'dedicated_client'], script='deployment_case.gd', mode='机密')
except RuntimeError as exc:
    sys.exit(str(exc))
