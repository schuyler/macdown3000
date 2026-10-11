"""Run native print regression with an external timeout and isolated PDFs."""
from pathlib import Path
import os
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def run(args):
    process = subprocess.Popen(args, cwd=ROOT, start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = process.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        raise RuntimeError(f'Print timeout: {stdout}\n{stderr}')
    print(stdout, end='')
    if process.returncode:
        raise RuntimeError(f'Exit {process.returncode}: {stderr}')

with tempfile.TemporaryDirectory(prefix='macdown-print-colors-') as directory:
    binary = Path(directory) / 'contracts'
    run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-framework', 'Cocoa',
         '-framework', 'WebKit', '-framework', 'PDFKit',
         str(ROOT / 'MacDownTests/BuildTools/print_colors_tests.m'), '-o', str(binary)])
    for level in range(1, 7):
        run([str(binary), str(ROOT / 'MacDown/Resources/Styles/Clearness Dark.css'),
             str(ROOT / 'MacDown/Resources/Extensions/print.css'),
             str(Path(directory) / f'heading-{level}.pdf'), str(level)])
