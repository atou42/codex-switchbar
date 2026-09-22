"""Pure configuration tests; no certificates or Keychain items are accessed."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
from signing_policy import SigningError, read_config, resolve_identity, validate_identity


FINGERPRINT = "1234567890ABCDEF1234567890ABCDEF12345678"


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="codex-switch-signing-policy-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "signing.json"

    def write_config(self, contents=None):
        if contents is None:
            contents = json.dumps({"schemaVersion": 1, "certificateSHA1": FINGERPRINT})
        self.path.write_text(contents, encoding="utf-8")
        self.path.chmod(0o600)
        return self.path.read_bytes()

    def assert_rejected_without_changes(self):
        original = self.path.read_bytes()
        mode = self.path.stat().st_mode
        for operation in (read_config, resolve_identity):
            with self.subTest(operation=operation.__name__):
                with self.assertRaises(SigningError):
                    operation(self.path)
                self.assertEqual(self.path.read_bytes(), original)
                self.assertEqual(self.path.stat().st_mode, mode)

    def test_valid_identity_and_config_preserve_exact_selected_certificate(self):
        original = self.write_config()
        self.assertEqual(validate_identity(FINGERPRINT), FINGERPRINT)
        self.assertEqual(read_config(self.path), FINGERPRINT)
        self.assertEqual(resolve_identity(self.path), FINGERPRINT)
        self.assertEqual(self.path.read_bytes(), original)
        lower = FINGERPRINT.lower()
        self.assertEqual(validate_identity(lower), FINGERPRINT)
        original = self.write_config(json.dumps({"schemaVersion": 1, "certificateSHA1": lower}))
        self.assertEqual(read_config(self.path), FINGERPRINT)
        self.assertEqual(self.path.read_bytes(), original)

    def test_invalid_identity_never_becomes_an_ad_hoc_signer(self):
        for value in ("", "-", "Developer ID Application: Example", FINGERPRINT[:-1],
                      FINGERPRINT + "0", "G" * 40, " " + FINGERPRINT,
                      FINGERPRINT + "\n", None, True, 123, [FINGERPRINT]):
            with self.subTest(value=value):
                with self.assertRaises(SigningError):
                    validate_identity(value)

    def test_absent_config_requires_explicit_ad_hoc_request(self):
        for operation in (read_config, resolve_identity):
            with self.subTest(operation=operation.__name__):
                with self.assertRaises(SigningError):
                    operation(self.path)
        self.assertEqual(resolve_identity(self.path, ad_hoc=True), "-")
        self.assertFalse(self.path.exists())

    def test_malformed_or_ambiguous_config_fails_without_rewriting(self):
        invalid = [
            "", "{", "null", "[]", '"signer"', "{}",
            json.dumps({"schemaVersion": 2, "certificateSHA1": FINGERPRINT}),
            json.dumps({"schemaVersion": True, "certificateSHA1": FINGERPRINT}),
            json.dumps({"schemaVersion": "1", "certificateSHA1": FINGERPRINT}),
            json.dumps({"schemaVersion": 1.0, "certificateSHA1": FINGERPRINT}),
            json.dumps({"certificateSHA1": FINGERPRINT}),
            json.dumps({"schemaVersion": 1}),
            json.dumps({"schemaVersion": 1, "certificateSHA1": ""}),
            json.dumps({"schemaVersion": 1, "certificateSHA1": "-"}),
            json.dumps({"schemaVersion": 1, "certificateSHA1": None}),
            json.dumps({"schemaVersion": 1, "certificateSHA1": [FINGERPRINT]}),
            json.dumps({"schemaVersion": 1, "certificateSHA1": FINGERPRINT, "identity": "-"}),
            '{"schemaVersion":1,"schemaVersion":1,"certificateSHA1":"' + FINGERPRINT + '"}',
            '{"schemaVersion":1,"certificateSHA1":"' + FINGERPRINT + '","certificateSHA1":"' + "A" * 40 + '"}',
        ]
        for contents in invalid:
            with self.subTest(contents=contents):
                self.write_config(contents)
                self.assert_rejected_without_changes()

    def test_group_or_world_writable_config_is_rejected_without_chmod(self):
        for mode in (0o620, 0o602, 0o666):
            with self.subTest(mode=oct(mode)):
                self.write_config()
                self.path.chmod(mode)
                self.assert_rejected_without_changes()

    def test_symlink_and_dangling_symlink_are_rejected_without_replacement(self):
        original = self.write_config()
        target = self.path.with_name("target.json")
        self.path.rename(target)
        self.path.symlink_to(target)
        for dangling in (False, True):
            if dangling:
                target.unlink()
            for operation in (read_config, resolve_identity):
                with self.subTest(dangling=dangling, operation=operation.__name__):
                    with self.assertRaises(SigningError):
                        operation(self.path)
                    self.assertTrue(self.path.is_symlink())
            if not dangling:
                self.assertEqual(target.read_bytes(), original)

    def test_non_regular_config_is_rejected_without_removal(self):
        self.path.mkdir(mode=0o700)
        for operation in (read_config, resolve_identity):
            with self.subTest(operation=operation.__name__):
                with self.assertRaises(SigningError):
                    operation(self.path)
        self.assertTrue(self.path.is_dir())
        self.path.rmdir()
        os.mkfifo(self.path, mode=0o600)
        # A FIFO must be rejected before opening it blocks for a writer.
        # The child bounds the test even if that validation regresses.
        script = """import sys
sys.path.insert(0, sys.argv[1])
from signing_policy import SigningError, read_config
try:
    read_config(sys.argv[2])
except SigningError:
    sys.exit(0)
sys.exit('FIFO was accepted as a signing configuration')
"""
        result = subprocess.run(
            [sys.executable, "-c", script, sys.path[0], str(self.path)],
            timeout=2, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.path.exists())

    def test_foreign_owned_config_is_rejected_without_rewriting(self):
        self.write_config()
        with patch("os.getuid", return_value=os.getuid() + 1):
            self.assert_rejected_without_changes()

    def test_explicit_ad_hoc_cannot_downgrade_any_existing_configuration(self):
        for contents in (None, "", "{broken", "null"):
            with self.subTest(contents=contents):
                original = self.write_config(contents)
                with self.assertRaises(SigningError):
                    resolve_identity(self.path, ad_hoc=True)
                self.assertEqual(self.path.read_bytes(), original)
        self.path.unlink()
        self.path.mkdir(mode=0o700)
        with self.assertRaises(SigningError):
            resolve_identity(self.path, ad_hoc=True)
        self.path.rmdir()
        self.path.symlink_to(self.path.with_name("missing.json"))
        with self.assertRaises(SigningError):
            resolve_identity(self.path, ad_hoc=True)
        self.assertTrue(self.path.is_symlink())


if __name__ == "__main__":
    unittest.main()
