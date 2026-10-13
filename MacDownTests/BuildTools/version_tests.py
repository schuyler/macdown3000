"""Exercise version consumers with a real isolated Git repository and C compiler."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix='macdown version ') as directory:
    repo = Path(directory)
    (repo / 'Tools').mkdir()
    for name in ['utils.sh', 'generate_version_header.sh', 'update_build_number.sh']:
        shutil.copy(ROOT / 'Tools' / name, repo / 'Tools' / name)
    (repo / 'Dependency/version').mkdir(parents=True)
    shutil.copy(ROOT / 'Dependency/version/Makefile', repo / 'Dependency/version')

    def run(*args, cwd=repo, **kwargs):
        return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                              text=True, **kwargs)

    run('git', 'init', '-q')
    run('git', 'config', 'user.name', 'Version Test')
    run('git', 'config', 'user.email', 'version-test@example.invalid')
    run('git', 'commit', '--allow-empty', '-qm', 'Initial')
    version_dir = repo / 'Dependency/version'
    header = version_dir / 'version.h'
    run('make', cwd=version_dir)
    assert '"0.0.0.dev1"' in header.read_text()
    original_mtime = header.stat().st_mtime_ns
    run('make', cwd=version_dir)
    assert header.stat().st_mtime_ns == original_mtime

    version = '1.2.3"%n'
    run('git', 'tag', 'v' + version)
    run('make', cwd=version_dir)
    consumer = version_dir / 'consumer.c'
    consumer.write_text('#include <stdio.h>\n#include "version.h"\n'
                        'int main(void) { puts(kMPApplicationShortVersion); }\n')
    run('clang', str(consumer), '-o', str(version_dir / 'consumer'))
    assert run(str(version_dir / 'consumer')).stdout.strip() == version
    run('git', 'commit', '--allow-empty', '-qm', 'Next')
    run('make', cwd=version_dir)
    run('clang', str(consumer), '-o', str(version_dir / 'consumer'))
    assert run(str(version_dir / 'consumer')).stdout.strip() == version + '.post1'
    assert '"2"' in header.read_text()

    if Path('/usr/libexec/PlistBuddy').exists():
        plist = repo / 'Info.plist'
        plist.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                         '<plist version="1.0"><dict/></plist>\n')
        env = dict(os.environ, CI='false', TARGET_BUILD_DIR=str(repo),
                   INFOPLIST_PATH=plist.name)
        run('bash', 'Tools/update_build_number.sh', env=env)
        value = run('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleVersion', str(plist))
        assert value.stdout.strip() == '2'
        short = run('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleShortVersionString', str(plist))
        assert short.stdout.strip() == version + '.post1', short.stdout
        missing = subprocess.run(['bash', 'Tools/update_build_number.sh'], cwd=repo,
                                 env=dict(env, INFOPLIST_PATH='absent.plist'),
                                 capture_output=True)
        assert missing.returncode != 0
    print('PASS real Git versions, stable header mtime, literal C consumer and plist failure')
