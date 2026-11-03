"""Check that explicit regeneration cannot corrupt the committed stylesheet."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CSSGenerationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="macdown-css-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.generator = self.root / "Tools/GitHub-style-generator"
        self.generator.mkdir(parents=True)
        shutil.copy2(ROOT / "Tools/GitHub-style-generator/Makefile",
                     self.generator / "Makefile")
        for name in ["index.sass", "tokens.js", "package-lock.json"]:
            (self.generator / name).touch()
        self.output = self.root / "MacDown/Resources/Styles/GitHub-2020.css"
        self.output.parent.mkdir(parents=True)
        self.output.write_text("reviewed stylesheet\n")
        os.utime(self.output, (1, 1))

    def make(self, *arguments, env=None):
        return subprocess.run([shutil.which("make"), *arguments],
                              cwd=self.generator, env=env,
                              capture_output=True, text=True, timeout=30)

    def install_stubs(self, sass_status=0, token_status=0):
        sass = self.generator / "node_modules/.bin/sass"
        sass.parent.mkdir(parents=True)
        sass.write_text("#!/bin/sh\nprintf '.markdown-body { color: red; }\\n'\n"
                        f"exit {sass_status}\n")
        sass.chmod(0o755)
        for name in ["base/size/size.css", "functional/themes/light.css"]:
            token = self.generator / "node_modules/@primer/primitives/dist/css" / name
            token.parent.mkdir(parents=True, exist_ok=True)
            token.touch()
        (self.generator / "tokens.js").write_text(
            "const fs = require('fs');\n"
            "process.stdout.write(fs.readFileSync(0));\n"
            f"process.exit({token_status});\n")
        node = shutil.which("node")
        self.assertIsNotNone(node, "Generator tests require Node.js")
        return dict(os.environ, PATH=str(Path(node).parent) + os.pathsep + "/usr/bin:/bin")

    def test_build_uses_committed_css_without_node_even_when_inputs_are_newer(self):
        empty = self.root / "empty-path"
        empty.mkdir()
        result = self.make(env=dict(os.environ, PATH=str(empty)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "reviewed stylesheet\n")
        self.assertEqual(self.output.stat().st_mtime, 1)

    def test_build_reports_missing_committed_css_without_trying_to_generate_it(self):
        self.output.unlink()
        result = self.make()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("make regenerate explicitly", result.stderr)
        self.assertFalse(self.output.exists())

    def test_success_replaces_css_with_a_readable_file_and_cleans_temporary_files(self):
        result = self.make("regenerate", env=self.install_stubs())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "body { color: red; }\n")
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o644)
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_failed_sass_preserves_reviewed_css_and_cleans_temporary_files(self):
        result = self.make("regenerate", env=self.install_stubs(sass_status=42))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), "reviewed stylesheet\n")
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_failed_token_resolution_preserves_reviewed_css_and_cleans_temporary_files(self):
        result = self.make("regenerate", env=self.install_stubs(token_status=43))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), "reviewed stylesheet\n")
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_clean_keeps_the_committed_stylesheet(self):
        result = self.make("clean")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "reviewed stylesheet\n")


if __name__ == "__main__":
    unittest.main()
