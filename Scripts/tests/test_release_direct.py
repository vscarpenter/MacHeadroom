"""Exercise release safety gates without a certificate or contacting Apple.

Run: python3 -m unittest discover -s Scripts/tests -p 'test_release_direct.py'
The fake tools model external command results; plist and receipt validation,
orchestration, artifact naming, and hashing run through the real script.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "release-direct.sh"
FAKE_TOOL = r'''#!/usr/bin/env python3
import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps([tool] + args) + "\n")
key = base64.b64encode(b"a" * 32).decode()
identity = "Developer ID Application: Example Developer (TEAM123456)"
if tool == "xcodebuild":
    if "-version" in args:
        print("Xcode test fixture")
    elif "-showBuildSettings" in args:
        print("    MARKETING_VERSION = 1.1\n    CURRENT_PROJECT_VERSION = 15")
        print("    DIRECT_SPARKLE_PUBLIC_ED_KEY = " + key)
    elif "archive" in args:
        archive = Path(args[args.index("-archivePath") + 1])
        contents = archive / "Products/Applications/System Headroom Direct.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS/System Headroom Direct").write_text("binary fixture")
        (contents / "Frameworks/Sparkle.framework").mkdir(parents=True)
        (contents / "Frameworks/Sparkle.framework/Sparkle").write_text("framework fixture")
        info = dict(CFBundleShortVersionString="1.1", CFBundleVersion="15",
                    CFBundleIdentifier="com.vinnycarpenter.SystemHeadroom.Direct",
                    CFBundleExecutable="System Headroom Direct", LSMinimumSystemVersion="14.0",
                    SUFeedURL="https://www.macheadroom.com/direct/appcast.xml", SUPublicEDKey=key)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
elif tool == "security":
    if os.environ.get("MISSING_IDENTITY") != "1":
        print('  1) FAKEHASH "' + identity + '"')
elif tool == "codesign":
    if "--entitlements" in args:
        assert "--xml" in args, "Request plist XML instead of codesign's human-readable default"
        entitlements = {}
        if os.environ.get("SANDBOXED") == "1":
            entitlements["com.apple.security.app-sandbox"] = True
        if os.environ.get("DEBUG_ENTITLEMENT") == "1":
            entitlements["com.apple.security.get-task-allow"] = True
        sys.stdout.buffer.write(plistlib.dumps(entitlements))
    elif "-d" in args:
        print("Authority=" + identity)
        print("TeamIdentifier=TEAM123456\nCodeDirectory flags=0x10000(runtime)\nTimestamp=test")
elif tool == "xcrun":
    if args[0] == "--find":
        print("/fake/" + args[1])
    elif args[:2] == ["notarytool", "submit"]:
        status = os.environ.get("APP_NOTARY_STATUS" if args[2].endswith(".zip") else "DMG_NOTARY_STATUS", "Accepted")
        print(json.dumps({"id": "test-submission", "status": status}))
elif tool == "ditto":
    if "-c" in args:
        Path(args[-1]).write_bytes(b"zip fixture")
    else:
        shutil.copytree(args[0], args[1])
elif tool == "hdiutil":
    staging = Path(args[args.index("-srcfolder") + 1])
    assert (staging / "Applications").is_symlink()
    assert os.readlink(staging / "Applications") == "/Applications"
    assert (staging / "System Headroom Direct.app").is_dir()
    Path(args[-1]).write_bytes(b"dmg fixture with Applications shortcut")
elif tool == "lipo":
    assert len(args) == 3 and Path(args[0]).is_file()
    assert args[1] == "-verify_arch" and args[2] in ["arm64", "x86_64"]
elif tool == "spctl":
    pass
else:
    raise SystemExit("Unexpected fake tool " + tool)
'''


@unittest.skipUnless(shutil.which("zsh") and shutil.which("plutil"), "requires macOS tools")
class DirectReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Scripts").mkdir()
        (self.root / "Vendor/Sparkle/Sparkle.framework").mkdir(parents=True)
        shutil.copy2(SCRIPT, self.root / "Scripts/release-direct.sh")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        shim = self.bin / "fake-tool"
        shim.write_text(FAKE_TOOL)
        shim.chmod(0o755)
        for tool in ("xcodebuild", "security", "codesign", "xcrun", "ditto", "hdiutil", "lipo", "spctl"):
            (self.bin / tool).symlink_to(shim)
        self.log = self.root / "commands.jsonl"
        self.output = self.root / "release"
        self.environment = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                                DIRECT_DEVELOPER_ID_APPLICATION="Developer ID Application: Example Developer (TEAM123456)",
                                DIRECT_DEVELOPER_TEAM_ID="TEAM123456",
                                DIRECT_NOTARY_PROFILE="test-profile", COMMAND_LOG=str(self.log))

    def run_script(self, *arguments, **environment):
        return subprocess.run(["zsh", str(self.root / "Scripts/release-direct.sh"),
                               "--output-dir", str(self.output), *arguments],
                              env=dict(self.environment, **environment), text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_preflight_never_archives_or_contacts_apple(self):
        result = self.run_script("--preflight")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.output.exists())
        self.assertFalse(any("archive" in command or "submit" in command for command in self.commands()))

    def test_missing_identity_stops_before_archiving(self):
        result = self.run_script(MISSING_IDENTITY="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not available in the current Keychain", result.stderr)
        self.assertFalse(self.output.exists())

    def test_sandbox_entitlement_stops_before_notarization(self):
        result = self.run_script(SANDBOXED="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sandbox entitlement", result.stderr)
        self.assertFalse(any("submit" in command for command in self.commands()))

    def test_debugger_entitlement_stops_before_notarization(self):
        result = self.run_script(DEBUG_ENTITLEMENT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("debugger entitlement", result.stderr)
        self.assertFalse(any("submit" in command for command in self.commands()))

    def test_rejected_app_stops_even_when_notarytool_exits_zero(self):
        result = self.run_script(APP_NOTARY_STATUS="Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("notarization status is 'Invalid'", result.stderr)
        self.assertTrue((self.output / "notarization-app.json").exists())
        self.assertFalse(any("staple" in command or "hdiutil" in command for command in self.commands()))
        self.assertFalse((self.output / "release.json").exists())

    def test_rejected_dmg_never_reports_release_ready(self):
        result = self.run_script(DMG_NOTARY_STATUS="Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("notarization status is 'Invalid'", result.stderr)
        self.assertFalse((self.output / "release.json").exists())
        self.assertFalse(any("staple" in command and command[-1].endswith(".dmg") for command in self.commands()))

    def test_accepted_release_records_the_final_dmg(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        metadata = json.loads((self.output / "release.json").read_text())
        self.assertEqual(metadata["dmg"], "System-Headroom-Direct-1.1-15.dmg")
        dmg = self.output / metadata["dmg"]
        self.assertEqual(metadata["sha256"], hashlib.sha256(dmg.read_bytes()).hexdigest())
        self.assertEqual(metadata["size"], dmg.stat().st_size)
        self.assertEqual(metadata["architectures"], ["arm64", "x86_64"])
        archive = next(command for command in self.commands() if command[:2] == ["xcodebuild", "archive"])
        self.assertIn("ARCHS=arm64 x86_64", archive)
        self.assertIn("ONLY_ACTIVE_ARCH=NO", archive)
        self.assertFalse(list(self.output.glob(".dmg-staging-*")))
        assessments = [command for command in self.commands() if command[0] == "spctl"]
        self.assertTrue(any("context:primary-signature" in command for command in assessments))


if __name__ == "__main__":
    unittest.main()
