#!/bin/sh
# NAS520 post-install fixes for the Debian 11 image.
#
# Version: 1.1.0
#
# Changelog:
#   1.1.0  named steps, --check (dry run), version, applied-fixes log
#   1.0.0  first release: duplicate watchdog feeder, fancontrol mask, state
#
# Usage:
#     sudo ./postinstall.sh            apply fixes (safe to re-run)
#     sudo ./postinstall.sh --check    show what would change, change nothing
#
# What it fixes:
#   1. nas_keep_alive.sh fights watchdog.service for /dev/watchdog on every
#      loop, which spams "Device or resource busy" in the journal. The MCU is
#      still petted through 0x904700D0, so only the duplicate line is removed.
#   2. fancontrol.service is enabled but can never start without
#      /etc/fancontrol, so it is disabled and masked.
#
# Undo:
#   restore /usr/local/bin/nas_keep_alive.sh.orig and run
#   "sudo systemctl unmask fancontrol".

set -u

VERSION=1.1.0
STATE_DIR=/var/lib/nas520-postinstall
STATE_FILE=$STATE_DIR/applied.log
KEEP=/usr/local/bin/nas_keep_alive.sh
FANUNIT=fancontrol.service

MODE=apply
case "${1:-}" in
    --check|--dry-run|-n)
        MODE=check
        ;;
    --help|-h)
        echo "usage: sudo $0 [--check|--dry-run]"
        echo "  no option   apply fixes (safe to re-run)"
        echo "  --check     show what would change and exit"
        exit 0
        ;;
    '')
        ;;
    *)
        echo "postinstall: unknown option '$1' (try --help)" >&2
        exit 2
        ;;
esac

say()     { printf '%s\n' "$*"; }
step()    { printf '== %s ==\n' "$*"; }
act()     { if [ "$MODE" = check ]; then printf '   would %s\n' "$*"; else printf '   %s\n' "$*"; fi; }
already() { printf '   already done: %s\n' "$*"; }

record() {
    [ "$MODE" = check ] && return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    printf '%s\t%s\t%s\n' "$1" "v$VERSION" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >>"$STATE_FILE"
}

if [ "$MODE" = apply ] && [ "$(id -u)" != 0 ]; then
    echo "error: run as root (sudo $0)" >&2
    exit 1
fi

say "nas520 postinstall v$VERSION ($MODE mode)"

step "1/2 watchdog keep-alive"
if [ ! -f "$KEEP" ]; then
    say "   $KEEP not found, skipping"
elif grep -q '^[[:space:]]*echo \. > /dev/watchdog' "$KEEP"; then
    act "comment out 'echo . > /dev/watchdog' in $KEEP"
    if [ "$MODE" = apply ]; then
        [ -f "$KEEP.orig" ] || cp -a "$KEEP" "$KEEP.orig"
        sed -i 's|^\([[:space:]]*\)echo \. > /dev/watchdog.*|\1# /dev/watchdog (SoC WDT) is fed by watchdog.service;|' "$KEEP"
        record "nas_keep_alive.sh: drop duplicate /dev/watchdog feeder"
        systemctl restart nas-watchdog.service >/dev/null 2>&1 || true
        say "   restarted nas-watchdog.service"
    fi
else
    already "watchdog feeder patched"
fi

step "2/2 fancontrol"
if [ -e /etc/fancontrol ]; then
    say "   /etc/fancontrol exists, leaving $FANUNIT alone"
elif [ "$(systemctl is-enabled "$FANUNIT" 2>/dev/null || true)" = masked ]; then
    already "$FANUNIT masked"
else
    act "disable and mask $FANUNIT (no /etc/fancontrol; fan runs from the SoC PWM)"
    if [ "$MODE" = apply ]; then
        systemctl disable --now "$FANUNIT" >/dev/null 2>&1 || true
        systemctl mask "$FANUNIT" >/dev/null 2>&1 || true
        record "$FANUNIT: masked (no /etc/fancontrol)"
    fi
fi

step "state"
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
    if [ -n "$t" ]; then
        printf '   CPU temperature  : %d C\n' "$((t))"
    fi
fi
if command -v mmiotool >/dev/null 2>&1; then
    pwm=$(mmiotool -r 0x9045802C 2>/dev/null | sed 's/.*: //')
    if [ -n "$pwm" ]; then
        printf '   fan PWM 0x9045802C: %s\n' "$pwm"
    fi
fi

if [ -s "$STATE_FILE" ]; then
    echo
    say "applied by this script:"
    cat "$STATE_FILE"
fi

echo
if [ "$MODE" = check ]; then
    say "check mode: nothing was changed."
else
    say "done."
fi
