#!/bin/sh
# Post-upgrade verification for the NAS520. Read-only: changes nothing.
#
# Run as root after every release upgrade (or after any reboot):
#   sh post-upgrade-check.sh
#
# Expected: no failed units, eth0 with a DHCP address, both watchdogs active,
# mcu_wdt=1, fan PWM around 0x5dc, zram swap present, NAND still 10 MTD parts.
echo "== release"
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
echo "== kernel"
uname -r
echo "== cmdline"
cat /proc/cmdline
echo "== network"
ip -4 addr show eth0 | grep 'inet '
ip route | head -2
echo "== dns/http"
getent hosts deb.debian.org | head -1
curl -sI -m 8 http://deb.debian.org/debian/ | head -1
echo "== failed units"
systemctl --failed --no-legend || true
echo "== services"
for u in cockpit.socket smbd watchdog nas-watchdog; do
    printf '%-18s %s\n' "$u" "$(systemctl is-active $u 2>/dev/null)"
done
echo "== mtd"
grep -c . /proc/mtd
echo "== mcu watchdog"
cat /proc/mcu_wdt
echo "== zram"
tail -1 /proc/swaps
echo "== temperature / fan"
i2cget -y 0 0x0a 0x07 2>/dev/null
mmiotool -r 0x9045802C 2>/dev/null
echo "== disk"
df -h / | tail -1
echo "== apt"
apt-get check 2>&1 | tail -2
echo "== bsp/kernel packages"
dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null \
  | grep -E 'linux-bsp-nas5xx|linux-image-6\.6|debian-archive-keyring' || true
echo "== ssh access rules"
grep -E '^AllowGroups' /etc/ssh/sshd_config || echo "AllowGroups: (default)"
echo CHECK_DONE
