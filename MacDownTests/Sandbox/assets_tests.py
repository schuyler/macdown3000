"""Consume real Core CSS in signed sandbox bundles, using only UUID fixtures."""
from pathlib import Path
import os
import plistlib
import shutil
import signal
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
FILE_KEY = 'com.apple.security.temporary-exception.files.home-relative-path.read-only'
SCOPES = ['/Library/Application Support/MacDown 3000/Styles/',
          '/Library/Application Support/MacDown 3000/Prism/themes/']
policy = plistlib.loads((ROOT / 'MacDownQuickLook/MacDownQuickLook.entitlements').read_bytes())
assert policy.get(FILE_KEY) == SCOPES, 'Only the two asset directories may be read'
assert policy.get('com.apple.security.temporary-exception.shared-preference.read-only') == ['app.macdown.macdown3000']
assert not any('read-write' in key and 'temporary-exception' in key for key in policy)

def run(args):
    process = subprocess.Popen(args, cwd=ROOT, start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        raise RuntimeError(f'Asset sandbox timeout: {process.communicate()}')
    if process.returncode:
        raise RuntimeError(f'Exit {process.returncode}: {stdout}\n{stderr}')
    return stdout.strip()

with tempfile.TemporaryDirectory(prefix='macdown-sandbox-assets-') as directory:
    tmp = Path(directory)
    flags = ['-I', str(ROOT / 'Pods/Headers/Public'), '-I', str(ROOT / 'Pods/hoedown/src')]
    objects = []
    for source in sorted((ROOT / 'Pods/hoedown/src').glob('*.c')) + [ROOT / 'MacDown/Code/Extension/hoedown_html_patch.c']:
        obj = tmp / (source.stem + '.o')
        run(['clang', *flags, '-c', str(source), '-o', str(obj)])
        objects.append(str(obj))
    binary = tmp / 'reader'
    run(['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation', *flags,
         str(ROOT / 'MacDownTests/Sandbox/assets_contracts.m'),
         str(ROOT / 'MacDownCore/MPQuickLookRenderer.m'),
         str(ROOT / 'MacDownCore/MPQuickLookPreferences.m'), *objects, '-o', str(binary)])
    token = uuid.uuid4().hex
    home = Path.home()
    root = home / 'Library/Application Support/MacDown 3000'
    fixtures = {root / 'Styles' / f'AuditSandboxAsset-{token}.css': f'/* USER_STYLE_{token} */',
                root / 'Prism/themes' / f'prism-auditsandboxasset-{token}.css': f'/* USER_THEME_{token} */',
                root / f'AuditSandboxOutside-{token}.css': 'isolated outside-scope fixture'}
    created_directories = []
    created_files = []
    identifiers = []
    try:
        for path, content in fixtures.items():
            missing = []
            current = path.parent
            while not current.exists():
                missing.append(current)
                current = current.parent
            for parent in reversed(missing):
                parent.mkdir()
                created_directories.append(parent)
            with path.open('x') as stream:
                stream.write(content)
            created_files.append(path)
            path.chmod(0o600)
        for access in ['denied', 'granted']:
            identifier = f'org.macdown.audit.assetreader.{token}.{access}'
            identifiers.append(identifier)
            app = tmp / (access + '.app')
            executable = app / 'Contents/MacOS/reader'
            executable.parent.mkdir(parents=True)
            shutil.copy2(binary, executable)
            resources = app / 'Contents/Resources'
            for relative, content in {
                f'Styles/AuditSandboxAsset-{token}.css': f'/* BUNDLE_STYLE_{token} */',
                f'Prism/themes/prism-auditsandboxasset-{token}.css': f'/* BUNDLE_THEME_{token} */'}.items():
                file = resources / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(content)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'reader',
                'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}))
            actual_policy = dict(policy)
            if access == 'denied':
                actual_policy.pop(FILE_KEY)
            entitlements = tmp / (access + '.entitlements')
            entitlements.write_bytes(plistlib.dumps(actual_policy))
            run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlements), str(app)])
            print(run([str(executable), token, 'user' if access == 'granted' else 'blocked', 'sandbox']), flush=True)
            if access == 'granted':
                # Missing user files must still select bundled copies.
                for path in list(fixtures)[:2]:
                    assert path.read_text() == fixtures[path]
                    path.unlink()
                print(run([str(executable), token, 'bundle', 'sandbox']), flush=True)
        for path, content in fixtures.items():
            if path.exists():
                assert path.read_text() == content, 'Read-only reader may not alter any fixture'
    finally:
        for path in created_files:
            path.unlink(missing_ok=True)
        for parent in reversed(created_directories):
            try:
                parent.rmdir()
            except OSError:
                pass
        for identifier in identifiers:
            container = home / 'Library/Containers' / identifier
            if container.exists():
                try:
                    shutil.rmtree(container)
                except PermissionError:
                    print(f'Protected fixture container remains: {container}', flush=True)
