"""Run production text-editing code against real AppKit, without user preferences."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='macdown-indent-') as directory:
    binary = Path(directory) / 'contracts'
    objects = []
    yaml_obj = Path(directory) / 'YAMLSerialization.o'
    subprocess.run(['clang', '-fno-objc-arc', '-I', str(ROOT / 'Pods/Headers/Public'),
                    '-I', str(ROOT / 'Pods/Headers/Public/LibYAML'), '-c',
                    str(ROOT / 'Dependency/YAML-framework/YAMLSerialization.m'),
                    '-o', str(yaml_obj)], check=True, timeout=20)
    objects.append(str(yaml_obj))
    for source in sorted((ROOT / 'Pods/LibYAML/src').glob('*.c')):
        obj = Path(directory) / (source.stem + '.o')
        subprocess.run(['clang', '-DHAVE_CONFIG_H', '-I', str(ROOT / 'Pods/LibYAML'),
                        '-I', str(ROOT / 'Pods/LibYAML/include'), '-c', str(source),
                        '-o', str(obj)], check=True, timeout=20)
        objects.append(str(obj))
    subprocess.run([
        'clang', '-fobjc-arc', '-Wno-deprecated-declarations',
        '-include', 'Cocoa/Cocoa.h',
        '-I', str(ROOT / 'MacDown/Code/Extension'),
        '-I', str(ROOT / 'MacDown/Code/Utility'),
        '-I', str(ROOT / 'Dependency/YAML-framework'),
        '-I', str(ROOT / 'Pods/Headers/Public/LibYAML'),
        '-I', str(ROOT / 'Pods/Headers/Public'),
        '-framework', 'Cocoa', '-framework', 'JavaScriptCore',
        str(ROOT / 'MacDownTests/BuildTools/indent_selection_tests.m'),
        str(ROOT / 'MacDown/Code/Extension/NSTextView+Autocomplete.m'),
        str(ROOT / 'MacDown/Code/Extension/NSString+Lookup.m'),
        str(ROOT / 'MacDown/Code/Utility/MPUtilities.m'),
        str(ROOT / 'Pods/M13OrderedDictionary/M13OrderedDictionary.m'),
        *objects,
        '-o', str(binary),
    ], check=True, timeout=30)
    subprocess.run([str(binary)], check=True, timeout=15)
