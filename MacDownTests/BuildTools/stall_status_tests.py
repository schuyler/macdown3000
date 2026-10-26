"""Exercise the stall diagnostic command with isolated xcodebuild results."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def test_stall_status(status, summary):
    with tempfile.TemporaryDirectory() as directory:
        repo = Path(directory)
        (repo / 'Tools').mkdir()
        shutil.copy2(ROOT / 'Tools/repro-stall.sh', repo / 'Tools/repro-stall.sh')
        (repo / 'bin').mkdir()
        policy = repo / 'bin/taskpolicy'
        policy.write_text(f'#!/bin/sh\necho "{summary}"\nexit {status}\n')
        policy.chmod(0o755)
        env = dict(os.environ, PATH=str(repo / 'bin') + ':' + os.environ['PATH'],
                   TMPDIR=directory)
        result = subprocess.run([str(repo / 'Tools/repro-stall.sh'), '1', '60'],
                                cwd=repo, env=env, capture_output=True)
        assert (result.returncode == 0) == (status == 0 and bool(summary) and not summary.startswith('Executed 0 tests,'))
        print('PASS stall runner status', status, 'summary', bool(summary))


if __name__ == '__main__':
    test_stall_status(0, 'Executed 2 tests, with 0 failures (0 unexpected)')
    test_stall_status(65, 'Executed 2 tests, with 1 failures (0 unexpected)')
    test_stall_status(65, '')
    test_stall_status(0, 'Executed 0 tests, with 0 failures (0 unexpected)')
