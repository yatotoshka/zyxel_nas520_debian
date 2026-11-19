#!/bin/sh
# Remove the last OpenMediaVault leftovers that survived the package purge:
# monit checks, cron jobs, SysV scripts, generated configs and folder2ram.
# Run as root on the NAS after the bullseye cleanup.
set -eu

echo "== folder2ram (unowned OMV helper)"
systemctl disable --now folder2ram 2>/dev/null || true
rm -f /etc/systemd/system/folder2ram.service /sbin/folder2ram
rm -rf /etc/folder2ram

echo "== monit and cron-apt"
DEBIAN_FRONTEND=noninteractive apt-get -y purge monit cron-apt
rm -rf /etc/monit

echo "== OMV files"
rm -fv /etc/sysctl.d/99-openmediavault-mdadm.conf \
       /etc/modules-load.d/openmediavault-watchdog.conf \
       /etc/systemd/system.conf.d/openmediavault-watchdog.conf \
       /etc/cron-apt/action.d/5-openmediavault-security \
       /etc/cron-apt/mailmsg.d/5-openmediavault-security \
       /etc/cron-apt/config.d/5-openmediavault-security \
       /etc/cron.hourly/openmediavault-flushmailq \
       /etc/cron.d/openmediavault-powermngmt \
       /etc/cron.d/openmediavault-userdefined \
       /etc/cron.daily/openmediavault-samba-recycle \
       /usr/local/bin/dru-omv-patch \
       /etc/systemd/system/networking.servic.service
rm -fv /etc/init.d/openmediavault /etc/init.d/openmediavault-engined \
       /etc/init.d/openmediavault-beep
rm -fv /etc/rc*.d/K*openmediavault-engined

echo "== OMV directories"
rm -rf /etc/openmediavault /usr/share/openmediavault \
       /var/lib/openmediavault /var/www/openmediavault
rmdir /var/www 2>/dev/null || true

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "== verify: no OMV files left"
find /etc /usr/local /var/lib /var/www -maxdepth 3 -iname '*openmediavault*' 2>/dev/null | head
echo "== failed units"
systemctl --failed --no-legend || true
echo DONE
