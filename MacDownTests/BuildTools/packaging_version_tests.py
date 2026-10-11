"""Execute the real target phases; consume an ad-hoc signed embedded extension."""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def run(*args, cwd=ROOT, env=None):
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True,
                          text=True, check=True, timeout=30)

project = json.loads(run('plutil', '-convert', 'json', '-o', '-',
                         str(ROOT / 'MacDown 3000.xcodeproj/project.pbxproj')).stdout)
objects = project['objects']
phases = {}
for name in ['MacDown', 'MacDownQuickLook']:
    target = next(o for o in objects.values() if o.get('isa') == 'PBXNativeTarget' and o.get('name') == name)
    matching = [objects[p] for p in target['buildPhases']
                if 'Tools/update_build_number.sh' in objects[p].get('shellScript', '')]
    assert len(matching) == 1, f'{name} must update its own processed plist exactly once'
    assert '$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)' in matching[0]['inputPaths']
    phases[name] = matching[0]['shellScript']

with tempfile.TemporaryDirectory(prefix='macdown packaging versions ') as directory:
    repo = Path(directory)
    (repo / 'Tools').mkdir()
    for name in ['utils.sh', 'update_build_number.sh']:
        shutil.copy2(ROOT / 'Tools' / name, repo / 'Tools' / name)
    run('git', 'init', '-q', cwd=repo)
    run('git', 'config', 'user.name', 'Packaging Test', cwd=repo)
    run('git', 'config', 'user.email', 'packaging@example.invalid', cwd=repo)
    run('git', 'commit', '--allow-empty', '-qm', 'Initial', cwd=repo)
    run('git', 'tag', 'v2.3.4', cwd=repo)
    run('git', 'commit', '--allow-empty', '-qm', 'Next', cwd=repo)
    products = repo / 'Products'
    products.mkdir()
    app = products / 'Containing App.app'
    extension = products / 'Quick Look.appex'

    def processed_product(product, executable, identifier):
        macos = product / 'Contents/MacOS'
        macos.mkdir(parents=True)
        plist = product / 'Contents/Info.plist'
        plist.write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier,
            'CFBundleExecutable': executable, 'CFBundlePackageType': 'APPL' if product == app else 'XPC!',
            'CFBundleVersion': '0', 'CFBundleShortVersionString': '0.0.0-dev'}))
        source = repo / 'fixture.c'
        source.write_text('int main(void) { return 0; }\n')
        run('clang', str(source), '-o', str(macos / executable), cwd=repo)
        return plist

    app_plist = processed_product(app, 'app', 'org.macdown.audit.packaging.app')
    ext_plist = processed_product(extension, 'extension', 'org.macdown.audit.packaging.app.QuickLook')

    def update(name, product, ci='false'):
        env = dict(os.environ, CI=ci, TARGET_BUILD_DIR=str(products),
                   INFOPLIST_PATH=str(product.relative_to(products) / 'Contents/Info.plist'))
        run('bash', '-c', phases[name], cwd=repo, env=env)

    update('MacDownQuickLook', extension)
    assert plistlib.loads(app_plist.read_bytes())['CFBundleVersion'] == '0', 'Extension phase may only touch its own product'
    run('codesign', '--force', '--sign', '-', str(extension), cwd=repo)
    embedded = app / 'Contents/PlugIns/Quick Look.appex'
    embedded.parent.mkdir(parents=True)
    shutil.copytree(extension, embedded)
    signed_plist = (embedded / 'Contents/Info.plist').read_bytes()
    update('MacDown', app)
    app_info = plistlib.loads(app_plist.read_bytes())
    ext_info = plistlib.loads(signed_plist)
    for key, expected in {'CFBundleVersion': '2', 'CFBundleShortVersionString': '2.3.4.post1'}.items():
        assert app_info[key] == ext_info[key] == expected, (key, app_info, ext_info)
    assert (embedded / 'Contents/Info.plist').read_bytes() == signed_plist, 'Parent phase may not modify an embedded signed product'
    run('codesign', '--verify', '--strict', str(embedded), cwd=repo)

    # In CI, Xcode expands explicit settings provided to all targets by the
    # build action. Both phases must preserve those processed metadata values.
    for name, product in [('MacDown', app), ('MacDownQuickLook', extension)]:
        plist = product / 'Contents/Info.plist'
        info = plistlib.loads(plist.read_bytes())
        info.update(CFBundleVersion='987', CFBundleShortVersionString='9.8.7')
        plist.write_bytes(plistlib.dumps(info))
        before = plist.read_bytes()
        update(name, product, ci='true')
        assert plist.read_bytes() == before, 'CI-provided versions must be preserved'
    print('PASS target-local versions match, embedded signature preserved, CI metadata untouched')
