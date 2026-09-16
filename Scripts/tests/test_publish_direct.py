"""Exercise publication staging and receipts without Keychain or network access.

Run: python3 -m unittest discover -s Scripts/tests -p 'test_publish_direct.py'
The real script and manifest generator run against fake signing, disk-image,
Sparkle, AWS, and HTTP commands. Only local temporary files are used.
"""

from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
FAKE_TOOL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys
from urllib.parse import urlsplit

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps([tool] + args) + "\n")
cloud = Path(os.environ["FAKE_CLOUD"])
if tool == "codesign":
    if "--entitlements" in args:
        assert "--xml" in args
        sys.stdout.buffer.write(plistlib.dumps({}))
    elif "-dv" in args:
        print("Authority=Developer ID Application: Example Developer (TEAM123456)")
        print("CodeDirectory flags=0x10000(runtime)")
elif tool in ("xcrun", "spctl", "lipo"):
    pass
elif tool == "hdiutil":
    if args[0] == "attach":
        mount = Path(args[args.index("-mountpoint") + 1])
        contents = mount / "System Headroom Direct.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS/System Headroom Direct").write_text("binary fixture")
        (contents / "Frameworks/Sparkle.framework").mkdir(parents=True)
        info = dict(CFBundleShortVersionString="1.1", CFBundleVersion="15",
                    CFBundleIdentifier="com.vinnycarpenter.SystemHeadroom.Direct",
                    CFBundleExecutable="System Headroom Direct", LSMinimumSystemVersion="14.0",
                    SUFeedURL="https://www.macheadroom.com/direct/appcast.xml",
                    SUEnableAutomaticChecks=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        (mount / "Applications").symlink_to("/Applications")
elif tool == "generate_appcast":
    Path(args[args.index("-o") + 1]).write_text("<rss>signed appcast fixture</rss>\n")
elif tool == "aws":
    if args[:2] == ["s3api", "list-objects-v2"]:
        bucket = args[args.index("--bucket") + 1]
        prefix = args[args.index("--prefix") + 1]
        if (cloud / bucket / prefix).exists():
            print(prefix)
    elif args[:2] == ["s3", "cp"]:
        def local_path(value):
            if value.startswith("s3://"):
                return cloud / value[len("s3://"):]
            return Path(value)
        source, target = map(local_path, args[2:4])
        if args[3].startswith("s3://") and os.environ.get("FAIL_UPLOAD") == "1":
            sys.exit("simulated upload failure")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    elif args[:2] == ["cloudfront", "create-invalidation"]:
        print("I-TEST-INVALIDATION")
    elif args[:3] == ["cloudfront", "wait", "invalidation-completed"]:
        if os.environ.get("FAIL_INVALIDATION") == "1":
            sys.exit("simulated invalidation wait failure")
    else:
        sys.exit("Unexpected AWS arguments: " + repr(args))
elif tool == "curl":
    url = next(arg for arg in args if arg.startswith("https://"))
    remote = urlsplit(url).path.removeprefix("/direct/")
    if remote == "appcast.xml":
        source = cloud / "site/direct/appcast.xml"
    else:
        source = cloud / "release" / remote
    target = Path(args[args.index("-o") + 1])
    if os.environ.get("FAIL_VERIFY") == remote:
        target.write_text("stale public bytes")
    else:
        shutil.copyfile(source, target)
else:
    sys.exit("Unexpected fake tool " + tool)
'''


@unittest.skipUnless(shutil.which("zsh") and shutil.which("plutil"), "requires macOS tools")
class DirectPublishTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Scripts").mkdir()
        for name in ("publish-direct.sh", "direct-release-metadata.py"):
            shutil.copy2(SCRIPTS / name, self.root / "Scripts" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        shim = self.bin / "fake-tool"
        shim.write_text(FAKE_TOOL)
        shim.chmod(0o755)
        for tool in ("codesign", "xcrun", "hdiutil", "spctl", "lipo", "aws", "curl"):
            (self.bin / tool).symlink_to(shim)
        sparkle = self.root / "Vendor/Sparkle/bin"
        sparkle.mkdir(parents=True)
        (sparkle / "generate_appcast").symlink_to(shim)
        self.dmg = self.root / "input.dmg"
        self.dmg.write_bytes(b"notarized universal DMG fixture")
        self.output = self.root / "release/staged"
        self.log = self.root / "commands.jsonl"
        self.environment = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                                COMMAND_LOG=str(self.log), FAKE_CLOUD=str(self.root / "cloud"),
                                DIRECT_RELEASE_BUCKET="release", DIRECT_SITE_BUCKET="site",
                                DIRECT_CLOUDFRONT_DISTRIBUTION_ID="distribution")

    def run_script(self, *arguments, **environment):
        return subprocess.run(["zsh", str(self.root / "Scripts/publish-direct.sh"),
                               *arguments, str(self.dmg)],
                              env=dict(self.environment, **environment), text=True, capture_output=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_stage_only_uses_requested_directory_without_publishing(self):
        result = self.run_script("--output-dir", str(self.output), "--stage-only")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.output / "updates/latest.json").is_file())
        self.assertTrue((self.output / "appcast.xml").is_file())
        self.assertFalse((self.output / "publish.json").exists())
        self.assertFalse(any(command[0] in ("aws", "curl") for command in self.commands()))

    def test_default_staging_is_fresh_on_each_run(self):
        for _ in range(2):
            result = self.run_script()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        directories = list((self.root / "build/direct-publish").iterdir())
        self.assertEqual(len(directories), 2)
        self.assertTrue(all(not (directory / "publish.json").exists() for directory in directories))

    def test_existing_output_directory_is_rejected_before_external_commands(self):
        self.output.mkdir(parents=True)
        receipt = self.output / "publish.json"
        receipt.write_text("prior receipt")
        result = self.run_script("--publish", "--output-dir", str(self.output))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("output directory already exists", result.stderr)
        self.assertEqual(receipt.read_text(), "prior receipt")
        self.assertEqual(self.commands(), [])

    def test_dangling_output_symlink_is_rejected(self):
        self.output.parent.mkdir(parents=True)
        self.output.symlink_to(self.root / "missing")
        result = self.run_script("--output-dir", str(self.output))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("output directory already exists", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_conflicting_modes_are_rejected(self):
        result = self.run_script("--stage-only", "--publish")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("choose only one", result.stderr)
        self.assertEqual(self.commands(), [])

    def test_verified_publication_writes_receipt_after_all_http_checks(self):
        result = self.run_script("--publish", "--output-dir", str(self.output))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads((self.output / "publish.json").read_text())
        self.assertEqual(receipt["version"], "1.1")
        self.assertEqual(receipt["build"], "15")
        self.assertEqual(receipt["downloadURL"],
                         "https://www.macheadroom.com/direct/updates/System-Headroom-Direct.dmg")
        self.assertEqual(receipt["artifactURL"],
                         "https://www.macheadroom.com/direct/updates/System-Headroom-Direct-1.1-15.dmg")
        self.assertEqual(receipt["sha256"], hashlib.sha256(self.dmg.read_bytes()).hexdigest())
        self.assertEqual(receipt["cloudfrontInvalidationID"], "I-TEST-INVALIDATION")
        self.assertIsNotNone(datetime.fromisoformat(receipt["publishedAt"]).tzinfo)
        commands = self.commands()
        self.assertEqual(sum(command[0] == "curl" for command in commands), 4)
        self.assertTrue(any(command[:4] == ["aws", "cloudfront", "wait", "invalidation-completed"]
                            for command in commands))

    def test_failed_upload_never_writes_publication_receipt(self):
        result = self.run_script("--publish", "--output-dir", str(self.output), FAIL_UPLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated upload failure", result.stderr)
        self.assertFalse((self.output / "publish.json").exists())
        self.assertFalse(any(command[0] == "curl" for command in self.commands()))

    def test_failed_versioned_download_never_advertises_release(self):
        result = self.run_script("--publish", "--output-dir", str(self.output),
                                 FAIL_VERIFY="updates/System-Headroom-Direct-1.1-15.dmg")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("public DMG differs", result.stderr)
        self.assertFalse((self.output / "publish.json").exists())
        self.assertEqual(sum(command[:3] == ["aws", "s3", "cp"] for command in self.commands()), 1)

    def test_failed_invalidation_never_writes_publication_receipt(self):
        result = self.run_script("--publish", "--output-dir", str(self.output), FAIL_INVALIDATION="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated invalidation wait failure", result.stderr)
        self.assertFalse((self.output / "publish.json").exists())

    def test_each_failed_final_public_check_prevents_receipt(self):
        for remote in ("appcast.xml", "updates/latest.json", "updates/System-Headroom-Direct.dmg"):
            with self.subTest(remote=remote):
                output = self.root / "attempts" / remote.replace("/", "-")
                result = self.run_script("--output-dir", str(output), "--publish", FAIL_VERIFY=remote)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"public {remote} differs", result.stderr)
                self.assertFalse((output / "publish.json").exists())


if __name__ == "__main__":
    unittest.main()
