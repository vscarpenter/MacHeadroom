import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "metadata", Path(__file__).resolve().parents[1] / "direct-release-metadata.py"
)
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.artifact = Path(self.tmp.name) / "System-Headroom-Direct-1.1-15.dmg"
        self.artifact.write_bytes(b"release fixture")
        self.info = {
            "CFBundleShortVersionString": "1.1",
            "CFBundleVersion": "15",
            "CFBundleIdentifier": metadata.BUNDLE_ID,
            "SUFeedURL": "https://www.macheadroom.com/direct/appcast.xml",
            "SUEnableAutomaticChecks": True,
            "DirectEditionClaimURL": "",
            "LSMinimumSystemVersion": "14.0",
        }

    def test_free_download_has_public_immutable_url_and_checksum(self):
        result = metadata.create_manifest(self.info, self.artifact)
        self.assertEqual(result["downloadURL"], metadata.BASE_URL + self.artifact.name)
        self.assertEqual(result["key"], "updates/" + self.artifact.name)
        self.assertEqual(result["size"], 15)
        self.assertEqual(len(result["sha256"]), 64)

    def test_wrong_edition_feed_or_purchase_gate_is_rejected(self):
        for field, value in [
            ("CFBundleIdentifier", "com.vinnycarpenter.MacHeadroom"),
            ("SUFeedURL", "https://example.com/feed.xml"),
            ("SUEnableAutomaticChecks", False),
            ("DirectEditionClaimURL", "https://example.com/claim"),
            ("CFBundleVersion", "../15"),
            ("CFBundleShortVersionString", "../1.1"),
        ]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                metadata.create_manifest({**self.info, field: value}, self.artifact)

    def test_rebuild_needs_new_filename(self):
        with self.assertRaises(ValueError):
            metadata.create_manifest({**self.info, "CFBundleVersion": "16"}, self.artifact)

    def test_next_build_and_exact_retry_are_allowed(self):
        previous = metadata.create_manifest(self.info, self.artifact)
        metadata.compare_releases(previous, previous)
        metadata.compare_releases(previous, {**previous, "build": "16", "sha256": "new"})

    def test_downgrade_replaced_bytes_and_invalid_prior_build_are_rejected(self):
        previous = metadata.create_manifest(self.info, self.artifact)
        for field, value in [("build", "14"), ("sha256", "different"), ("version", "1.2"), ("key", "updates/replaced.dmg")]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                metadata.compare_releases(previous, {**previous, field: value})
        with self.assertRaises(ValueError):
            metadata.compare_releases({**previous, "build": "unknown"}, previous)


if __name__ == "__main__":
    unittest.main()
