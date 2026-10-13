"""Consume every bundled heading style in legacy WebKit, without user preferences."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="macdown-heading-spacing-") as directory:
    binary = Path(directory) / "contracts"
    subprocess.run([
        "clang", "-fobjc-arc", "-Wno-deprecated-declarations",
        "-framework", "Cocoa", "-framework", "WebKit",
        "-framework", "JavaScriptCore",
        str(Path(__file__).with_suffix(".m")), "-o", str(binary),
    ], check=True, timeout=30)
    subprocess.run([str(binary), str(ROOT / "MacDown/Resources/Styles")],
                   check=True, timeout=70)
