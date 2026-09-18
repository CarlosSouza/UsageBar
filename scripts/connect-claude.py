#!/usr/bin/python3
"""Explicit installer; preserves the user's existing statusline and settings."""
import json
import os
from pathlib import Path
import shlex
import shutil
import tempfile
import time


def main():
    settings_path = Path.home() / ".claude/settings.json"
    directory = Path.home() / "Library/Application Support/UsageBar"
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    previous = settings.get("statusLine")
    if previous and (not isinstance(previous, dict) or previous.get("type") != "command"):
        raise SystemExit("Formato de statusline desconhecido. Nenhuma alteração realizada.")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    collector = directory / "claude-statusline.py"
    command = "/usr/bin/python3 " + shlex.quote(str(collector))
    if previous and previous.get("command") != command:
        (directory / "previous-statusline.json").write_text(json.dumps(previous))
        os.chmod(directory / "previous-statusline.json", 0o600)
    shutil.copyfile(Path(__file__).with_name("claude-statusline.py"), collector)
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    backup = settings_path.with_name(f"settings.json.usagebar-backup-{time.time_ns()}")
    if settings_path.exists():
        shutil.copy2(settings_path, backup)
        os.chmod(backup, 0o600)
    settings["statusLine"] = {**(previous or {}), "type": "command", "command": command}
    fd, temporary = tempfile.mkstemp(dir=settings_path.parent, prefix=".usagebar-")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(settings, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.replace(temporary, settings_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Claude conectado. Reinicie a sessão do Claude Code e envie uma mensagem.")
    print(f"Configuração anterior: {backup}" if backup.exists() else "Nenhuma configuração anterior existia.")


if __name__ == "__main__":
    main()
