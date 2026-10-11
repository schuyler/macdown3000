"""Pinned theme assets, offline CSS, real PEG parser and optional bundle integrity."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "MacDown/Resources"
MANIFEST = json.loads((ROOT / "docs/themes/community-manifest.json").read_text())


def verify_assets(resources, bundled=False):
    for relative, digest in MANIFEST["assets"].items():
        destination = relative.replace("CommunityPrismThemes/", "Prism/themes/") if bundled else relative
        file = resources / destination
        assert file.is_file(), f"Missing theme asset: {file}"
        assert hashlib.sha256(file.read_bytes()).hexdigest() == digest, f"Changed asset: {file}"
        if file.suffix == ".css":
            css = re.sub(r"/\*.*?\*/", "", file.read_text(), flags=re.S)
            assert not re.search(r"@import|expression\s*\(|javascript:|behavior\s*:", css, re.I), file
            for url in re.findall(r"url\(\s*['\"]?([^)'\"]+)", css, re.I):
                # Pojoaque's original background is an embedded JPEG, never a network request.
                prefix = "data:image/jpeg;base64,"
                assert url.startswith(prefix), f"External CSS resource in {file}"
                image = base64.b64decode(url[len(prefix):], validate=True)
                assert image.startswith(b"\xff\xd8\xff") and len(image) < 16384, file
    for directory in ("Themes", "Styles", "Prism/themes" if bundled else "CommunityPrismThemes"):
        assert (resources / directory / "COMMUNITY-THEMES-LICENSE.txt").is_file(), directory


def verify_build_phases(directory):
    project = subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-",
        str(ROOT / "MacDown 3000.xcodeproj/project.pbxproj"),
    ], timeout=10)
    objects = json.loads(project)["objects"]
    fixture = directory / "source"
    resources = fixture / "MacDown/Resources"
    resources.mkdir(parents=True)
    (fixture / "Dependency").symlink_to(ROOT / "Dependency", target_is_directory=True)
    for folder in ("Styles", "CommunityPrismThemes"):
        (resources / folder).symlink_to(RESOURCES / folder, target_is_directory=True)
    environment = dict(os.environ, SRCROOT=str(fixture),
                       TARGET_BUILD_DIR=str(directory / "product"),
                       UNLOCALIZED_RESOURCES_FOLDER_PATH="Resources")
    for name in ("Fetch Prism Resources", "Copy Styles and Prism Resources"):
        phases = [item for item in objects.values() if item.get("name") == name]
        assert len(phases) == 1, name
        subprocess.run(["/bin/sh", "-c", phases[0]["shellScript"]],
                       env=environment, check=True, timeout=30)
        target = resources / "Prism/themes" if name == "Fetch Prism Resources" else directory / "product/Resources/Prism/themes"
        for relative, digest in MANIFEST["assets"].items():
            if relative.startswith("CommunityPrismThemes/"):
                assert hashlib.sha256((target / Path(relative).name).read_bytes()).hexdigest() == digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-resources", type=Path)
    args = parser.parse_args()
    assert len(MANIFEST["palettes"]) == 37
    assert len(MANIFEST["assets"]) == 148
    verify_assets(RESOURCES)
    if args.bundle_resources:
        verify_assets(args.bundle_resources, bundled=True)
    with tempfile.TemporaryDirectory(prefix="macdown-community-themes-") as directory:
        verify_build_phases(Path(directory))
        binary = Path(directory) / "parser-contracts"
        peg = Path(directory) / "peg"
        source = ROOT / "Dependency/peg-markdown-highlight"
        shutil.copytree(source, peg, ignore=shutil.ignore_patterns(
            "*.o", "*.dSYM", "greg", "pmh_parser.c", "pmh_parser_core.c"))
        shutil.copytree(source / "greg", peg / "greg",
                        ignore=shutil.ignore_patterns("*.o", "greg"))
        subprocess.run(["make", "CC=clang"], cwd=peg, check=True, timeout=30)
        subprocess.run([
            "clang", "-I", str(peg),
            str(Path(__file__).with_name("community_theme_parser_tests.c")),
            str(peg / "pmh_styleparser.c"), str(peg / "pmh_parser.c"),
            "-o", str(binary),
        ], check=True, timeout=30)
        styles = [str(RESOURCES / path) for path in MANIFEST["assets"] if path.endswith(".style")]
        subprocess.run([str(binary), *styles], check=True, timeout=30)
    print("PASS 37 palettes / 148 pinned assets / 74 real PEG style parses / both resource build paths / offline CSS")


if __name__ == "__main__":
    main()
