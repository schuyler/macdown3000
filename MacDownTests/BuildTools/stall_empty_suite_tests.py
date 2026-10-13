"""A successful build that executes no tests is not a successful test run."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory() as directory:
    repo = Path(directory)
    (repo / 'Tools').mkdir()
    (repo / 'Tools/repro-stall.sh').write_text(
        (ROOT / 'Tools/repro-stall.sh').read_text())
    (repo / 'bin').mkdir()
    policy = repo / 'bin/taskpolicy'
    policy.write_text('#!/bin/sh\necho "Executed 0 tests, with 0 failures (0 unexpected)"\n')
    policy.chmod(0o755)
    env = dict(os.environ, PATH=str(repo / 'bin') + ':' + os.environ['PATH'],
               TMPDIR=directory)
    result = subprocess.run(['bash', 'Tools/repro-stall.sh', '1', '60'],
                            cwd=repo, env=env, capture_output=True, text=True)
    assert result.returncode != 0, result.stdout
    assert 'NORUN' in result.stdout, result.stdout
    print('PASS empty suite is classified NORUN and fails the runner')
