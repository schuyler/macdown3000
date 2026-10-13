"""Exercise the shared real file queue across independent processes in a temp home."""
from pathlib import Path
import collections
import plistlib
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='macdown-command-queue-') as directory:
    work = Path(directory)
    binary = work / 'contracts'
    compilation = subprocess.run(['clang', '-fobjc-arc', '-I' + str(ROOT / 'macdown-cmd'),
                    str(ROOT / 'MacDownTests/BuildTools/command_queue_tests.m'),
                    '-framework', 'Foundation', '-o', str(binary)], text=True, capture_output=True, timeout=30)
    if compilation.returncode:
        raise RuntimeError(compilation.stderr)
    cli = work / 'cli'
    (work / 'version.h').write_text('#pragma once\n')
    compilation = subprocess.run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations',
        '-I' + str(ROOT / 'macdown-cmd'), '-I' + str(ROOT / 'MacDown/Code/Utility'),
        '-I' + str(work), str(ROOT / 'MacDownTests/BuildTools/command_queue_cli_tests.m'),
        '-framework', 'Foundation', '-framework', 'AppKit', '-o', str(cli)],
        text=True, capture_output=True, timeout=30)
    if compilation.returncode:
        raise RuntimeError(compilation.stderr)
    queue = work / 'queue'
    def run(*args, check=True):
        result = subprocess.run([str(binary), str(queue), *args], text=True,
                                capture_output=True, timeout=30)
        if check and result.returncode:
            raise RuntimeError(f'Exit {result.returncode}: {result.stdout}\n{result.stderr}')
        return result
    run('enqueue', 'first')
    assert run('peek').stdout.splitlines() == ['/first-0.md']
    run('enqueue', 'second')
    assert run('drain').stdout.splitlines() == ['/first-0.md', '/second-0.md']
    assert not run('drain').stdout
    # A producer after an observed snapshot must survive a later drain.
    run('enqueue', 'snapshot')
    assert run('peek').stdout.splitlines() == ['/snapshot-0.md']
    run('enqueue', 'later')
    assert run('drain').stdout.splitlines() == ['/snapshot-0.md', '/later-0.md']
    # Release producers together through inherited pipes. Consumers really race
    # their flock/append/drain operations; no CFPreferences cache or fake store.
    writers = [subprocess.Popen([str(binary), str(queue), 'enqueue', f'p{i}', '40', 'barrier'],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
               for i in range(8)]
    for writer in writers:
        writer.stdin.write(b'x')
        writer.stdin.flush()
    consumers = [subprocess.Popen([str(binary), str(queue), 'drain', '100'],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(3)]
    for writer in writers:
        output, error = writer.communicate(timeout=30)
        assert writer.returncode == 0, error.decode()
    consumed = []
    for consumer in consumers:
        output, error = consumer.communicate(timeout=30)
        assert consumer.returncode == 0, error.decode()
        consumed.extend(output.decode().splitlines())
    consumed.extend(run('drain').stdout.splitlines())
    expected = [f'/p{i}-{j}.md' for i in range(8) for j in range(40)]
    assert collections.Counter(consumed) == collections.Counter(expected), consumed
    # Invalid input, oversized queue, corrupt persistence and symlinks fail
    # without replacing pending work or following another file.
    run('enqueue', 'keep')
    plist = queue / 'requests.plist'
    before = plist.read_bytes()
    run('invalid')
    run('large')
    assert plist.read_bytes() == before
    plist.write_bytes(b'not a plist')
    assert run('enqueue', 'blocked', check=False).returncode != 0
    assert run('drain', check=False).returncode != 0
    assert plist.read_bytes() == b'not a plist'
    plist.write_bytes(before)
    plist.unlink()
    os.mkfifo(plist, 0o600)
    assert run('drain', check=False).returncode != 0
    plist.unlink()
    plist.symlink_to(work / 'outside-plist')
    assert run('enqueue', 'blocked', check=False).returncode != 0
    plist.unlink()
    plist.write_bytes(before)
    queue.chmod(0o500)
    assert run('enqueue', 'blocked', check=False).returncode != 0
    assert plist.read_bytes() == before
    queue.chmod(0o700)
    lock = queue / '.lock'
    lock.unlink()
    outside = work / 'outside'
    outside.write_text('untouched')
    lock.symlink_to(outside)
    assert run('enqueue', 'blocked', check=False).returncode != 0
    assert outside.read_text() == 'untouched' and plist.read_bytes() == before
    lock.unlink()
    queue.chmod(0o755)
    assert run('drain', check=False).returncode != 0
    queue.chmod(0o700)
    assert run('drain').stdout.splitlines() == ['/keep-0.md']
    assert (plist.stat().st_mode & 0o777) == 0o600
    # Run the entire real CLI source, real stdin and filesystem classification.
    # Argument parsing and launching the OS application are boundary fixtures.
    cli_queue = work / 'cli-queue'
    folder = work / 'folder'
    folder.mkdir()
    result = subprocess.run([str(cli), str(cli_queue), 'relative.md', str(folder)],
        cwd=work, input=b'pipe\0bytes', capture_output=True, timeout=30)
    assert result.returncode == 0 and result.stdout == b'LAUNCH\n', result.stderr
    requests = plistlib.loads((cli_queue / 'requests.plist').read_bytes())
    assert requests == [{'files': [str(work.resolve() / 'relative.md')], 'folders': [str(folder)],
                         'pipedContent': b'pipe\0bytes'}], requests
    before = (cli_queue / 'requests.plist').read_bytes()
    # A terminal invocation with no arguments launches without clearing work.
    terminal, slave = os.openpty()
    try:
        result = subprocess.run([str(cli), str(cli_queue)], stdin=slave,
                                capture_output=True, timeout=30)
        assert result.returncode == 0 and result.stdout == b'LAUNCH\n'
        assert (cli_queue / 'requests.plist').read_bytes() == before
    finally:
        os.close(slave)
        os.close(terminal)
    # An empty pipe still represents valid input for an empty document.
    result = subprocess.run([str(cli), str(cli_queue)], input=b'', capture_output=True, timeout=30)
    assert result.returncode == 0
    requests = plistlib.loads((cli_queue / 'requests.plist').read_bytes())
    assert len(requests) == 2 and requests[-1]['pipedContent'] == b''
    # Reject an oversized stream before EOF. Keep its writer open so this
    # proves bounded input collection rather than the later queue-size check.
    before = (cli_queue / 'requests.plist').read_bytes()
    stream = subprocess.Popen([str(cli), str(cli_queue)], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        try:
            for _ in range(2049):
                stream.stdin.write(b'x' * 16384)
            stream.stdin.flush()
        except BrokenPipeError:
            pass  # A bounded consumer may reject while the writer is active.
        try:
            status = stream.wait(timeout=5)
        except subprocess.TimeoutExpired as error:
            raise AssertionError('Oversized stdin must be rejected without waiting for EOF') from error
        assert status != 0 and not stream.stdout.read()
        assert b'Could not read standard input' in stream.stderr.read()
        assert (cli_queue / 'requests.plist').read_bytes() == before
    finally:
        if stream.poll() is None:
            stream.kill()
            stream.wait(timeout=5)
        for pipe in (stream.stdin, stream.stdout, stream.stderr):
            try:
                pipe.close()
            except BrokenPipeError:
                pass
    # Exactly the input limit reaches serialization. XML/base64 overhead then
    # exceeds the queue limit, so this is a queue error, not a read error.
    result = subprocess.run([str(cli), str(cli_queue)], input=b'x' * (32 * 1024 * 1024),
                            capture_output=True, timeout=30)
    assert result.returncode != 0 and not result.stdout
    assert b'Could not queue command input' in result.stderr
    assert (cli_queue / 'requests.plist').read_bytes() == before
    (cli_queue / 'requests.plist').write_bytes(b'corrupt')
    result = subprocess.run([str(cli), str(cli_queue), 'next.md'], input=b'',
                            capture_output=True, timeout=30)
    assert result.returncode != 0 and not result.stdout and b'Could not queue command input' in result.stderr
    assert (cli_queue / 'requests.plist').read_bytes() == b'corrupt'
    print('PASS command queue: 320 concurrent requests consumed exactly once, binary stdin preserved, snapshots and failures safe')
