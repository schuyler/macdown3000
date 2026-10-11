"""Verify inline Markdown transactions against the real Hoedown renderer."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="macdown-inline-contracts-") as directory:
    directory = Path(directory)
    (directory / "hoedown").symlink_to(ROOT / "Pods/hoedown/src", target_is_directory=True)
    binary = directory / "contracts"
    sources = [ROOT / "MacDownTests/BuildTools/inline_transactions_tests.m"]
    sources += [ROOT / "Pods/hoedown/src" / name for name in ("autolink.c", "buffer.c", "document.c", "escape.c", "html.c", "html_blocks.c", "html_smartypants.c", "stack.c")]
    subprocess.run(["clang", "-fobjc-arc", "-Wno-deprecated-declarations", "-I", str(directory), "-framework", "Foundation", *map(str, sources), "-o", str(binary)], check=True, timeout=20)
    subprocess.run([str(binary)], check=True, timeout=20)
