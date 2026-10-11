"""Exercise Quarto callouts through the real shared Quick Look renderer."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='macdown-callouts-') as directory:
    tmp = Path(directory)
    flags = ['-I', str(ROOT / 'Pods/Headers/Public'), '-I', str(ROOT / 'Pods/hoedown/src')]
    objects = []
    for source in sorted((ROOT / 'Pods/hoedown/src').glob('*.c')) + [ROOT / 'MacDown/Code/Extension/hoedown_html_patch.c']:
        obj = tmp / (source.stem + '.o')
        subprocess.run(['clang', *flags, '-c', str(source), '-o', str(obj)], check=True, timeout=30)
        objects.append(str(obj))
    binary = tmp / 'contracts'
    subprocess.run(['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation', *flags,
                    str(Path(__file__).with_suffix('.m')),
                    str(ROOT / 'MacDownCore/MPQuickLookRenderer.m'),
                    str(ROOT / 'MacDownCore/MPQuickLookPreferences.m'), *objects,
                    '-o', str(binary)], check=True, timeout=30)
    env = dict(os.environ, CFFIXED_USER_HOME=str(tmp))
    subprocess.run([str(binary)], check=True, timeout=30, env=env)
