#!/bin/sh
# NAS520 post-install tweaks for the Debian 11 image.
#
# Safe to run more than once. Run as root:
#
#     sudo ./postinstall.sh
#
# What it does:
#   1. stops nas_keep_alive.sh from fighting watchdog.service for /dev/watchdog
#      (the SoC watchdog is already fed by /sbin/watchdog; the script keeps
#      petting the external MCU through 0x904700D0)
#   2. masks fancontrol.service, which can never start without /etc/fancontrol
#   3. prints the state of both watchdogs, the fan and the CPU temperature
#
# Nothing here is required for the system to boot; these are cosmetic and
# reliability fixes. Undo by restoring the *.orig backup and running
# "systemctl unmask fancontrol".

set -u

KEEP=/usr/local/bin/nas_keep_alive.sh
changed=0

if [ "$(id -u)" != "0" ]; then
    echo "error: run this script as root (sudo $0)" >&2
    exit 1
fi

echo "== 1. watchdog keep-alive =="
if [ -f "$KEEP" ] && grep -q '^[[:space:]]*echo \. > /dev/watchdog' "$KEEP"; then
    [ -f "$KEEP.orig" ] || cp -a "$KEEP" "$KEEP.orig"
    sed -i 's|^\([[:space:]]*\)echo \. > /dev/watchdog.*|\1# /dev/watchdog (SoC WDT) is fed by watchdog.service;|' "$KEEP"
    echo "   patched $KEEP (backup: $KEEP.orig)"
    changed=1
else
    echo "   nothing to do (already patched or file missing)"
fi

echo "== 2. fancontrol =="
if [ -e /etc/fancontrol ]; then
    echo "   /etc/fancontrol exists, leaving fancontrol.service alone"
else
    if systemctl is-enabled --quiet fancontrol.service 2>/dev/null; then
        systemctl disable --now fancontrol.service >/dev/null 2>&1 || true
        changed=1
    fi
    systemctl mask fancontrol.service >/dev/null 2>&1 || true
    echo "   masked fancontrol.service (no /etc/fancontrol; fan is driven by the SoC PWM)"
fi

if [ "$changed" = "1" ] && systemctl is-active --quiet nas-watchdog.service 2>/dev/null; then
    systemctl restart nas-watchdog.service >/dev/null 2>&1 || true
    echo "== restarted nas-watchdog.service =="
fi

echo "== 3. state =="
printf '   watchdog devices : '
ls /dev/watchdog* 2>/dev/null | tr '\n' ' '
echo
if [ -r /proc/mcu_wdt ]; then
    printf '   /proc/mcu_wdt    : %s (1 = MCU watchdog stopped)\n' "$(cat /proc/mcu_wdt)"
fi
for u in watchdog nas-watchdog fancontrol; do
    state=$(systemctl is-active "$u.service" 2>/dev/null || true)
    printf '   %-20s: %s\n' "$u.service" "${state:-unknown}"
done
if command -v i2cget >/dev/null 2>&1; then
    t=$(i2cget -y 0 0x0a 0x07 2>/dev/null || true)
    [ -n "$t" ] && printf '   CPU temperature  : %d C\n' "$((t))"
fi
if command -v mmiotool >/dev/null 2>&1; then
    printf '   fan PWM 0x9045802C: %s\n' "$(mmiotool -r 0x9045802C 2>/dev/null | sed 's/.*: //')"
fi
echo
echo "done."
