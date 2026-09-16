#!/usr/bin/env python3
"""Create a public Direct manifest and reject accidental release downgrades."""
import hashlib
import json
import plistlib
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE_URL = "https://www.macheadroom.com/direct/updates/"
BUNDLE_ID = "com.vinnycarpenter.SystemHeadroom.Direct"


def create_manifest(info, artifact):
    version = info.get("CFBundleShortVersionString", "")
    build = info.get("CFBundleVersion", "")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
        raise ValueError("invalid marketing version")
    if not isinstance(build, str) or not re.fullmatch(r"[0-9]+", build):
        raise ValueError("build number must be an integer")
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("expected the Direct bundle identifier")
    if info.get("SUFeedURL") != "https://www.macheadroom.com/direct/appcast.xml":
        raise ValueError("unexpected update feed URL")
    if info.get("SUEnableAutomaticChecks") is not True:
        raise ValueError("Direct release must enable automatic update checks")
    if info.get("DirectEditionClaimURL"):
        raise ValueError("free Direct download must not require a purchase claim")
    if artifact.name != f"System-Headroom-Direct-{version}-{build}.dmg":
        raise ValueError("artifact filename does not match bundle version and build")
    with artifact.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "version": version,
        "build": build,
        "bundleID": BUNDLE_ID,
        "key": f"updates/{artifact.name}",
        "downloadURL": BASE_URL + artifact.name,
        "sha256": digest.hexdigest(),
        "size": artifact.stat().st_size,
        "minimumSystemVersion": info["LSMinimumSystemVersion"],
        "releasedAt": datetime.now(timezone.utc).isoformat(),
    }


def compare_releases(previous, candidate):
    """Allow an exact retry; never replace a build with new bytes or downgrade."""
    old, new = previous.get("build", ""), candidate.get("build", "")
    if not all(isinstance(value, str) and re.fullmatch(r"[0-9]+", value) for value in (old, new)):
        raise ValueError("release manifests need integer build numbers")
    if int(new) < int(old):
        raise ValueError("build number must increase; Sparkle cannot roll users back")
    if int(new) == int(old) and any(previous.get(key) != candidate.get(key) for key in ("version", "key", "sha256")):
        raise ValueError("this build already exists with different content; increment the build number")


def main():
    if len(sys.argv) == 5 and sys.argv[1] == "create":
        with open(sys.argv[2], "rb") as stream:
            info = plistlib.load(stream)
        manifest = create_manifest(info, Path(sys.argv[3]))
        Path(sys.argv[4]).write_text(json.dumps(manifest, indent=2) + "\n")
    elif len(sys.argv) == 4 and sys.argv[1] == "compare":
        compare_releases(*(json.loads(Path(path).read_text()) for path in sys.argv[2:]))
    else:
        raise ValueError("usage: direct-release-metadata.py create Info.plist release.dmg latest.json | compare previous.json candidate.json")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        sys.exit(f"FAIL: {error}")
