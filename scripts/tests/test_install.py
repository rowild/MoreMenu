import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def run_install(self, fail_import=False, fail_verification=False, fail_enable=False, previous_app=True):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scripts = root / "scripts"
            scripts.mkdir()
            for name in ["install-local.sh", "export-legacy-settings.py"]:
                shutil.copy2(SCRIPTS / name, scripts / name)
            def executable(path, text):
                path.write_text(text)
                path.chmod(0o755)
            executable(scripts / "build-app.sh", "#!/bin/zsh\nexit 0\n")
            executable(scripts / "verify-signing.py", "import sys\nsys.exit(" + str(int(fail_verification)) + ")\n")
            derived = root / "derived"
            built = derived / "Build/Products/Release/MoreMenu.app"
            binary = built / "Contents/MacOS/MoreMenu"
            binary.parent.mkdir(parents=True)
            executable(binary, '#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\nPath(os.environ["IMPORT_LOG"]).write_text(sys.argv[2])\nsys.exit(' + str(int(fail_import)) + ')\n')
            destination = root / "Applications"
            old = destination / "MoreMenu.app"
            destination.mkdir()
            if previous_app:
                old.mkdir()
                (old / "old-marker").write_text("previous app")
            legacy = root / "legacy.plist"
            legacy.write_bytes(plistlib.dumps({"finderMenuEnabled": False, "enabledDocumentKeys": ["vue"]}))
            commands = root / "bin"
            commands.mkdir()
            executable(commands / "ditto", '#!/usr/bin/env python3\nimport shutil,sys\nshutil.copytree(sys.argv[1],sys.argv[2])\n')
            for name in ["killall", "pluginkit", "find"]:
                source = '#!/bin/zsh\nprintf "%s %s\\n" "${0:t}" "$*" >> "$COMMAND_LOG"\n'
                if name == "pluginkit" and fail_enable:
                    source += 'if [[ "$1" == "-e" ]]; then exit 1; fi\n'
                executable(commands / name, source)
            # Any accidental reintroduction of a consent reset fails the test.
            executable(commands / "tccutil", '#!/bin/zsh\necho tccutil >> "$COMMAND_LOG"\nexit 99\n')
            env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                       DERIVED_DATA_PATH=str(derived), MOREMENU_INSTALL_DIR=str(destination),
                       MOREMENU_LEGACY_PREFERENCES=str(legacy), IMPORT_LOG=str(root / "import.json"),
                       COMMAND_LOG=str(root / "commands.log"))
            result = subprocess.run(["zsh", str(scripts / "install-local.sh")], env=env, capture_output=True, text=True)
            failed = fail_import or fail_verification or fail_enable
            self.assertEqual(result.returncode == 0, not failed, result.stderr)
            self.assertEqual((old / "old-marker").exists(), previous_app and failed)
            if not previous_app and failed:
                self.assertFalse(old.exists())
            self.assertTrue(legacy.exists())
            self.assertFalse(list(destination.glob(".moremenu-install.*")))
            if not fail_verification:
                self.assertEqual(json.loads((root / "import.json").read_text()), {"finderMenuEnabled": False, "enabledDocumentKeys": ["vue"]})
                log = (root / "commands.log").read_text()
                self.assertNotIn("tccutil", log)
                if failed:
                    self.assertNotIn("killall Finder", log)
                else:
                    self.assertIn("pluginkit -e use", log)

    def test_success_imports_preferences_without_resetting_consent(self):
        self.run_install()

    def test_import_failure_restores_previous_app(self):
        self.run_install(fail_import=True)

    def test_verification_failure_keeps_previous_app(self):
        self.run_install(fail_verification=True)

    def test_enable_failure_restores_previous_app_without_restarting_finder(self):
        self.run_install(fail_enable=True)

    def test_fresh_install_failure_removes_the_incomplete_app(self):
        self.run_install(fail_enable=True, previous_app=False)
