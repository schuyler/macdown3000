"""Exercise build failure handling in isolated temporary repositories."""
import os
import shutil
import signal
import sys
import time
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FILES = ['MPMarkdownRenderingTests.m', 'MPSyntaxHighlightingTests.m',
         'MPMathJaxRenderingTests.m']
DISABLED = '// #define REGENERATE_GOLDEN_FILES\n// other source\n'


def test_regeneration(stage):
    with tempfile.TemporaryDirectory() as directory:
        repo = Path(directory)
        (repo / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/regenerate-golden-files.sh',
                     repo / 'scripts/regenerate.sh')
        (repo / 'MacDown 3000.xcworkspace').mkdir()
        (repo / 'MacDownTests/Fixtures').mkdir(parents=True)
        (repo / 'bin').mkdir()
        for name in FILES:
            (repo / 'MacDownTests' / name).write_text(DISABLED)
        fake = repo / 'bin/xcodebuild'
        verification_status = 31 if stage == 'verification-failure' else 0
        fake.write_text(f'''#!/bin/bash
if [[ -e "$PWD/run-marker" ]]; then exit {verification_status}; fi
touch "$PWD/run-marker"
''' + ('exit 42\n' if stage == 'regeneration-failure' else '''
while [[ $# -gt 0 ]]; do
    if [[ "$1" == '-derivedDataPath' ]]; then path="$2"; break; fi
    shift
done
fixtures="$path/Build/Products/Debug/MacDown 3000.app/Contents/PlugIns/MacDownTests.xctest/Contents/Resources/Fixtures"
mkdir -p "$fixtures"
echo '<p>new</p>' > "$fixtures/new.html"
echo 'Regenerated golden file: new.html'
exit 65
'''))
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(repo / 'bin') + ':' + os.environ['PATH'],
                   TMPDIR=directory)
        result = subprocess.run([str(repo / 'scripts/regenerate.sh')], cwd=repo,
                                env=env, capture_output=True)
        assert (result.returncode == 0) == (stage == 'success'), result.stderr
        for name in FILES:
            assert (repo / 'MacDownTests' / name).read_text() == DISABLED
        print('PASS', stage, 'restores source definitions and reports status')



def test_regeneration_signal(interruption):
    with tempfile.TemporaryDirectory() as directory:
        repo = Path(directory)
        (repo / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/regenerate-golden-files.sh',
                     repo / 'scripts/regenerate.sh')
        (repo / 'MacDown 3000.xcworkspace').mkdir()
        (repo / 'MacDownTests/Fixtures').mkdir(parents=True)
        (repo / 'bin').mkdir()
        for name in FILES:
            (repo / 'MacDownTests' / name).write_text(DISABLED)
        fake = repo / 'bin/xcodebuild'
        # The marker is emitted only after the real script enabled every file.
        # Keep the first build alive until the test interrupts its process group.
        fake.write_text(f'#!{sys.executable}\nfrom pathlib import Path\nimport time\n'
                        'Path("build-started").write_text("started")\ntime.sleep(60)\n')
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(repo / 'bin') + ':' + os.environ['PATH'],
                   TMPDIR=directory)
        process = subprocess.Popen([str(repo / 'scripts/regenerate.sh')], cwd=repo,
                                   env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 30
            while not (repo / 'build-started').exists():
                assert process.poll() is None, 'Regeneration exited before the build started'
                assert time.monotonic() < deadline, 'Timed out waiting for first build'
                time.sleep(0.01)
            for name in FILES:
                assert (repo / 'MacDownTests' / name).read_text() == DISABLED.replace(
                    '// #define', '#define'), 'Signal must arrive during enabled regeneration'
            os.killpg(process.pid, interruption)
            stdout, stderr = process.communicate(timeout=30)
            assert process.returncode != 0, (stdout, stderr)
            for name in FILES:
                assert (repo / 'MacDownTests' / name).read_text() == DISABLED
            assert not list((repo / 'MacDownTests/Fixtures').iterdir()), 'Interrupted build must not publish fixtures'
        finally:
            # Kill descendants too if an assertion or timeout interrupted cleanup.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=5)
        print('PASS', interruption.name, 'during regeneration restores source definitions')


if __name__ == '__main__':
    for scenario in ['regeneration-failure', 'verification-failure', 'success']:
        test_regeneration(scenario)
    for interruption in [signal.SIGTERM, signal.SIGINT]:
        test_regeneration_signal(interruption)
