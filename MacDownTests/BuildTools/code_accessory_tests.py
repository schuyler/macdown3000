"""Compile and run isolated real Hoedown/WebKit accessory contracts, bounded to 20s."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='macdown-code-accessory-') as directory:
    directory = Path(directory)
    (directory / 'hoedown').symlink_to(ROOT / 'Pods/hoedown/src', target_is_directory=True)
    binary = directory / 'contracts'
    sources = [ROOT / 'MacDownTests/BuildTools/code_accessory_tests.m', ROOT / 'MacDown/Code/Extension/hoedown_html_patch.c']
    sources += [ROOT / 'Pods/hoedown/src' / name for name in ('autolink.c','buffer.c','document.c','escape.c','html.c','html_blocks.c','html_smartypants.c','stack.c')]
    subprocess.run(['clang','-fobjc-arc','-Wno-deprecated-declarations','-I',str(directory),'-framework','Cocoa','-framework','WebKit',*map(str,sources),'-o',str(binary)], check=True, timeout=20)
    subprocess.run([str(binary),str(ROOT / 'MacDown/Resources/Extensions/show-information.css')],check=True,timeout=20)
