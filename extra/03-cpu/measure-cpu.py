#!/usr/bin/env python3
"""Measure a unit's cgroup CPU time over five seconds, without extra packages."""

from pathlib import Path
import subprocess
import sys
import time

unit = sys.argv[1] if len(sys.argv) == 2 else "lk3-extra-cpu.service"
cgroup = subprocess.check_output(
    ["systemctl", "show", unit, "--property=ControlGroup", "--value"], text=True
).strip()
if not cgroup or cgroup == "/":
    raise SystemExit("Нет cgroup службы. Сначала запустите опыт с CPU.")
stats = Path("/sys/fs/cgroup") / cgroup.lstrip("/") / "cpu.stat"


def cpu_microseconds():
    fields = dict(line.split() for line in stats.read_text().splitlines())
    return int(fields["usage_usec"])


try:
    start_cpu = cpu_microseconds()
    start_wall = time.monotonic()
    time.sleep(5)
    end_cpu = cpu_microseconds()
    elapsed = time.monotonic() - start_wall
except FileNotFoundError:
    raise SystemExit("Служба уже завершилась. Повторите запуск опыта с CPU.")

percent = (end_cpu - start_cpu) / (elapsed * 1_000_000) * 100
print(f"CPU за {elapsed:.1f} с: {percent:.1f}% одного логического CPU")
