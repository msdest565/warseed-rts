"""Offline safety checks: no provider requests or real credentials."""
import importlib.util
import json
import tempfile
import unittest
import urllib.error
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "low_cost", Path(__file__).resolve().parents[2] / "tools/ask_low_cost_ai.py")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class ClientTests(unittest.TestCase):
    def test_prompt_and_output_bounds(self):
        for prompt, cap in [("", 10), ("x" * 16001, 10), ("review", 4097),
                            ("secret-test", 10), ("sk-" + "x" * 20, 10)]:
            with self.assertRaises(ValueError):
                client.prepare(prompt, "secret-test", "model", cap)
        payload = client.prepare("review", "secret-test", "model", 128)
        self.assertFalse(payload["stream"])
        self.assertNotIn("tools", payload)

    def test_redirect_is_refused(self):
        self.assertIsNone(client.NoRedirect().redirect_request(
            None, None, 302, "redirect", {}, "https://other.invalid"))

    def test_response_redaction_and_usage(self):
        content, usage, finish = client.summarize({"choices": [{"message": {
            "content": "secret-test"}, "finish_reason": "length"}],
            "usage": {"prompt_tokens": 12, "completion_tokens": "secret-test"}}, "secret-test")
        self.assertEqual(content, "[REDACTED]")
        self.assertEqual(usage, {"prompt_tokens": 12})
        self.assertEqual(finish, "length")

    def test_failed_call_is_not_retried_or_leaked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "key").write_text("secret-test")
            (root / "prompt").write_text("review")
            args = Namespace(prompt=root / "prompt", key_file=root / "key", model="model",
                             max_tokens=128, run_id="unit")
            failure = urllib.error.HTTPError("https://example.invalid", 429,
                                             "secret-test", {}, None)
            with patch.object(client, "ROOT", root), patch.object(
                    client, "request_once", side_effect=failure) as call, patch("builtins.print"):
                self.assertEqual(client.run(args), 1)
                with self.assertRaises(FileExistsError):
                    client.run(args)
                self.assertEqual(call.call_count, 1)
            receipt = (root / "artifacts/delegation/unit/receipt.json").read_text()
            self.assertNotIn("secret-test", receipt)
            self.assertEqual(json.loads(receipt)["http_status"], 429)

    def test_incomplete_response_is_not_success(self):
        with self.assertRaises(ValueError):
            client.summarize({"choices": [{"message": {"content": ""}}]}, "secret-test")


if __name__ == "__main__":
    unittest.main()
