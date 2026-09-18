import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("collector", Path(__file__).resolve().parents[1] / "scripts/claude-statusline.py")
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
install_spec = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "scripts/connect-claude.py")
installer = importlib.util.module_from_spec(install_spec)
install_spec.loader.exec_module(installer)


class CollectorTests(unittest.TestCase):
    def test_installer_preserves_settings_and_does_not_chain_itself(self):
        with tempfile.TemporaryDirectory() as path:
            home = Path(path)
            settings = home / ".claude/settings.json"
            settings.parent.mkdir()
            original = {"statusLine": {"type": "command", "command": "echo old", "padding": 1}, "other": {"keep": True}}
            settings.write_text(json.dumps(original))
            with patch.object(Path, "home", return_value=home), patch("builtins.print"):
                installer.main()
                installer.main()
            updated = json.loads(settings.read_text())
            self.assertEqual(updated["other"], original["other"])
            self.assertEqual(updated["statusLine"]["padding"], 1)
            previous = json.loads((home / "Library/Application Support/UsageBar/previous-statusline.json").read_text())
            self.assertEqual(previous["command"], "echo old")
            self.assertEqual(len(list(settings.parent.glob("settings.json.usagebar-backup-*"))), 2)

    def test_only_metrics_are_saved_and_replay_stays_old(self):
        with tempfile.TemporaryDirectory() as path:
            directory = Path(path)
            payload = {"rate_limits": {"five_hour": {"used_percentage": 90, "resets_at": 1800003600}},
                       "session_id": "private-session", "transcript_path": "private-path"}
            collector.collect(json.dumps(payload), directory)
            first = (directory / "claude.json").read_text()
            self.assertNotIn("private", first)
            collector.collect(json.dumps(payload), directory)
            self.assertEqual(first, (directory / "claude.json").read_text())
            self.assertEqual((directory / "claude.json").stat().st_mode & 0o777, 0o600)

    def test_missing_and_invalid_metrics_clear_previous_sample(self):
        with tempfile.TemporaryDirectory() as path:
            directory = Path(path)
            collector.collect('{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":1800003600}}}', directory)
            collector.collect('{"rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1800003600}}}', directory)
            self.assertEqual(json.loads((directory / "claude.json").read_text())["rate_limits"], {})
            collector.collect('{}', directory)
            self.assertEqual(json.loads((directory / "claude.json").read_text())["rate_limits"], {})


if __name__ == "__main__":
    unittest.main()
