"""Exercise build failure handling in isolated temporary repositories."""
import os
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
        (repo / 'scripts/regenerate.sh').write_text(
            (ROOT / 'scripts/regenerate-golden-files.sh').read_text())
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
        result = subprocess.run(['bash', 'scripts/regenerate.sh'], cwd=repo,
                                env=env, capture_output=True)
        assert (result.returncode == 0) == (stage == 'success'), result.stderr
        for name in FILES:
            assert (repo / 'MacDownTests' / name).read_text() == DISABLED
        print('PASS', stage, 'restores source definitions and reports status')


def test_css_generation():
    with tempfile.TemporaryDirectory() as directory:
        repo = Path(directory)
        (repo / 'node_modules/.bin').mkdir(parents=True)
        for name in ['index.sass', 'package-lock.json']:
            (repo / name).touch()
        (repo / 'Makefile').write_text(
            (ROOT / 'Tools/GitHub-style-generator/Makefile').read_text())
        sass = repo / 'node_modules/.bin/sass'
        sass.write_text('#!/bin/sh\necho bad\nexit 42\n')
        sass.chmod(0o755)
        output = repo / 'existing.css'
        output.write_text('good')
        cmd = ['make', '-B', 'target=existing.css']
        result = subprocess.run(cmd, cwd=repo, capture_output=True)
        assert result.returncode and output.read_text() == 'good'
        sass.write_text('#!/bin/sh\necho ".markdown-body {color:red;}"\n')
        result = subprocess.run(cmd, cwd=repo, capture_output=True)
        assert result.returncode == 0
        assert output.read_text() == 'body {color:red;}\n'
        assert not list(repo.glob('*.sass.*')) and not list(repo.glob('*.css.*'))
        print('PASS CSS failure preserves artifact; success replaces it atomically')


def test_stall_status(status, summary):
    with tempfile.TemporaryDirectory() as directory:
        repo = Path(directory)
        (repo / 'Tools').mkdir()
        (repo / 'Tools/repro-stall.sh').write_text(
            (ROOT / 'Tools/repro-stall.sh').read_text())
        (repo / 'bin').mkdir()
        policy = repo / 'bin/taskpolicy'
        policy.write_text(f'#!/bin/sh\necho "{summary}"\nexit {status}\n')
        policy.chmod(0o755)
        env = dict(os.environ, PATH=str(repo / 'bin') + ':' + os.environ['PATH'],
                   TMPDIR=directory)
        result = subprocess.run(['bash', 'Tools/repro-stall.sh', '1', '60'],
                                cwd=repo, env=env, capture_output=True)
        assert (result.returncode == 0) == (status == 0 and bool(summary))
        print('PASS stall runner status', status, 'summary', bool(summary))


if __name__ == '__main__':
    for scenario in ['regeneration-failure', 'verification-failure', 'success']:
        test_regeneration(scenario)
    test_css_generation()
    test_stall_status(0, 'Executed 2 tests, with 0 failures (0 unexpected)')
    test_stall_status(65, 'Executed 2 tests, with 1 failures (0 unexpected)')
    test_stall_status(65, '')
