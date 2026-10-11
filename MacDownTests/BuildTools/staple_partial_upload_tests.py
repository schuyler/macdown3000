"""Recover real shell steps after exactly one remote release asset was replaced."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from staple_resume_tests import ROOT, SUBMISSION, BOUNDARY, step

PARTIAL_BOUNDARY = BOUNDARY.replace(
    "if asset != '--clobber': shutil.copy2(asset, root / 'remote' / Path(asset).name)",
    """if (root / 'partial-upload').exists() and asset.endswith('.sha256'):
                sys.exit(42)
            if asset != '--clobber': shutil.copy2(asset, root / 'remote' / Path(asset).name)""")


with tempfile.TemporaryDirectory(prefix='macdown-partial-assets-') as directory:
    root = Path(directory)
    for name in ['bin', 'remote', 'Tools']:
        (root / name).mkdir()
    shutil.copy2(ROOT / 'Tools/release_asset_checksums.py', root / 'Tools')
    shutil.copy2(ROOT / 'Tools/release_asset_checksums.py', root / 'macdown-release-asset-checksums.py')
    for tool in ['gh', 'xcrun', 'codesign', 'spctl']:
        path = root / 'bin' / tool
        path.write_text(PARTIAL_BOUNDARY)
        path.chmod(0o700)
    dmg = root / 'remote/MacDown-1.2.3.dmg'
    dmg.write_bytes(b'SIGNED-DMG')
    original = hashlib.sha256(dmg.read_bytes()).hexdigest()
    sidecar = root / 'remote/MacDown-1.2.3.dmg.sha256'
    sidecar.write_text(original + '  ' + dmg.name + '\n')
    info = {'id': 'fixture-release', 'isDraft': True, 'tagName': 'v1.2.3',
            'body': 'Submission ID: `' + SUBMISSION + '`'}
    (root / 'release.json').write_text(json.dumps(info))
    (root / 'CHANGELOG.md').write_text('## [1.2.3]\n\nVerified asset recovery.\n')
    env = dict(os.environ, FIXTURE_ROOT=str(root), EXPECTED_ID=SUBMISSION,
        PATH=str(root / 'bin') + ':' + os.environ['PATH'], VERSION='1.2.3', TAG='v1.2.3',
        RELEASE_COMMIT='a' * 40, APPLE_ID='fixture@example.invalid', APPLE_APP_PASSWORD='fixture-only',
        RUNNER_TEMP=str(root),
        APPLE_TEAM_ID='FIXTURE', GITHUB_ENV=str(root / 'github.env'), GITHUB_REPOSITORY='fixture/never-publish')

    def execute(name, check=True):
        (root / 'github.env').write_text('')
        script = step(name).replace('${{ github.repository }}', 'fixture/never-publish').replace('sleep $wait_time', ':')
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script],
            cwd=root, env=env, text=True, capture_output=True, timeout=15)
        if check: assert result.returncode == 0, (name, result.stderr)
        for line in (root / 'github.env').read_text().splitlines():
            key, value = line.split('=', 1)
            env[key] = value
        return result

    for name in ['Get release info', 'Verify notarization status (with polling)',
                 'Download and verify DMG from release', 'Staple notarization ticket', 'Generate updated checksums']:
        execute(name)
    # Failure to persist hashes must stop with both remote assets untouched.
    (root / 'fail-metadata').touch()
    assert execute('Persist asset recovery hashes', check=False).returncode != 0
    assert dmg.read_bytes() == b'SIGNED-DMG' and sidecar.read_text().startswith(original)
    assert 'gh release upload' not in (root / 'calls').read_text()
    execute('Persist asset recovery hashes')
    preserved = json.loads((root / 'release.json').read_text())['body']
    assert info['body'] in preserved and 'macdown-assets:' in preserved
    (root / 'partial-upload').touch()
    assert execute('Update release with stapled DMG', check=False).returncode != 0
    assert dmg.read_bytes().endswith(SUBMISSION.encode()) and sidecar.read_text().startswith(original)
    (root / 'partial-upload').unlink()
    # Retry from a fresh runner with the same remote draft, now a mismatched pair.
    shutil.rmtree(root / 'build')
    execute('Get release info')
    execute('Verify notarization status (with polling)')
    execute('Download and verify DMG from release')
    execute('Staple notarization ticket')
    execute('Generate updated checksums')
    execute('Persist asset recovery hashes')
    execute('Update release with stapled DMG')
    execute('Update release notes')
    execute('Publish release')
    assert not json.loads((root / 'release.json').read_text())['isDraft']
    assert sidecar.read_text().startswith(hashlib.sha256(dmg.read_bytes()).hexdigest())
    assert (root / 'calls').read_text().count('xcrun stapler staple ') == 1
    print('PASS interrupted checksum upload resumes with previously persisted hashes; metadata failure prevents upload')

    # Repair refuses unknown bytes, published releases, wrong tags or commits,
    # and absent/ambiguous hashes; it must never rewrite the supplied sidecar.
    downloaded = root / 'build' / dmg.name
    checksum = root / 'build' / sidecar.name
    saved_info = dict(info, body=preserved)
    for invalid in ['unknown-bytes', 'published', 'wrong-tag', 'wrong-commit', 'absent', 'ambiguous']:
        candidate = dict(saved_info)
        downloaded.write_bytes(dmg.read_bytes())
        if invalid == 'unknown-bytes': downloaded.write_bytes(b'UNRECOGNIZED-DMG')
        if invalid == 'published': candidate['isDraft'] = False
        if invalid == 'wrong-tag': candidate['tagName'] = 'v9.9.9'
        if invalid == 'wrong-commit': candidate['body'] = candidate['body'].replace('a' * 40, 'b' * 40)
        if invalid == 'absent': candidate['body'] = info['body']
        if invalid == 'ambiguous': candidate['body'] += '\n' + next(line for line in preserved.splitlines() if line.startswith('<!-- macdown-assets:'))
        (root / 'repair-info.json').write_text(json.dumps(candidate))
        checksum.write_text('keep-me')
        result = subprocess.run(['python3', str(root / 'Tools/release_asset_checksums.py'), 'repair',
            env['TAG'], env['RELEASE_COMMIT'], str(root / 'repair-info.json'), str(downloaded), str(checksum)],
            cwd=root, capture_output=True, timeout=15)
        assert result.returncode != 0 and checksum.read_text() == 'keep-me', invalid
    print('PASS unknown hashes/provenance/non-draft/ambiguous metadata rejected without sidecar mutation')

    # A complete published pair supports a read-only replay of all real steps.
    published = json.loads((root / 'release.json').read_text())
    published_bytes = dmg.read_bytes()
    published_checksum = sidecar.read_bytes()
    (root / 'calls').write_text('')
    shutil.rmtree(root / 'build')
    for name in ['Get release info', 'Verify notarization status (with polling)',
                 'Download and verify DMG from release', 'Staple notarization ticket',
                 'Generate updated checksums', 'Persist asset recovery hashes',
                 'Update release with stapled DMG', 'Update release notes', 'Publish release']:
        execute(name)
    calls = (root / 'calls').read_text()
    assert 'gh release upload' not in calls and 'gh release edit' not in calls
    assert 'xcrun stapler staple ' not in calls
    assert dmg.read_bytes() == published_bytes and sidecar.read_bytes() == published_checksum
    assert json.loads((root / 'release.json').read_text()) == published
    # Even known persisted hashes must never repair a published mismatch.
    published['body'] = preserved
    (root / 'release.json').write_text(json.dumps(published))
    sidecar.write_text(original + '  ' + dmg.name + '\n')
    shutil.rmtree(root / 'build')
    execute('Get release info')
    assert execute('Download and verify DMG from release', check=False).returncode != 0
    assert sidecar.read_text().startswith(original)
    print('PASS verified published assets replay without mutations; published mismatch stays rejected')
