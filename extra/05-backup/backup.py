#!/usr/bin/env python3
"""Archive only the extra lab's sample data; each run creates a new archive."""

from datetime import datetime, timezone
from pathlib import Path
import tarfile

source = Path("/srv/lk3-extra-backup/source")
destination = Path("/var/lib/lk3-extra-backup")
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
archive = destination / f"backup-{stamp}.tar.gz"
with tarfile.open(archive, "x:gz") as output:
    output.add(source, arcname="source")
print(f"Created {archive}", flush=True)
