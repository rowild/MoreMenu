import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LegacyExportTests(unittest.TestCase):
    def test_missing_file_is_empty(self):
        export = load_module("export-legacy-settings")
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(export.read_settings(Path(folder) / "missing.plist"), {})

    def test_exports_only_typed_settings(self):
        export = load_module("export-legacy-settings")
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "preferences.plist"
            path.write_bytes(plistlib.dumps({"finderMenuEnabled": False, "enabledDocumentKeys": [], "authorizedFolderRecords": "ignore"}))
            self.assertEqual(export.read_settings(path), {"finderMenuEnabled": False, "enabledDocumentKeys": []})
            path.write_bytes(plistlib.dumps({"finderMenuEnabled": "false", "enabledDocumentKeys": [12]}))
            with self.assertRaises(ValueError):
                export.read_settings(path)


class SigningTests(unittest.TestCase):
    group = "QN24ZH7M6W.GMX.MoreMenu"
    identifier = "GMX.MoreMenu.MoreMenuExtension"
    details = "Identifier=GMX.MoreMenu.MoreMenuExtension\nTeamIdentifier=QN24ZH7M6W\nAuthority=Apple Development: Example\nCodeDirectory v=20500 flags=0x10000(runtime)\n"

    def entitlements(self):
        return {"com.apple.security.app-sandbox": True,
                "com.apple.security.application-groups": [self.group],
                "com.apple.security.temporary-exception.files.absolute-path.read-write": ["/"]}

    def test_matching_certificate_and_entitlements_are_accepted(self):
        verify = load_module("verify-signing")
        verify.validate_signature(self.details, self.entitlements(), self.group, self.identifier, extension=True)

    def test_wrong_team_adhoc_or_missing_runtime_are_rejected(self):
        verify = load_module("verify-signing")
        for details in [self.details.replace("QN24ZH7M6W", "OTHERTEAM00"),
                        self.details + "Signature=adhoc\n",
                        self.details.replace("0x10000(runtime)", "0x0(none)")]:
            with self.subTest(details=details), self.assertRaises(ValueError):
                verify.validate_signature(details, self.entitlements(), self.group, self.identifier, extension=True)

    def test_legacy_group_missing_sandbox_and_broad_access_are_rejected(self):
        verify = load_module("verify-signing")
        for key, value in [("com.apple.security.application-groups", ["group.GMX.MoreMenu"]),
                           ("com.apple.security.app-sandbox", False),
                           ("com.apple.security.temporary-exception.apple-events", ["com.apple.finder"])]:
            entitlements = self.entitlements()
            entitlements[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify.validate_signature(self.details, entitlements, self.group, self.identifier, extension=True)


if __name__ == "__main__":
    unittest.main()
