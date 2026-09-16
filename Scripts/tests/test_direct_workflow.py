"""Verify Direct workflow gates and durable receipts with local mock commands."""

import hashlib
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1]
loader = SourceFileLoader("direct_workflow", str(SCRIPTS / "direct-release"))
workflow = module_from_spec(spec_from_loader(loader.name, loader))
loader.exec_module(workflow)


class DirectWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(patch.stopall)
        patch.object(workflow, "ROOT", self.root).start()
        patch("sys.stdout", new=io.StringIO()).start()
        patch.dict(os.environ, {}, clear=True).start()
        config = self.root / "Configuration"
        config.mkdir()
        self.defaults = {
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
            "DIRECT_DEVELOPER_ID_APPLICATION": "",
            "DIRECT_DEVELOPER_TEAM_ID": "TEAM123456",
            "DIRECT_NOTARY_PROFILE": "test-notary-profile",
            "DIRECT_RELEASE_BUCKET": "",
            "DIRECT_SITE_BUCKET": "",
            "DIRECT_CLOUDFRONT_DISTRIBUTION_ID": "",
            "AWS_PROFILE": "",
            "AWS_REGION": "us-east-1",
        }
        (config / "DirectRelease.example.json").write_text(json.dumps(self.defaults))
        self.config = config / "DirectRelease.local.json"
        self.output = self.root / "runs/example"
        self.identity = "Developer ID Application: Example Developer (TEAM123456)"
        self.release_env = {**self.defaults, "DIRECT_DEVELOPER_ID_APPLICATION": self.identity}
        self.commands = []
        self.app_test_output = "Test run with 106 tests in 10.123 seconds passed.\n"
        self.failing_command = None
        self.write_publication_receipt = True

    def write_release(self, directory):
        directory.mkdir(parents=True, exist_ok=True)
        artifact = directory / "System-Headroom-Direct-1.1-15.dmg"
        artifact.write_bytes(b"notarized release fixture")
        metadata = {"dmg": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                    "size": artifact.stat().st_size, "version": "1.1", "build": "15"}
        (directory / "release.json").write_text(json.dumps(metadata))
        return artifact

    def make_run(self, status="staged"):
        run = workflow.Run(self.output, {}, create=True)
        artifact = self.write_release(run.directory / "release")
        run.state.update(status=status, releaseDirectory="release")
        run.save()
        return run, artifact

    def fake_subprocess(self, command, **kwargs):
        self.commands.append(command)
        stream = kwargs.get("stdout")
        if stream is not None:
            stream.write("Running " + command[0] + "\n")
        if self.failing_command and self.failing_command(command):
            return subprocess.CompletedProcess(command, 1)
        if command[0] == "xcodebuild":
            stream.write(self.app_test_output)
        elif command[0] == "Scripts/release-direct.sh":
            self.write_release(Path(command[command.index("--output-dir") + 1]))
        elif command[0] == "Scripts/publish-direct.sh":
            output = Path(command[command.index("--output-dir") + 1])
            output.mkdir(parents=True)
            if "--publish" in command and self.write_publication_receipt:
                artifact = Path(command[-1])
                receipt = {"version": "1.1", "build": "15",
                           "downloadURL": "https://www.macheadroom.com/direct/updates/System-Headroom-Direct.dmg",
                           "artifactURL": "https://www.macheadroom.com/direct/updates/" + artifact.name,
                           "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                           "publishedAt": workflow.now(), "cloudfrontInvalidationID": "test-invalidation"}
                (output / "publish.json").write_text(json.dumps(receipt))
        return subprocess.CompletedProcess(command, 0)

    def test_configuration_rejects_unknown_and_secret_keys(self):
        for key in ("UNKNOWN", "AWS_SECRET_ACCESS_KEY", "APPLE_PASSWORD", "DIRECT_SPARKLE_PRIVATE_KEY"):
            with self.subTest(key=key):
                self.config.write_text(json.dumps({key: "example"}))
                with self.assertRaisesRegex(workflow.ReleaseError, "non-secret settings"):
                    workflow.configuration(self.config)

    def test_configuration_rejects_non_object_and_non_single_line_values(self):
        for value in ([], "value", {"AWS_REGION": 1}, {"AWS_REGION": "one\ntwo"}, {"AWS_REGION": "one\rtwo"}):
            with self.subTest(value=value):
                self.config.write_text(json.dumps(value))
                with self.assertRaises(workflow.ReleaseError):
                    workflow.configuration(self.config)

    def test_environment_overrides_saved_settings_and_uses_config_for_empty_values(self):
        with patch.dict(os.environ, {"AWS_PROFILE": "environment-profile", "AWS_REGION": "",
                                     "DIRECT_NOTARY_PROFILE": "environment-notary"}, clear=True):
            env = workflow.environment({"AWS_PROFILE": "saved-profile", "AWS_REGION": "us-west-2",
                                        "DIRECT_NOTARY_PROFILE": "saved-notary"})
        self.assertEqual(env["AWS_PROFILE"], "environment-profile")
        self.assertEqual(env["AWS_REGION"], "us-west-2")
        self.assertEqual(env["DIRECT_NOTARY_PROFILE"], "environment-notary")
        self.assertEqual(env["PYTHONDONTWRITEBYTECODE"], "1")

    def test_setup_preserves_existing_identity_and_settings(self):
        self.config.write_text(json.dumps({"DIRECT_DEVELOPER_ID_APPLICATION": self.identity,
                                           "AWS_PROFILE": "my-profile", "AWS_REGION": "us-west-2"}))
        with patch.object(workflow, "capture") as capture:
            workflow.setup(self.config, ["DIRECT_RELEASE_BUCKET=my-release-bucket"])
        saved = workflow.configuration(self.config)
        self.assertEqual(saved["DIRECT_DEVELOPER_ID_APPLICATION"], self.identity)
        self.assertEqual(saved["AWS_PROFILE"], "my-profile")
        self.assertEqual(saved["AWS_REGION"], "us-west-2")
        self.assertEqual(saved["DIRECT_RELEASE_BUCKET"], "my-release-bucket")
        self.assertEqual(saved["DIRECT_NOTARY_PROFILE"], "test-notary-profile")
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        capture.assert_not_called()

    def test_setup_detects_only_certificate_matching_configured_team(self):
        identities = ('1) HASH "Developer ID Application: Other (OTHERTEAM0)"\n'
                      f'2) HASH "{self.identity}"\n')
        with patch.object(workflow, "capture", return_value=identities):
            workflow.setup(self.config, [])
        self.assertEqual(workflow.configuration(self.config)["DIRECT_DEVELOPER_ID_APPLICATION"], self.identity)

    def test_setup_does_not_choose_between_multiple_matching_certificates(self):
        identities = f'1) HASH "{self.identity}"\n2) HASH "Developer ID Application: Another (TEAM123456)"\n'
        with patch.object(workflow, "capture", return_value=identities):
            workflow.setup(self.config, [])
        self.assertEqual(workflow.configuration(self.config)["DIRECT_DEVELOPER_ID_APPLICATION"], "")

    def test_setup_rejects_secret_overrides_without_writing_config(self):
        with self.assertRaises(workflow.ReleaseError):
            workflow.setup(self.config, ["AWS_SECRET_ACCESS_KEY=example"])
        self.assertFalse(self.config.exists())

    def test_site_settings_accepts_quoted_exported_literals_and_ignores_secrets(self):
        site = self.root / "site.env"
        site.write_text('export S3_BUCKET="s3://my-site-bucket/" # current site\n'
                        "CLOUDFRONT_DISTRIBUTION_ID='E123EXAMPLE'\n"
                        "AWS_SECRET_ACCESS_KEY='deliberately unclosed quote\n"
                        "export APPLE_PASSWORD=$(must-never-run)\n")
        with patch.object(workflow.subprocess, "run") as execute:
            settings = workflow.site_settings(site)
        self.assertEqual(settings, {"DIRECT_SITE_BUCKET": "my-site-bucket",
                                    "DIRECT_CLOUDFRONT_DISTRIBUTION_ID": "E123EXAMPLE"})
        execute.assert_not_called()

    def test_site_settings_rejects_shell_expansion_and_commands_without_execution(self):
        site = self.root / "site.env"
        for value in ('"$(touch should-not-exist)"', '`touch should-not-exist`',
                      '"${BUCKET}"', "my-bucket;touch should-not-exist"):
            with self.subTest(value=value):
                site.write_text(f"S3_BUCKET={value}\nCLOUDFRONT_DISTRIBUTION_ID=E123EXAMPLE\n")
                with patch.object(workflow.subprocess, "run") as execute:
                    with self.assertRaisesRegex(workflow.ReleaseError, "literal hosting value"):
                        workflow.site_settings(site)
                execute.assert_not_called()

    def test_site_settings_requires_both_hosting_keys(self):
        site = self.root / "site.env"
        for content in ("", "S3_BUCKET=my-bucket\n", "CLOUDFRONT_DISTRIBUTION_ID=E123EXAMPLE\n"):
            with self.subTest(content=content):
                site.write_text(content)
                with self.assertRaisesRegex(workflow.ReleaseError, "must define S3_BUCKET and"):
                    workflow.site_settings(site)

    def test_setup_imports_site_settings_then_applies_explicit_overrides(self):
        site = self.root / "site.env"
        site.write_text("S3_BUCKET=site-bucket\nCLOUDFRONT_DISTRIBUTION_ID=E123EXAMPLE\n")
        self.config.write_text(json.dumps({"DIRECT_DEVELOPER_ID_APPLICATION": self.identity,
                                           "DIRECT_RELEASE_BUCKET": "separate-release-bucket"}))
        workflow.setup(self.config, ["DIRECT_SITE_BUCKET=explicit-site-bucket"], site_config=site)
        saved = workflow.configuration(self.config)
        self.assertEqual(saved["DIRECT_SITE_BUCKET"], "explicit-site-bucket")
        self.assertEqual(saved["DIRECT_RELEASE_BUCKET"], "separate-release-bucket")
        self.assertEqual(saved["DIRECT_CLOUDFRONT_DISTRIBUTION_ID"], "E123EXAMPLE")

    def test_doctor_missing_sparkle_stops_before_online_checks(self):
        with patch.object(workflow, "capture", return_value="preflight passed") as capture, \
                patch.object(workflow, "check_signing_key") as key_check:
            with self.assertRaisesRegex(workflow.ReleaseError, "Missing Sparkle generate_appcast"):
                workflow.doctor({}, online=True)
        capture.assert_called_once_with(["Scripts/release-direct.sh", "--preflight"], {})
        key_check.assert_not_called()

    def test_doctor_local_checks_never_contact_apple_or_aws(self):
        binary_directory = self.root / "Vendor/Sparkle/bin"
        binary_directory.mkdir(parents=True)
        for name in ("generate_appcast", "sign_update"):
            binary = binary_directory / name
            binary.write_text("#!/bin/sh\nexit 0\n")
            binary.chmod(0o755)
        with patch.object(workflow, "capture", return_value="preflight passed") as capture, \
                patch.object(workflow, "check_signing_key") as key_check:
            workflow.doctor({})
        capture.assert_called_once_with(["Scripts/release-direct.sh", "--preflight"], {})
        key_check.assert_not_called()

    def test_prepare_prerequisite_failure_stops_before_run_or_build(self):
        with patch.object(workflow, "capture", return_value=""), \
                patch.object(workflow, "doctor", side_effect=workflow.ReleaseError("missing certificate")), \
                patch.object(workflow.subprocess, "run") as run:
            with self.assertRaisesRegex(workflow.ReleaseError, "missing certificate"):
                workflow.prepare(self.release_env, self.output)
        self.assertFalse(self.output.exists())
        run.assert_not_called()

    def test_prepare_fetch_failure_stops_before_credential_checks(self):
        with patch.object(workflow, "capture", side_effect=workflow.ReleaseError("Sparkle unavailable")), \
                patch.object(workflow, "doctor") as doctor, \
                patch.object(workflow.subprocess, "run") as run:
            with self.assertRaisesRegex(workflow.ReleaseError, "Sparkle unavailable"):
                workflow.prepare(self.release_env, self.output)
        doctor.assert_not_called()
        run.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_prepare_failed_tests_stop_before_notarization_or_staging(self):
        self.failing_command = lambda command: "unittest" in command
        with patch.object(workflow, "capture", return_value=""), patch.object(workflow, "doctor"), \
                patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            with self.assertRaisesRegex(workflow.ReleaseError, "release-tests failed"):
                workflow.prepare(self.release_env, self.output)
        state = json.loads((self.output / "workflow.json").read_text())
        self.assertEqual(state["status"], "failed")
        self.assertEqual([step["name"] for step in state["steps"]], ["release-tests"])
        self.assertTrue(Path(state["steps"][0]["log"]).is_file())
        self.assertEqual(len(self.commands), 1)

    def test_prepare_app_test_failure_stops_before_notarization_or_staging(self):
        self.failing_command = lambda command: command[0] == "xcodebuild"
        with patch.object(workflow, "capture", return_value=""), patch.object(workflow, "doctor"), \
                patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            with self.assertRaisesRegex(workflow.ReleaseError, "app-tests failed"):
                workflow.prepare(self.release_env, self.output)
        self.assertEqual([command[0] for command in self.commands][-1], "xcodebuild")
        self.assertFalse((self.output / "release").exists())

    def test_prepare_zero_swift_tests_with_success_exit_stops_before_archive(self):
        self.app_test_output = "Test run with 0 tests in 0.001 seconds passed.\n** TEST SUCCEEDED **\n"
        with patch.object(workflow, "capture", return_value=""), patch.object(workflow, "doctor"), \
                patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            with self.assertRaisesRegex(workflow.ReleaseError, "did not execute a passing Swift test suite"):
                workflow.prepare(self.release_env, self.output)
        state = json.loads((self.output / "workflow.json").read_text())
        self.assertEqual(state["status"], "failed")
        self.assertEqual(state["steps"][-1]["name"], "app-tests")
        self.assertEqual(state["steps"][-1]["status"], "failed")
        self.assertFalse(any(command[0] in ("Scripts/release-direct.sh", "Scripts/publish-direct.sh")
                             for command in self.commands))

    def test_prepare_validates_tests_then_notarizes_and_stages_without_publishing(self):
        with patch.object(workflow, "capture", return_value=""), patch.object(workflow, "doctor"), \
                patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            workflow.prepare(self.release_env, self.output)
        state = json.loads((self.output / "workflow.json").read_text())
        self.assertEqual(state["status"], "staged")
        self.assertEqual([step["name"] for step in state["steps"]],
                         ["release-tests", "update-signature-tests", "app-tests", "notarized-release", "stage"])
        self.assertTrue(all(step["status"] == "passed" for step in state["steps"]))
        self.assertIn("--stage-only", self.commands[-1])
        self.assertFalse(any("--publish" in command for command in self.commands))
        self.assertNotIn("publication", state)

    def test_prepare_signs_sandboxed_app_tests_with_the_configured_release_identity(self):
        with patch.object(workflow, "capture", return_value=""), patch.object(workflow, "doctor"), \
                patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            workflow.prepare(self.release_env, self.output)
        command = next(command for command in self.commands if command[0] == "xcodebuild")
        self.assertIn("CODE_SIGN_STYLE=Manual", command)
        self.assertIn(f"CODE_SIGN_IDENTITY={self.identity}", command)
        self.assertIn("DEVELOPMENT_TEAM=TEAM123456", command)
        self.assertEqual(command[command.index("-scheme") + 1], "SystemHeadroom")
        self.assertEqual(command[command.index("-configuration") + 1], "Debug")
        self.assertFalse(any(arg.startswith(("CODE_SIGN_ENTITLEMENTS=", "ENABLE_APP_SANDBOX=",
                                             "-only-testing", "-skip-testing", "-xcconfig"))
                             for arg in command))

    def test_artifact_detects_same_size_byte_changes(self):
        run, artifact = self.make_run()
        artifact.write_bytes(b"X" * artifact.stat().st_size)
        with self.assertRaisesRegex(workflow.ReleaseError, "DMG changed"):
            run.artifact()

    def test_artifact_detects_changed_size_even_with_matching_hash(self):
        run, artifact = self.make_run()
        receipt_path = artifact.parent / "release.json"
        receipt = json.loads(receipt_path.read_text())
        receipt["size"] += 1
        receipt_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(workflow.ReleaseError, "DMG changed"):
            run.artifact()

    def test_artifact_rejects_receipt_filename_outside_release_directory(self):
        run, artifact = self.make_run()
        receipt_path = artifact.parent / "release.json"
        receipt = json.loads(receipt_path.read_text())
        receipt["dmg"] = "../outside.dmg"
        receipt_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(workflow.ReleaseError, "Invalid DMG filename"):
            run.artifact()

    def test_publish_requires_staged_status(self):
        run, _ = self.make_run(status="preparing")
        with patch.object(workflow.subprocess, "run") as execute:
            with self.assertRaisesRegex(workflow.ReleaseError, "Stage the release successfully"):
                run.stage(publish=True)
        execute.assert_not_called()

    def test_publish_uses_exact_notarized_dmg_without_rebuilding(self):
        run, artifact = self.make_run()
        before = artifact.read_bytes()
        with patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            run.stage(publish=True)
        self.assertEqual(len(self.commands), 1)
        self.assertEqual(self.commands[0][0], "Scripts/publish-direct.sh")
        self.assertIn("--publish", self.commands[0])
        self.assertEqual(Path(self.commands[0][-1]), artifact)
        self.assertEqual(artifact.read_bytes(), before)
        reloaded = workflow.Run(self.output, {})
        self.assertEqual(reloaded.state["status"], "published")
        self.assertEqual(reloaded.state["publication"]["sha256"], hashlib.sha256(before).hexdigest())

    def test_publish_without_receipt_never_claims_success(self):
        run, _ = self.make_run()
        self.write_publication_receipt = False
        with patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            with self.assertRaises(OSError):
                run.stage(publish=True)
        reloaded = workflow.Run(self.output, {})
        self.assertEqual(reloaded.state["status"], "publish-failed")
        self.assertNotIn("publication", reloaded.state)

    def test_failed_publication_can_retry_with_fresh_output_and_same_artifact(self):
        run, artifact = self.make_run()
        self.failing_command = lambda command: "--publish" in command
        with patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            with self.assertRaises(workflow.ReleaseError):
                run.stage(publish=True)
            retry = workflow.Run(self.output, {})
            self.assertEqual(retry.state["status"], "publish-failed")
            self.failing_command = None
            retry.stage(publish=True)
        state = workflow.Run(self.output, {}).state
        self.assertEqual(state["status"], "published")
        self.assertEqual([step["status"] for step in state["steps"]], ["failed", "passed"])
        self.assertTrue(all(Path(command[-1]) == artifact for command in self.commands))
        outputs = [command[command.index("--output-dir") + 1] for command in self.commands]
        self.assertEqual(len(set(outputs)), 2)

    def test_interrupted_publication_preserves_retryable_state(self):
        run, _ = self.make_run()
        with patch.object(workflow.subprocess, "run", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                run.stage(publish=True)
        retry = workflow.Run(self.output, {})
        self.assertEqual(retry.state["status"], "publish-failed")
        self.assertEqual(retry.state["steps"][-1]["status"], "failed")
        with patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            retry.stage(publish=True)
        self.assertEqual(workflow.Run(self.output, {}).state["status"], "published")

    def test_stage_failure_cannot_be_published_without_successful_restage(self):
        run, _ = self.make_run(status="preparing")
        self.failing_command = lambda command: "--stage-only" in command
        with patch.object(workflow.subprocess, "run", side_effect=self.fake_subprocess):
            with self.assertRaises(workflow.ReleaseError):
                run.stage()
            retry = workflow.Run(self.output, {})
            self.assertEqual(retry.state["status"], "stage-failed")
            with self.assertRaisesRegex(workflow.ReleaseError, "Stage the release successfully"):
                retry.stage(publish=True)
            self.failing_command = None
            retry.stage()
            retry.stage(publish=True)
        self.assertEqual(workflow.Run(self.output, {}).state["status"], "published")
        self.assertEqual(len(self.commands), 3)


if __name__ == "__main__":
    unittest.main()
