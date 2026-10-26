"""Exercise build failure handling in isolated temporary repositories."""
import os
import shutil
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



if __name__ == '__main__':
    for scenario in ['regeneration-failure', 'verification-failure', 'success']:
        test_regeneration(scenario)
