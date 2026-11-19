#!/bin/sh
# Upgrade Debian on the NAS520 to the release named in $1 (bookworm or trixie).
#
# Unattended: keeps existing conffiles, logs everything to
# /root/upgrade-<release>.log and prints UPGRADE_OK on success.
# Safe to run under nohup over SSH: the upgrade survives the connection.
#
# Usage (on the NAS, as root):
#   sh dist-upgrade.sh bookworm
#   sh dist-upgrade.sh trixie
#
# The caller is responsible for pointing /etc/apt/sources.list at the target
# release before running this script.
set -eu
REL=${1:?usage: dist-upgrade.sh bookworm|trixie}
LOG=/root/upgrade-$REL.log
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_MODE=a
exec >>"$LOG" 2>&1
echo "=== $(date -u '+%F %T') upgrade to $REL: start"
echo "--- sources:"
grep -vE '^#|^$' /etc/apt/sources.list
echo "--- apt update"
apt-get update
echo "--- minimal upgrade (--without-new-pkgs)"
apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        -o Acquire::Retries=5 upgrade --without-new-pkgs
echo "--- full upgrade"
apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        -o Acquire::Retries=5 full-upgrade
echo "--- autoremove"
apt-get -y autoremove --purge
apt-get clean
echo "=== $(date -u '+%F %T') upgrade to $REL: done"
echo UPGRADE_OK
