"""Validate the repository entitlement with real ad-hoc signed sandbox apps."""
from pathlib import Path
import os
import plistlib
import shutil
import signal
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
KEY = 'com.apple.security.temporary-exception.shared-preference.read-only'
APP_DOMAIN = 'app.macdown.macdown3000'
entitlements = plistlib.loads((ROOT / 'MacDownQuickLook/MacDownQuickLook.entitlements').read_bytes())
assert entitlements.get(KEY) == [APP_DOMAIN], 'Only the exact MacDown domain may be shared read-only'
assert 'com.apple.security.temporary-exception.shared-preference.read-write' not in entitlements

def run(args, expected=0):
    process = subprocess.Popen(args, cwd=ROOT, start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        raise RuntimeError(f'Sandbox fixture timeout: {process.communicate()}')
    if process.returncode != expected:
        raise RuntimeError(f'Exit {process.returncode} expected {expected}: {stdout}\n{stderr}')
    return stdout.strip()

with tempfile.TemporaryDirectory(prefix='macdown-sandbox-prefs-') as directory:
    tmp = Path(directory)
    binary = tmp / 'preferences'
    run(['clang', '-fobjc-arc', '-framework', 'Foundation',
         str(ROOT / 'MacDownTests/Sandbox/preferences_contracts.m'), '-o', str(binary)])
    token = uuid.uuid4().hex
    domain = 'org.macdown.audit.preferences.' + token
    value = 'synthetic-audit-value'
    identifiers = []
    try:
        run([str(binary), 'write', domain, value])
        run([str(binary), 'read', domain, value])
        for access in ['denied', 'granted']:
            identifier = 'org.macdown.audit.reader.' + token + '.' + access
            identifiers.append(identifier)
            app = tmp / (access + '.app')
            executable = app / 'Contents/MacOS/reader'
            executable.parent.mkdir(parents=True)
            shutil.copy2(binary, executable)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'reader',
                'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}))
            # Use the actual project policy. Replace its one authorized domain
            # with our synthetic suite; never read the application's real data.
            policy = dict(entitlements)
            if access == 'denied':
                policy.pop(KEY)
            else:
                policy[KEY] = [domain]
            policy_path = tmp / (access + '.entitlements')
            policy_path.write_bytes(plistlib.dumps(policy))
            run(['codesign', '--force', '--sign', '-', '--entitlements', str(policy_path), str(app)])
            result = run([str(executable), 'read', domain, value], expected=1 if access == 'denied' else 0)
            print(f'PASS sandbox {access}: {result}', flush=True)
            if access == 'granted':
                # The read-only sandbox must reject synchronization of a
                # attempted write and leave the shared user's suite intact.
                run([str(executable), 'write', domain, 'unauthorized-replacement'], expected=2)
                run([str(binary), 'read', domain, value])
                print('PASS read-only grant does not permit shared preference mutation', flush=True)
    finally:
        run([str(binary), 'delete', domain, value])
        run([str(binary), 'read', domain, value], expected=1)
        for identifier in identifiers:
            container = Path.home() / 'Library/Containers' / identifier
            if container.exists():
                try:
                    shutil.rmtree(container)
                except PermissionError:
                    # macOS protects container-manager metadata. Report exact
                    # fixture paths and preserve permissions; never broaden access.
                    print(f'Cleanup limited by macOS protected test container metadata: {container}', flush=True)
