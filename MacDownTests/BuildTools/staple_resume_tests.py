"""Replay actual release steps against private assets and failing remote boundaries."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / '.github/workflows/staple-release.yml').read_text()
SUBMISSION = '11111111-2222-3333-4444-555555555555'


def step(name):
    body = WORKFLOW.split('      - name: ' + name + '\n', 1)[1].split('\n      - name:', 1)[0]
    script = body.split('        run: |\n', 1)[1]
    return '\n'.join(line[10:] for line in script.splitlines() if line.startswith('          ')) + '\n'


BOUNDARY = r'''#!/usr/bin/env python3
from pathlib import Path
import json, os, shutil, sys
root = Path(os.environ['FIXTURE_ROOT'])
args = sys.argv[1:]
tool = Path(sys.argv[0]).name
with (root / 'calls').open('a') as log:
    log.write(tool + ' ' + ' '.join(args) + '\n')
state = json.loads((root / 'release.json').read_text())
if tool == 'gh':
    if args[:2] == ['release', 'view']:
        print('true' if state['isDraft'] else 'false') if '--jq' in args else print(json.dumps(state))
    elif args[:2] == ['release', 'download']:
        Path('build').mkdir(exist_ok=True)
        for asset in (root / 'remote').iterdir():
            shutil.copy2(asset, Path('build') / asset.name)
    elif args[:2] == ['release', 'upload']:
        for asset in args[3:]:
            if asset != '--clobber': shutil.copy2(asset, root / 'remote' / Path(asset).name)
    elif args[:2] == ['release', 'edit']:
        operation = ('metadata' if args[-1] == 'asset-release-notes.md' else 'notes') if '--notes-file' in args else 'publish'
        failure = root / ('fail-' + operation)
        if failure.exists():
            failure.unlink()
            sys.exit(42)
        if operation in ['notes', 'metadata']: state['body'] = Path(args[args.index('--notes-file') + 1]).read_text()
        else: state['isDraft'] = False
        (root / 'release.json').write_text(json.dumps(state))
    else: sys.exit(2)
elif tool == 'xcrun':
    if args[:2] == ['notarytool', 'info']:
        print(json.dumps({'status': 'Accepted' if args[2] == os.environ['EXPECTED_ID'] else 'Invalid'}))
    elif args[:2] == ['notarytool', 'log']:
        sys.exit(0)
    elif args[:2] == ['stapler', 'validate']:
        sys.exit(0 if Path(args[2]).read_bytes().endswith(b'\nTICKET:' + os.environ['EXPECTED_ID'].encode()) else 1)
    elif args[:2] == ['stapler', 'staple']:
        dmg = Path(args[2])
        if b'WRONG-TICKET' in dmg.read_bytes(): sys.exit(1)
        dmg.write_bytes(dmg.read_bytes() + b'\nTICKET:' + os.environ['EXPECTED_ID'].encode())
    else: sys.exit(2)
elif tool == 'codesign':
    dmg = Path(args[-1])
    if b'BAD-SIGNATURE' in dmg.read_bytes(): sys.exit(1)
    if '-dvv' in args: print('Authority=Developer ID Application: Fixture', file=sys.stderr)
elif tool == 'spctl':
    dmg = Path(args[-1])
    sys.exit(0 if dmg.read_bytes().endswith(b'\nTICKET:' + os.environ['EXPECTED_ID'].encode()) else 1)
else: sys.exit(2)
'''


def fixture(failure=None, invalid=None):
    with tempfile.TemporaryDirectory(prefix='macdown-staple-resume-') as directory:
        root = Path(directory)
        (root / 'Tools').mkdir()
        shutil.copy2(ROOT / 'Tools/release_asset_checksums.py', root / 'Tools')
        shutil.copy2(ROOT / 'Tools/release_asset_checksums.py', root / 'macdown-release-asset-checksums.py')
        (root / 'bin').mkdir()
        (root / 'remote').mkdir()
        for tool in ['gh', 'xcrun', 'codesign', 'spctl']:
            path = root / 'bin' / tool
            path.write_text(BOUNDARY)
            path.chmod(0o700)
        data = b'SIGNED-DMG'
        if invalid == 'signature': data += b'BAD-SIGNATURE'
        if invalid == 'ticket': data += b'WRONG-TICKET'
        dmg = root / 'remote/MacDown-1.2.3.dmg'
        dmg.write_bytes(data)
        digest = hashlib.sha256(data).hexdigest()
        if invalid == 'checksum': digest = '0' * 64
        (root / 'remote/MacDown-1.2.3.dmg.sha256').write_text(digest + '  MacDown-1.2.3.dmg\n')
        identity = 'wrong-submission' if invalid == 'submission' else SUBMISSION
        (root / 'release.json').write_text(json.dumps({'id': 'fixture-release', 'isDraft': True, 'tagName': 'v1.2.3',
            'body': 'Submission ID: `' + identity + '`'}))
        (root / 'CHANGELOG.md').write_text('## [1.2.3]\n\nResume publication safely.\n')
        env = dict(os.environ, FIXTURE_ROOT=str(root), EXPECTED_ID=SUBMISSION,
            PATH=str(root / 'bin') + ':' + os.environ['PATH'], VERSION='1.2.3', TAG='v1.2.3',
            RELEASE_COMMIT='a' * 40,
            RUNNER_TEMP=str(root),
            APPLE_ID='fixture@example.invalid', APPLE_APP_PASSWORD='fixture-only', APPLE_TEAM_ID='FIXTURE',
            GITHUB_REPOSITORY='fixture/never-publish', GITHUB_ENV=str(root / 'github.env'))
        if failure: (root / ('fail-' + failure)).touch()

        def replay():
            # Fresh runner storage on each retry, same uploaded release assets.
            for path in (root / 'build').glob('*') if (root / 'build').exists() else []: path.unlink()
            for name in ['Get release info', 'Verify notarization status (with polling)',
                         'Download and verify DMG from release', 'Staple notarization ticket',
                         'Generate updated checksums', 'Persist asset recovery hashes', 'Update release with stapled DMG',
                         'Update release notes', 'Publish release']:
                (root / 'github.env').write_text('')
                script = step(name).replace('${{ github.repository }}', 'fixture/never-publish')
                result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script],
                    cwd=root, env=env, capture_output=True, text=True, timeout=15)
                if result.returncode: return name, result
                for line in (root / 'github.env').read_text().splitlines():
                    key, value = line.split('=', 1)
                    env[key] = value
            return None, None

        stopped, result = replay()
        if invalid:
            assert stopped, invalid
            assert 'gh release upload' not in (root / 'calls').read_text(), invalid
            assert json.loads((root / 'release.json').read_text())['isDraft']
            print('PASS rejected before upload:', invalid, stopped)
            return
        expected = 'Update release notes' if failure == 'notes' else 'Publish release'
        assert stopped == expected, (stopped, result.stdout if result else '')
        assert dmg.read_bytes().endswith(b'\nTICKET:' + SUBMISSION.encode())
        stopped, result = replay()
        assert stopped is None, (stopped, result.stderr if result else '')
        state = json.loads((root / 'release.json').read_text())
        assert not state['isDraft'] and 'Submission ID: `' + SUBMISSION + '`' in state['body']
        assert (root / 'calls').read_text().count('xcrun stapler staple ') == 1
        expected_digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
        assert (root / 'remote/MacDown-1.2.3.dmg.sha256').read_text().startswith(expected_digest)
        print('PASS resume after', failure, 'failure: one ticket, retained submission, verified checksum/signature')


if __name__ == '__main__':
    for failure in ['notes', 'publish']:
        fixture(failure=failure)
    for invalid in ['checksum', 'signature', 'ticket', 'submission']:
        fixture(invalid=invalid)

    # Native final checks are unchanged and remain mandatory on resumed releases.
    final = step('Final comprehensive verification')
    for gate in ['codesign -vvv --strict', 'xcrun stapler validate', 'spctl -a',
                 'hdiutil attach', 'codesign -vvv --deep --strict',
                 'Tools/verify_sparkle_signature.sh', 'shasum -a 256 -c']:
        assert gate in final, gate
    print('PASS final native verification remains mandatory; fixture does not claim native notarization validation')
