"""Exercise manual/tagged release provenance and compiled version consumers."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def step_script(text, name):
    step = text.split('      - name: ' + name + '\n', 1)[1].split('\n      - name:', 1)[0]
    script = step.split('        run: |\n', 1)[1]
    return '\n'.join(line[10:] for line in script.splitlines() if line.startswith('          ')) + '\n'

workflow = (ROOT / '.github/workflows/release.yml').read_text()
resolve_script = step_script(workflow, 'Extract version from tag or input')
with tempfile.TemporaryDirectory(prefix='macdown-release-identity-') as directory:
    repo = Path(directory)
    def run(*args, check=True, env=None, cwd=repo):
        return subprocess.run(args, cwd=cwd, env=env, check=check, capture_output=True, text=True, timeout=30)
    run('git', 'init', '-q')
    run('git', 'config', 'user.name', 'Release Identity Test')
    run('git', 'config', 'user.email', 'release@example.invalid')
    run('git', 'commit', '--allow-empty', '-qm', 'Release base')
    first = run('git', 'rev-parse', 'HEAD').stdout.strip()
    run('git', 'update-ref', 'refs/remotes/origin/main', first)
    run('git', 'tag', 'v1.0.0')
    run('git', 'commit', '--allow-empty', '-qm', 'Release candidate')
    second = run('git', 'rev-parse', 'HEAD').stdout.strip()
    run('git', 'update-ref', 'refs/remotes/origin/release/2.0.0', second)
    (repo / 'bin').mkdir()
    gh = repo / 'bin/gh'
    gh.write_text('#!/bin/sh\nprintf "v1.0.0\\n"\n')
    gh.chmod(0o755)

    def resolve(version, ref='refs/heads/release/2.0.0'):
        output = repo / 'github.env'
        output.write_text('')
        env = dict(os.environ, PATH=str(repo / 'bin') + ':' + os.environ['PATH'],
                   GITHUB_REF=ref, GITHUB_ENV=str(output), PROVIDED_VERSION=version)
        result = run('bash', '-e', '-o', 'pipefail', '-c', resolve_script, check=False, env=env)
        values = dict(line.split('=', 1) for line in output.read_text().splitlines())
        return result, values

    # New manual release is anchored to the exact commit that is built, even
    # when the workflow is selected on a release branch rather than main.
    result, values = resolve('2.0.0-rc.1')
    assert result.returncode == 0, result.stderr
    assert values.get('RELEASE_TAG') == 'v2.0.0-rc.1', values
    assert values.get('RELEASE_COMMIT') == second, values
    assert 'target_commitish: ${{ env.RELEASE_COMMIT }}' in workflow

    # Existing releases may only be rebuilt from their original source.
    result, _ = resolve('1.0.0')
    assert result.returncode != 0, 'Wrong HEAD was accepted for an existing release tag'
    result, _ = resolve('')
    assert result.returncode != 0, 'Auto-selected old release accepted current HEAD'
    run('git', 'checkout', '-q', 'v1.0.0')
    result, values = resolve('', 'refs/tags/v1.0.0')
    assert result.returncode == 0 and values['RELEASE_COMMIT'] == first
    result, values = resolve('1.0.0')
    assert result.returncode == 0 and values['RELEASE_COMMIT'] == first

    # A manually selected development commit must not bypass branch ancestry.
    run('git', 'commit', '--allow-empty', '-qm', 'Unapproved source')
    result, _ = resolve('3.0.0')
    assert result.returncode != 0, 'Unapproved manual release source was accepted'

    (repo / 'Tools').mkdir()
    for name in ['generate_version_header.sh', 'utils.sh']:
        shutil.copy2(ROOT / 'Tools' / name, repo / 'Tools' / name)
    version_dir = repo / 'Dependency/version'
    version_dir.mkdir(parents=True)
    shutil.copy2(ROOT / 'Dependency/version/Makefile', version_dir / 'Makefile')
    env = dict(os.environ, MACDOWN_RELEASE_VERSION='2.0.0-rc.1', MACDOWN_RELEASE_BUILD='873')
    run('make', cwd=version_dir, env=env)
    consumer = version_dir / 'consumer.c'
    consumer.write_text('#include <stdio.h>\n#include "version.h"\nint main(void) { puts(kMPApplicationShortVersion); puts(kMPApplicationBundleVersion); }\n')
    run('clang', str(consumer), '-o', str(version_dir / 'consumer'))
    assert run(str(version_dir / 'consumer')).stdout == '2.0.0-rc.1\n873\n'
    action = (ROOT / '.github/actions/build-macdown/action.yml').read_text()
    assert 'MACDOWN_RELEASE_VERSION: ${{ inputs.marketing-version }}' in action
    assert 'MACDOWN_RELEASE_BUILD: ${{ inputs.build-number }}' in action
    for bad_env in [dict(env, MACDOWN_RELEASE_BUILD=''), dict(env, MACDOWN_RELEASE_BUILD='8bad'),
                    dict(env, MACDOWN_RELEASE_VERSION='bad"version')]:
        before = (version_dir / 'version.h').read_bytes()
        result = run('make', cwd=version_dir, env=bad_env, check=False)
        assert result.returncode != 0 and (version_dir / 'version.h').read_bytes() == before
    print('PASS release commit/tag binding, ancestry gate and compiled release version/build')
