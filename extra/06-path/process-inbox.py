#!/usr/bin/env python3
"""Process one fully published request file, then clear the path condition."""

from pathlib import Path

inbox = Path("/var/lib/lk3-extra-inbox")
request = inbox / "request.txt"
message = request.read_text()
(inbox / "processed.txt").write_text("Обработано: " + message)
request.unlink()
print("Processed request.txt -> processed.txt; input removed", flush=True)
