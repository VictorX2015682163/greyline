"""Exercise real ENet peers and AI fill with isolated saves and captured logs."""
import os
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
ENGINE = os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
if not ENGINE:
    ENGINE = str(pathlib.Path.home() / 'Downloads/Godot.app/Contents/MacOS/Godot')


def free_udp_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('', 0))
        return probe.getsockname()[1]


def run_case(roles, port=None, script='multiplayer_case.gd', mode='普通'):
    port = port or free_udp_port()
    discovery_port = free_udp_port()
    while discovery_port == port:
        discovery_port = free_udp_port()
    with tempfile.TemporaryDirectory(prefix='greyline-net-') as folder:
        peers = []
        try:
            for role in roles:
                log = pathlib.Path(folder) / (role + '.log')
                with log.open('w') as out:
                    process = subprocess.Popen(
                        [ENGINE, '--headless', '--path', str(ROOT), '--script',
                         f'res://tests/{script}', '--', f'--case={role}', f'--port={port}',
                         f'--discovery-port={discovery_port}', f'--mode={mode}']
                        + (['--dedicated'] if role == 'dedicated' else []),
                        stdout=out, stderr=subprocess.STDOUT)
                peers.append((role, process, log))
                if role in ('host', 'takeover_host', 'dedicated', 'discovery_host'):
                    deadline = time.monotonic() + 10
                    while f'NET READY {role}' not in log.read_text():
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise RuntimeError('Host did not become ready')
                        time.sleep(.1)
            deadline = time.monotonic() + 35
            while any(p.poll() is None for _, p, _ in peers):
                for role, process, log in peers:
                    if 'ERROR:' in log.read_text():
                        raise RuntimeError(f'{role} reported an engine/test error')
                if time.monotonic() > deadline:
                    raise RuntimeError('Multiplayer case timed out')
                time.sleep(.1)
            for role, process, log in peers:
                if process.returncode or f'NET PASS {role}:' not in log.read_text():
                    raise RuntimeError(f'{role} integration failed')
        finally:
            for role, process, log in peers:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                print(log.read_text(), flush=True)


if __name__ == '__main__':
    try:
        run_case(['host', 'client'], script='deployment_case.gd')
        run_case(['host', 'client'], script='deployment_case.gd', mode='机密')
        run_case(['dedicated', 'dedicated_client'], script='deployment_case.gd', mode='机密')
        run_case(['host', 'client'])
        run_case(['fallback'])
        run_case(['host', 'client'], mode='机密')
        run_case(['fallback'], mode='机密')
        run_case(['takeover_host', 'dropout'], script='connection_case.gd')
        run_case(['dedicated', 'dedicated_client'], script='connection_case.gd')
        run_case(['autonomy'], script='bot_case.gd')
        run_case(['perception'], script='perception_case.gd')
        run_case(['discovery_host', 'discovery_client'], script='matching_case.gd')
        run_case(['no_room'], script='matching_case.gd')
    except RuntimeError as exc:
        sys.exit(str(exc))
