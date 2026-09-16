from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bump-direct-version.py"
SPEC = importlib.util.spec_from_file_location("bump_direct_version", SCRIPT)
bump = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bump)

CONFIG = "// settings\r\nMARKETING_VERSION = 1.1\r\nCURRENT_PROJECT_VERSION = 15\r\nOTHER = unchanged\r\n"
IDENTITY = 'before\r\n    #expect(short == "1.1")\r\n    #expect(build == "15")\r\nafter\r\n'


class VersionPlanTests(unittest.TestCase):
    def test_default_only_increments_build_and_preserves_other_bytes(self):
        plan = bump.plan_version_bump(CONFIG, IDENTITY)
        self.assertEqual(plan["version"], "1.1")
        self.assertEqual(plan["build"], "16")
        self.assertEqual(plan["config"], CONFIG.replace("= 15", "= 16"))
        self.assertEqual(plan["identity_tests"], IDENTITY.replace('"15"', '"16"'))

    def test_explicit_version_and_build_update_both_files(self):
        plan = bump.plan_version_bump(CONFIG, IDENTITY, version="1.2.3", build="22")
        self.assertEqual(plan["config"], CONFIG.replace("1.1", "1.2.3").replace("15", "22"))
        self.assertEqual(plan["identity_tests"], IDENTITY.replace("1.1", "1.2.3").replace("15", "22"))

    def test_numeric_comparison_allows_equivalent_and_larger_versions(self):
        for version in ("1.1.0", "1.10", "2", "1.1.1"):
            with self.subTest(version=version):
                self.assertEqual(bump.plan_version_bump(CONFIG, IDENTITY, version=version)["version"], version)

    def test_rejects_version_downgrades(self):
        for version in ("1", "1.0.99", "0.99.99"):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "decrease"):
                bump.plan_version_bump(CONFIG, IDENTITY, version=version)

    def test_rejects_invalid_requested_versions(self):
        for version in ("", "1.2.3.4", "1..2", "v1.2", "1.2-beta", "-1.2", " 1.2", "1.2\n", "١.٢"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                bump.plan_version_bump(CONFIG, IDENTITY, version=version)

    def test_requires_strictly_increasing_positive_integer_build(self):
        for build in ("15", "14", "0", "-1", "", "1.2", "16.0", "16\n", " 16", "١٦"):
            with self.subTest(build=build), self.assertRaises(ValueError):
                bump.plan_version_bump(CONFIG, IDENTITY, build=build)

    def test_config_assignments_and_test_pins_must_be_unique_and_present(self):
        for config, identity in (
            (CONFIG.replace("MARKETING_VERSION", "MISSING"), IDENTITY),
            (CONFIG.replace("CURRENT_PROJECT_VERSION", "MISSING"), IDENTITY),
            (CONFIG + "MARKETING_VERSION = 1.1\n", IDENTITY),
            (CONFIG + "CURRENT_PROJECT_VERSION = 15\n", IDENTITY),
            (CONFIG, IDENTITY.replace("#expect(short", "#expect(other")),
            (CONFIG, IDENTITY.replace("#expect(build", "#expect(other")),
            (CONFIG, IDENTITY + '#expect(short == "1.1")\n'),
            (CONFIG, IDENTITY + '#expect(build == "15")\n'),
        ):
            with self.subTest(config=config, identity=identity), self.assertRaises(ValueError):
                bump.plan_version_bump(config, identity)

    def test_refuses_to_overwrite_test_pins_that_disagree_with_config(self):
        for old, new in (("1.1", "1.2"), ("15", "99")):
            with self.subTest(pin=old), self.assertRaisesRegex(ValueError, "match"):
                bump.plan_version_bump(CONFIG, IDENTITY.replace(old, new))

    def test_existing_config_must_have_valid_values(self):
        for old, new in (("1.1", "1.2.3.4"), ("15", "0"), ("15", "fifteen")):
            with self.subTest(value=new), self.assertRaises(ValueError):
                bump.plan_version_bump(CONFIG.replace(old, new), IDENTITY.replace(old, new))

    def test_preserves_assignment_spacing(self):
        config = CONFIG.replace("MARKETING_VERSION = 1.1", "\tMARKETING_VERSION\t=\t1.1  ")
        result = bump.plan_version_bump(config, IDENTITY, version="1.2")
        self.assertEqual(result["config"], config.replace("1.1", "1.2").replace("15", "16"))


class VersionFilesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "Configuration/Shared.xcconfig"
        self.identity = self.root / "SystemHeadroomTests/AppIdentityTests.swift"
        self.config.parent.mkdir()
        self.identity.parent.mkdir()
        self.config.write_bytes(CONFIG.encode())
        self.identity.write_bytes(IDENTITY.encode())
        self.config.chmod(0o640)
        self.identity.chmod(0o644)

    def test_updates_files_and_preserves_modes_and_line_endings(self):
        result = bump.bump_files(self.root, version="1.2", build="20")
        self.assertEqual(result["version"], "1.2")
        self.assertEqual(result["build"], "20")
        self.assertEqual(self.config.read_bytes(), CONFIG.replace("1.1", "1.2").replace("15", "20").encode())
        self.assertEqual(self.identity.read_bytes(), IDENTITY.replace("1.1", "1.2").replace("15", "20").encode())
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.identity.stat().st_mode & 0o777, 0o644)

    def test_parse_mismatch_leaves_all_files_unchanged(self):
        self.identity.write_bytes(IDENTITY.replace('"15"', '"14"').encode())
        before = (self.config.read_bytes(), self.identity.read_bytes())
        with self.assertRaises(ValueError):
            bump.bump_files(self.root)
        self.assertEqual((self.config.read_bytes(), self.identity.read_bytes()), before)

    def test_missing_second_file_does_not_change_config(self):
        self.identity.unlink()
        with self.assertRaises(OSError):
            bump.bump_files(self.root)
        self.assertEqual(self.config.read_bytes(), CONFIG.encode())

    def test_failure_replacing_second_file_restores_first(self):
        real_replace = bump.os.replace
        calls = 0

        def fail_second_replace(source, target):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("simulated replacement failure")
            return real_replace(source, target)

        with patch.object(bump.os, "replace", side_effect=fail_second_replace):
            with self.assertRaisesRegex(OSError, "simulated"):
                bump.bump_files(self.root)
        self.assertEqual(self.config.read_bytes(), CONFIG.encode())
        self.assertEqual(self.identity.read_bytes(), IDENTITY.encode())
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)
        self.assertEqual(list(self.config.parent.iterdir()), [self.config])
        self.assertEqual(list(self.identity.parent.iterdir()), [self.identity])

    def test_cli_reports_new_identity_and_changed_paths(self):
        output = io.StringIO()
        with redirect_stdout(output):
            bump.main(["--version", "1.2", "--build", "20"], root=self.root)
        self.assertIn("Release version: 1.2 (20)", output.getvalue())
        self.assertIn("Configuration/Shared.xcconfig", output.getvalue())
        self.assertIn("SystemHeadroomTests/AppIdentityTests.swift", output.getvalue())


if __name__ == "__main__":
    unittest.main()
