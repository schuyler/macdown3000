"""Real shared Hoedown/Quick Look WebKit code-theme consumers, each bounded."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='macdown-code-theme-') as folder:
    folder = Path(folder)
    (folder / 'hoedown').symlink_to(ROOT / 'Pods/hoedown/src', target_is_directory=True)
    binary = folder / 'contracts'
    sources = [ROOT / 'MacDownTests/BuildTools/quicklook_code_theme_tests.m', ROOT / 'MacDown/Code/Extension/hoedown_html_patch.c', ROOT / 'MacDownCore/MPQuickLookRenderer.m', ROOT / 'MacDownCore/MPQuickLookPreferences.m']
    sources += [ROOT / 'Pods/hoedown/src' / name for name in ('autolink.c', 'buffer.c', 'document.c', 'escape.c', 'html.c', 'html_blocks.c', 'html_smartypants.c', 'stack.c')]
    subprocess.run(['clang', '-fobjc-arc', '-Wno-deprecated-declarations', '-I', str(folder), '-framework', 'Cocoa', '-framework', 'WebKit', *map(str, sources), '-o', str(binary)], check=True, timeout=20)
    for style, background, color in (('GitHub2.css', 'rgb(248, 248, 248)', 'rgb(0, 0, 0)'), ('GitHub-2020.css', 'rgb(246, 248, 250)', 'rgb(31, 35, 40)')):
        for themed, numbered in ((1, 0), (1, 1), (0, 0), (0, 1)):
            subprocess.run([str(binary), str(ROOT / 'MacDown/Resources/Styles' / style), str(ROOT / 'Dependency/prism/themes/prism-tomorrow.css'), str(themed), str(numbered), background, color], check=True, timeout=20)
