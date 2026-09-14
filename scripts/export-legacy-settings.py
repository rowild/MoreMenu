#!/usr/bin/env python3
"""Export only MoreMenu's two preferences; leave the legacy container untouched."""
import json
import plistlib
import sys
from pathlib import Path


def read_settings(path):
    if not path.exists():
        return {}
    with path.open("rb") as source:
        values = plistlib.load(source)
    if not isinstance(values, dict):
        raise ValueError("Legacy preferences must be a property-list dictionary")
    result = {}
    if "finderMenuEnabled" in values:
        enabled = values["finderMenuEnabled"]
        if type(enabled) is not bool:
            raise ValueError("Legacy finderMenuEnabled is not a boolean")
        result["finderMenuEnabled"] = enabled
    if "enabledDocumentKeys" in values:
        keys = values["enabledDocumentKeys"]
        if not isinstance(keys, list) or any(not isinstance(key, str) for key in keys):
            raise ValueError("Legacy enabledDocumentKeys is not an array of strings")
        result["enabledDocumentKeys"] = keys
    return result


if __name__ == "__main__":
    try:
        print(json.dumps(read_settings(Path(sys.argv[1]))))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        sys.exit(f"Could not export legacy MoreMenu preferences: {error}")
