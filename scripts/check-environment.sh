#!/usr/bin/env bash
# Read-only checks before the first exercise. Ports must still be free.
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
  echo 'Run this script in Ubuntu, not in the macOS or Windows terminal.' >&2
  exit 1
fi

LAB_ERRORS=0
lab_ok() { printf 'OK: %s\n' "$1"; }
lab_fail() { printf 'FAIL: %s\n' "$1" >&2; LAB_ERRORS=$((LAB_ERRORS + 1)); }

cat /etc/os-release
uname -m
uname -r
if [[ $(ps -p 1 -o comm=) == systemd ]]; then
  lab_ok 'PID 1 is systemd'
else
  lab_fail 'PID 1 must be systemd; use the full Ubuntu VM'
fi
if [[ $(stat -fc %T /sys/fs/cgroup) == cgroup2fs ]]; then
  lab_ok 'cgroups v2'
else
  lab_fail 'Expected cgroups v2'
fi
for lab_command in systemctl systemd-run systemd-analyze journalctl python3 curl nc ss findmnt git; do
  if command -v "$lab_command" >/dev/null; then
    lab_ok "$lab_command is available"
  else
    lab_fail "Missing command: $lab_command"
  fi
done
if command -v systemctl >/dev/null; then
  systemctl --version | head -n 1
fi
if [[ -d /sys/firmware/efi ]]; then
  lab_ok 'UEFI boot detected'
else
  echo 'INFO: no EFI directory; check VM firmware settings. Container tests cannot validate firmware.'
fi
if getent passwd course-web >/dev/null; then
  lab_ok 'course-web account exists'
else
  lab_fail 'Run scripts/prepare.sh first'
fi
for lab_file in /srv/lk3/index.html /opt/lk3/lk3-memory.py; do
  if [[ -r $lab_file ]]; then
    lab_ok "$lab_file is readable"
  else
    lab_fail "Missing or unreadable: $lab_file"
  fi
done
if command -v ss >/dev/null; then
  LAB_LISTENERS=$(ss -H -ltn '( sport = :8080 or sport = :8081 )')
  if [[ -z $LAB_LISTENERS ]]; then
    lab_ok 'Ports 8080 and 8081 are free'
  else
    printf '%s\n' "$LAB_LISTENERS"
    lab_fail 'Ports are occupied. Identify the owner or restore the prepared snapshot.'
  fi
fi
if [[ -e /etc/systemd/system/course-web.service ]] || [[ -d /etc/systemd/system/course-web.service.d ]]; then
  lab_fail 'course-web is already installed; restore the initial lab state before the first exercise'
fi
if (( LAB_ERRORS > 0 )); then
  printf 'Checks failed: %s\n' "$LAB_ERRORS" >&2
  exit 1
fi
echo 'Ready for exercise 1. Keep this state as a powered-off VM snapshot.'
