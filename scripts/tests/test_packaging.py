import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


class PackagingTests(unittest.TestCase):
    def test_both_notarization_submissions_use_the_configured_keychain(self):
        for custom_keychain in [None, "signing credentials.keychain-db"]:
            with self.subTest(keychain=custom_keychain), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                scripts = root / "scripts"
                scripts.mkdir()
                shutil.copy2(SCRIPTS / "build-release-dmg.sh", scripts)

                def executable(path, source):
                    path.write_text(source)
                    path.chmod(0o755)

                executable(scripts / "build-app.sh", "#!/bin/zsh\nexit 0\n")
                derived = root / "derived"
                contents = derived / "Build/Products/Release/MoreMenu.app/Contents"
                contents.mkdir(parents=True)
                (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.2.2"}))
                commands = root / "bin"
                commands.mkdir()
                executable(commands / "xcrun", '#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["NOTARY_LOG"], "a") as log:\n    log.write(json.dumps(sys.argv[1:]) + "\\n")\n')
                executable(commands / "hdiutil", '#!/bin/zsh\ntouch "${@: -1}"\n')
                log = root / "notary.jsonl"
                env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                           DERIVED_DATA_PATH=str(derived), DIST_DIR=str(root / "dist"),
                           MOREMENU_DISTRIBUTION="1", MOREMENU_NOTARY_PROFILE="release-profile",
                           NOTARY_LOG=str(log))
                env.pop("MOREMENU_NOTARY_KEYCHAIN", None)
                if custom_keychain:
                    env["MOREMENU_NOTARY_KEYCHAIN"] = str(root / custom_keychain)
                result = subprocess.run(["zsh", str(scripts / "build-release-dmg.sh")], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                submissions = [call for call in calls if call[:2] == ["notarytool", "submit"]]
                self.assertEqual(len(submissions), 2)
                self.assertTrue(submissions[0][2].endswith(".zip"))
                self.assertTrue(submissions[1][2].endswith(".dmg"))
                for call in submissions:
                    self.assertEqual(call[call.index("--keychain-profile") + 1], "release-profile")
                    if custom_keychain:
                        self.assertIn("--keychain", call)
                        self.assertEqual(call[call.index("--keychain") + 1], str(root / custom_keychain))
                    else:
                        self.assertNotIn("--keychain", call)
