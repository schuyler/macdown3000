"""Exercise the real launch gate against private app/preference boundaries."""
from pathlib import Path
import json
import os
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'Tools/smoke_launch.sh'
BOUNDARY = '''#!/usr/bin/env python3
from pathlib import Path
import json,os,sys,time
p=Path(os.environ['FIXTURE_STORE'])
d=json.loads(p.read_text()) if p.exists() else {}
if Path(sys.argv[0]).name == 'defaults':
    action,domain=sys.argv[1:3]
    if action=='delete': d.pop(domain,None)
    elif action=='write': d.setdefault(domain,{})[sys.argv[3]]=sys.argv[4]
    elif action=='read':
        value=d.get(domain,{}).get(sys.argv[3])
        with open(os.environ['FIXTURE_READS'],'a') as log:
            log.write(json.dumps([domain,sys.argv[3],value])+'\\n')
        if value is None: sys.exit(1)
        print(value);sys.exit(0)
    else: sys.exit(2)
    p.write_text(json.dumps(d))
else:
    domain=os.environ['FIXTURE_DOMAIN']
    if os.environ['FIXTURE_MIGRATES']=='yes':
        values=d.setdefault(domain,{})
        if not values.get('MPDidMigrateFromLegacyBundleIdentifier'):
            values.update(d.get('com.uranusjr.macdown',{}))
            values['MPDidMigrateFromLegacyBundleIdentifier']='1'
        p.write_text(json.dumps(d))
    time.sleep(30)
'''
with tempfile.TemporaryDirectory(prefix='macdown-smoke-contract-') as directory:
    root = Path(directory)
    tools = root / 'bin'
    tools.mkdir()
    defaults = tools / 'defaults'
    defaults.write_text(BOUNDARY)
    defaults.chmod(0o700)
    for suffix, migrates in [('', True), ('-debug', True), ('-debug', False)]:
        domain = 'app.macdown.macdown3000' + suffix
        app = root / ('Debug.app' if suffix else 'Release.app')
        executable = app / 'Contents/MacOS/Fixture'
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_text(BOUNDARY)
        executable.chmod(0o700)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': domain, 'CFBundleExecutable': 'Fixture'}))
        store = root / 'preferences.json'
        store.write_text('{}')
        reads = root / 'reads.jsonl'
        reads.write_text('')
        env = dict(os.environ, PATH=str(tools)+':'+os.environ['PATH'],
                   GITHUB_ACTIONS='true', FIXTURE_STORE=str(store), FIXTURE_READS=str(reads),
                   FIXTURE_DOMAIN=domain, FIXTURE_MIGRATES='yes' if migrates else 'no')
        result = subprocess.run(['bash', str(SCRIPT), str(app)], env=env,
                                capture_output=True, text=True, timeout=30)
        if migrates:
            assert result.returncode == 0, result.stderr
            assert 'migration passed' in result.stdout
            observed = [json.loads(line) for line in reads.read_text().splitlines()]
            assert observed == [[domain, 'MPDidMigrateFromLegacyBundleIdentifier', '1'],
                                [domain, 'testMigrationKey', 'testMigrationValue'],
                                [domain, 'editorBaseFontName', 'Monaco']], observed
            # EXIT cleanup removes both fixture preference domains.
            assert domain not in json.loads(store.read_text())
        else:
            assert result.returncode != 0, 'A missing migration must never be reported as passed'
            assert 'migration passed' not in result.stdout
        print('PASS', domain, 'migration accepted' if migrates else 'missing migration rejected')
