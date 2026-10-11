"""Persist trusted draft asset hashes before GitHub replaces either asset."""
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import os

MARKER = '<!-- macdown-assets: '


def release_info(path, tag):
    info = json.loads(Path(path).read_text())
    if info.get('isDraft') is not True or info.get('tagName') != tag:
        raise ValueError('Asset recovery requires the matching draft release')
    if not isinstance(info.get('body'), str):
        raise ValueError('Release body is missing')
    return info


def metadata_lines(body):
    return [line for line in body.splitlines() if line.startswith(MARKER)]


def atomic_write(path, content):
    destination = Path(path)
    with tempfile.NamedTemporaryFile(mode='w', dir=destination.parent, delete=False) as file:
        temporary = Path(file.name)
        try:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def main(args):
    command, tag, commit, info_path, *rest = args
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid source commit')
    info = release_info(info_path, tag)
    if command == 'record':
        original, stapled, output = rest
        if not all(re.fullmatch(r'[0-9a-f]{64}', digest) for digest in [original, stapled]):
            raise ValueError('Invalid SHA256')
        body = '\n'.join(line for line in info['body'].splitlines() if not line.startswith(MARKER))
        metadata = json.dumps({'tag': tag, 'commit': commit, 'sha256': [original, stapled]}, separators=(',', ':'))
        atomic_write(output, body + '\n\n' + MARKER + metadata + ' -->\n')
    elif command == 'repair':
        dmg_path, checksum_path = rest
        lines = metadata_lines(info['body'])
        if len(lines) != 1 or not lines[0].endswith(' -->'):
            raise ValueError('No unique persisted asset hashes')
        metadata = json.loads(lines[0][len(MARKER):-len(' -->')])
        digests = metadata.get('sha256')
        if (metadata.get('tag') != tag or metadata.get('commit') != commit
                or not isinstance(digests, list) or len(digests) != 2
                or not all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) for value in digests)):
            raise ValueError('Persisted hashes do not match release provenance')
        dmg = Path(dmg_path)
        hash_value = hashlib.sha256()
        with dmg.open('rb') as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b''):
                hash_value.update(chunk)
        digest = hash_value.hexdigest()
        if digest not in digests:
            raise ValueError('Downloaded DMG does not match a hash persisted before upload')
        atomic_write(checksum_path, digest + '  ' + dmg.name + '\n')
    else:
        raise ValueError('Unknown operation')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, TypeError, KeyError) as error:
        sys.exit(str(error))
