#!/bin/sh
# Clean up a stock (Baxi) bullseye image before a Debian release upgrade.
#
# Removes the OpenMediaVault/PHP/Salt/nginx leftovers and the old 3.2 kernel
# packages that came with the original firmware image. Keeps the BSP packages
# (linux-bsp-nas5xx*) and the Debian 6.6 kernel, which the NAS boots from NAND.
#
# Run as root on the NAS. Verified on a live NAS520 (bullseye -> bookworm).
set -eu

echo "== 1. dead repositories"
rm -fv /etc/apt/sources.list.d/openmediavault.list \
       /etc/apt/sources.list.d/openmediavault-os-security.list \
       /etc/apt/sources.list.d/openmediavault-kernel-backports.list \
       /etc/apt/sources.list.d/backports.list \
       /etc/apt/preferences.d/openmediavault-kernel-backports.pref

echo "== 2. purge unused packages"
DEBIAN_FRONTEND=noninteractive apt-get -y purge \
  openmediavault-wol salt-minion salt-common \
  php7.4-bcmath php7.4-cgi php7.4-cli php7.4-common php7.4-fpm php7.4-json \
  php7.4-mbstring php7.4-opcache php7.4-readline php7.4-xml \
  php-cgi php-cli php-common php-fpm php-pam php-yaml \
  nginx nginx-common nginx-core libnginx-mod-http-geoip \
  libnginx-mod-http-image-filter libnginx-mod-http-xslt-filter \
  libnginx-mod-mail libnginx-mod-stream libnginx-mod-stream-geoip \
  wsdd \
  linux-image-armhf linux-image-3.2.0-6-nas5xx \
  linux-headers-armhf linux-headers-3.2.0-6-nas5xx \
  linux-headers-3.2.0-6-common linux-kbuild-3.2

echo "== 3. autoremove"
DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge
apt-get clean

echo "== 4. what is left"
dpkg-query -W -f='${Package} ${Version}\n' \
  | grep -E 'openmediavault|salt-|nginx|^php|wsdd|linux-image-3\.2|linux-headers-3\.2' \
  || echo "none"

echo "== 5. BSP and current kernel still here"
dpkg-query -W -f='${Package} ${Version}\n' \
  | grep -E 'linux-bsp-nas5xx|linux-image-6\.6' || true

echo "== 6. sources"
grep -rvE '^#|^$' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true
echo DONE
