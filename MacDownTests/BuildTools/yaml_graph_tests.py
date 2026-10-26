"""Compile the deployed YAML stack in a private directory; no Xcode or preferences."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f'Exit {result.returncode}: {result.stdout}\n{result.stderr}')
    return result

with tempfile.TemporaryDirectory(prefix='macdown-yaml-graph-') as directory:
    work = Path(directory)
    ordered = work / 'ordered.o'
    run('clang', '-fobjc-arc', '-c', str(ROOT / 'Pods/M13OrderedDictionary/M13OrderedDictionary.m'),
        '-o', str(ordered))
    yaml = ROOT / 'Pods/LibYAML'
    binary = work / 'contracts'
    run('clang', '-I' + str(yaml / 'include'), '-I' + str(yaml / 'src'),
        '-I' + str(ROOT / 'Pods'), '-I' + str(ROOT / 'Dependency/YAML-framework'),
        '-include', str(yaml / 'config.h'), '-Wno-deprecated-declarations',
        str(ROOT / 'MacDownTests/BuildTools/yaml_graph_tests.m'),
        str(ROOT / 'Dependency/YAML-framework/YAMLSerialization.m'), str(ordered),
        *(str(path) for path in sorted((yaml / 'src').glob('*.c'))),
        '-framework', 'Foundation', '-o', str(binary))
    print(run(str(binary)).stdout.strip())
