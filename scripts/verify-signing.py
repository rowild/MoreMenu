#!/usr/bin/env python3
"""Reject installable bundles whose signer cannot authorize MoreMenu's App Group."""
import plistlib
import subprocess
import sys
from pathlib import Path


GROUP = "QN24ZH7M6W.GMX.MoreMenu"


def validate_signature(details, entitlements, group, identifier, *, extension):
    fields = dict(line.split("=", 1) for line in details.splitlines() if "=" in line)
    if fields.get("Identifier") != identifier:
        raise ValueError(f"Expected bundle identifier {identifier}")
    if fields.get("TeamIdentifier") != group.split(".", 1)[0] or "Signature=adhoc" in details:
        raise ValueError(f"A certificate-backed signature from team {group.split('.', 1)[0]} is required")
    if "Authority=" not in details or "(runtime)" not in details:
        raise ValueError("A certificate authority and hardened runtime are required")
    expected = {"com.apple.security.app-sandbox": True,
                "com.apple.security.application-groups": [group]}
    if extension:
        expected["com.apple.security.temporary-exception.files.absolute-path.read-write"] = ["/"]
    if entitlements != expected:
        raise ValueError(f"Unexpected entitlements: expected {expected}, received {entitlements}")


def verify_bundle(app):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    for bundle, identifier, extension in [
        (app, "GMX.MoreMenu", False),
        (app / "Contents/PlugIns/MoreMenuExtension.appex", "GMX.MoreMenu.MoreMenuExtension", True),
    ]:
        result = subprocess.run(["codesign", "-dvv", str(bundle)], capture_output=True, text=True, check=True)
        entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)],
                                      capture_output=True, check=True)
        validate_signature(result.stderr, plistlib.loads(entitlements.stdout), GROUP, identifier, extension=extension)
    print(f"Verified signer, hardened runtime, and App Group: {app}")


if __name__ == "__main__":
    try:
        verify_bundle(Path(sys.argv[1]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"MoreMenu signature validation failed: {error}")
