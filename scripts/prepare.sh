#!/usr/bin/env bash
# Prepare assets only. The student installs course-web.service during the seminar.
set -euo pipefail

if [[ $(uname -s) != Linux ]] || [[ $(ps -p 1 -o comm=) != systemd ]]; then
  echo 'Run this script inside the Ubuntu lab VM with systemd as PID 1.' >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo 'Run: sudo bash scripts/prepare.sh' >&2
  exit 1
fi

LAB_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -e /etc/systemd/system/course-web.service ]] || [[ -d /etc/systemd/system/course-web.service.d ]]; then
  echo 'course-web is already installed. Restore the prepared snapshot or follow the reset section in README.md.' >&2
  exit 1
fi

if getent passwd course-web >/dev/null; then
  LAB_UID=$(id -u course-web)
  LAB_SHELL=$(getent passwd course-web | cut -d: -f7)
  if (( LAB_UID >= 1000 )) || [[ $LAB_SHELL != /usr/sbin/nologin ]]; then
    echo 'An unexpected course-web account already exists. Use a fresh lab VM.' >&2
    exit 1
  fi
else
  useradd --system --user-group --home-dir /nonexistent --shell /usr/sbin/nologin course-web
fi

install -d -m 0755 /srv/lk3 /opt/lk3
install -m 0644 "$LAB_ROOT/examples/01-service/index.html" /srv/lk3/index.html
install -m 0644 "$LAB_ROOT/examples/04-resources/lk3-memory.py" /opt/lk3/lk3-memory.py
install -m 0644 "$LAB_ROOT/examples/02-port-conflict/lk3-port-holder.service" /etc/systemd/system/
systemctl daemon-reload

systemd-analyze verify \
  "$LAB_ROOT/examples/01-service/course-web.service" \
  "$LAB_ROOT/examples/02-port-conflict/lk3-port-holder.service" \
  "$LAB_ROOT/examples/06-socket/lk3-echo.socket" \
  "$LAB_ROOT/examples/06-socket/lk3-echo@.service" \
  "$LAB_ROOT/examples/08-timer/lk3-tick.service" \
  "$LAB_ROOT/examples/08-timer/lk3-tick.timer"

echo 'Prepared: course-web account, /srv/lk3, /opt/lk3 and the inactive port-holder unit.'
echo 'Next: bash scripts/check-environment.sh'
