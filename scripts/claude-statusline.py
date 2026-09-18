#!/usr/bin/python3
"""Export only Claude quota fields; preserve an existing statusline command."""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def collect(raw, directory):
    payload = json.loads(raw)
    limits = payload.get("rate_limits") or {}
    clean = {}
    for key in ("five_hour", "seven_day"):
        entry = limits.get(key)
        if not isinstance(entry, dict):
            continue
        percentage, reset = entry.get("used_percentage"), entry.get("resets_at")
        if all(type(v) in (int, float) and math.isfinite(v) for v in (percentage, reset)) and percentage >= 0 and reset > 0:
            clean[key] = {"used_percentage": percentage, "resets_at": reset}
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = directory / "claude.json"
    # Re-running the statusline can replay the same cached metrics. Do not make
    # identical data look newly observed. This deliberately errs toward stale.
    try:
        old = json.loads(target.read_text())
        if old.get("rate_limits") == clean:
            return clean
    except (OSError, ValueError):
        pass
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".claude-")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump({"observed_at": time.time(), "rate_limits": clean}, handle, allow_nan=False)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return clean


def main():
    raw = sys.stdin.read()
    directory = Path.home() / "Library/Application Support/UsageBar"
    try:
        limits = collect(raw, directory)
    except (OSError, ValueError, TypeError):
        limits = {}
    previous = directory / "previous-statusline.json"
    if previous.exists():
        try:
            command = json.loads(previous.read_text()).get("command")
            if command:
                subprocess.run(command, input=raw, text=True, shell=True, timeout=8, check=False)
                return
        except (OSError, ValueError, subprocess.TimeoutExpired):
            pass
    values = [f"{'5h' if key == 'five_hour' else '7d'} {entry['used_percentage']:.0f}%" for key, entry in limits.items()]
    print("Claude · " + " · ".join(values) if values else "Claude · aguardando limites")


if __name__ == "__main__":
    main()
