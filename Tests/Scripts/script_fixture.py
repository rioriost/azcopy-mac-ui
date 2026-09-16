import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]


class ScriptFixture(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / "coverage/script-regressions" / uuid.uuid4().hex
        self.root.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.root)
        shutil.copytree(ROOT / "Scripts", self.root / "Scripts", ignore=shutil.ignore_patterns("__pycache__"))
        self.bin = self.root / ".build/out/Products/Debug"
        self.bin.mkdir(parents=True)
        self.state = {
            "bin_path": str(self.bin),
            "targets": ["AzCopyMacUICoreTests", "AzCopyMacUIModelTests"],
        }
        self.write_state()
        self.write("VERSION", "0.2.1\n")
        self.write("Package.swift", "// offline fixture\n")
        self.write("Sources/AzCopyMacUICore/AppVersion.swift",
                   'public enum AppVersion { public static let current = "0.2.1" }\n')
        self.write("Sources/AzCopyMacUICore/File.swift", "let fixture = 1\n")
        self.write("AzCopyMacUI.xcodeproj/project.pbxproj",
                   "MARKETING_VERSION = 0.2.1;\nCURRENT_PROJECT_VERSION = 3;\n"
                   "MARKETING_VERSION = 0.2.1;\nCURRENT_PROJECT_VERSION = 3;\n"
                   "ENABLE_HARDENED_RUNTIME = YES;\n")
        self.write("AzCopyMacUI/AzCopyMacUI.entitlements", "<plist><dict/></plist>")
        info = self.root / "AzCopyMacUI/Info.plist"
        with info.open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "0.2.1", "CFBundleVersion": "3"}, stream)
        self.write("Tests/Scripts/test_fixture.py",
                   "import json, os, pathlib, unittest\n"
                   "class FixtureTest(unittest.TestCase):\n"
                   " def test_fixture(self):\n"
                   "  root = pathlib.Path(os.environ['SCRIPT_FIXTURE_ROOT'])\n"
                   "  with (root / 'commands.jsonl').open('a') as stream:\n"
                   "   stream.write(json.dumps(['script-tests']) + '\\n')\n"
                   "  self.assertFalse(json.loads((root / 'fixture.json').read_text()).get('script_test_failure'))\n")
        tools = self.root / "fixture-bin"
        tools.mkdir()
        for name in ("swift", "xcrun", "xcodebuild", "codesign", "ditto", "spctl"):
            path = tools / name
            shutil.copyfile(ROOT / "Tests/Scripts/toolchain_fixture.py", path)
            path.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "SCRIPT_FIXTURE_ROOT": str(self.root),
            "COVERAGE_THRESHOLD": "80",
            "DEVELOPER_ID_APPLICATION": "Developer ID Application: Fixture 'quoted' \"double\" & <sample> (A1B2C3D4E5)",
            "APPLE_TEAM_ID": "A1B2C3D4E5",
            "NOTARY_PROFILE": "offline fixture 'profile'",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        self.env.pop("SWIFTPM_BUILD_SYSTEM", None)
        self.artifacts()
        self.coverage()

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def write_state(self):
        (self.root / "fixture.json").write_text(json.dumps(self.state))

    def artifacts(self, names=None):
        for name in names or self.state["targets"]:
            self.write(str(self.bin.relative_to(self.root) / f"{name}.xctest/Contents/MacOS" / name), "fixture")
        self.profile = self.write(str(self.bin.relative_to(self.root) / "codecov/default.profdata"), "fixture")

    def coverage_file(self, name="File.swift", count=10000, covered=8000, **extra):
        return {
            "filename": str(self.root / "Sources/AzCopyMacUICore" / name),
            "summary": {
                "lines": {"count": count, "covered": covered, "percent": 100},
                "regions": {"count": 100, "covered": 100, "percent": 100},
            },
            **extra,
        }

    def coverage(self, count=10000, covered=8000, files=None):
        document = {
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [{
                "files": files if files is not None else [self.coverage_file(count=count, covered=covered)],
                "totals": {"lines": {"count": 100, "covered": 100, "percent": 100}},
            }],
        }
        self.write("coverage.json", json.dumps(document))

    def run_script(self, name, *args):
        runner = ["python3", "-B"] if name.endswith(".py") else ["bash"]
        return subprocess.run(runner + [str(self.root / "Scripts" / name), *args],
                              cwd=self.root, env=self.env, text=True, capture_output=True)

    def commands(self):
        path = self.root / "commands.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_failed(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message.lower(), (result.stdout + result.stderr).lower())
