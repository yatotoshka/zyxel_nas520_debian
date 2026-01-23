====================================================================
ZYXEL NAS520 - DEBIAN 11 (BULLSEYE) + OPENMEDIAVAULT 6 (SHAITAN)
====================================================================
Description: Modern OS with Kernel 6.6.x optimized for Zyxel NAS520. 
The system boots from an SD Card, ensuring silence (HDD spindown) 
and rock-solid stability (Real-Time Watchdog).

## 📥 Download Links
You can download the system image and kernel from the link below:

👉 https://mega.nz/folder/zwIUiaAZ#dWQR1B-A20QjlfZXmADpuQ

### Contents:
* `NAS520_System_Image.img.gz` - OS for SD Card
* `uImage` - Kernel for NAND flash
* `README.txt` - Step-by-step installation guide

update : 
Here is the professional English version for your GitHub README.md. It highlights the key optimizations and the shift from OMV to a lightweight Cockpit setup.

🚀 Applied Optimizations & System Enhancements (Changelog)
This system image has been specifically tuned for the Zyxel NAS520 hardware, focusing on maximum reliability, RAID self-healing, and minimal CPU overhead.

1. System Architecture: Cockpit vs. OMV
Lightweight Management (Cockpit): This build features Cockpit as the primary management interface. Unlike OpenMediaVault (OMV), Cockpit is a "demand-based" service that consumes virtually no resources when not in use.

Zero OMV Overhead: By removing OMV, we eliminated dozens of background PHP/Python processes and heavy database triggers. This results in a much more responsive Debian environment, leaving more CPU cycles for actual file transfers and RAID management.

Native Configuration: Cockpit interacts directly with standard Debian configuration files. There are no proprietary database layers, meaning changes made via the Web UI are identical to those made via the CLI.

2. Intelligent RAID Self-Healing
Hybrid Rebuild Script: Integrated a custom script /usr/local/bin/raid-auto-rebuild.sh that intelligently handles array failures. It first attempts a fast re-add (to preserve data consistency); if the event count mismatch is too high, it automatically triggers a full add to force recovery.

Udev Integration: Implemented a custom rule 99-raid-rebuild.rules that monitors SATA ports in real-time. The system automatically initiates a repair the moment a disk is "re-inserted" (useful for intermittent power drops or bay connection issues).

UUID Verification: To prevent data corruption, the script verifies the Array UUID before attempting any recovery, ensuring it only acts on the correct member disks.

3. CPU-Friendly Backup Strategy
Optimized .img Generation: The system partition backup is performed as a raw binary dump using an optimized block size (bs=1M) and the conv=sparse flag.

No In-Transit Compression: To prevent "choking" the dual-core ARM CPU, compression is omitted during the backup process. This ensures the NAS remains functional and responsive while the system image is being created.

4. Monitoring & Stability
Read-Write Enforcement: The automation script includes a fail-safe to force the array back into --readwrite mode, resolving the common issue where Debian locks the RAID as "read-only" after a disk timeout.

Action Logging: All automated repair attempts are logged to the system journal (journalctl -t raid-auto), providing a clear audit trail of disk health and recovery events.

1. DEFAULT CREDENTIALS
--------------------------------------------------------------------
System (SSH/Console):
  User: admin
  Pass: lol

Web GUI (OMV):
  URL: http://[nas_ip_address]
  User: admin
  Pass: lol

2. SD CARD PREPARATION
--------------------------------------------------------------------
1. Micro SD card required (min. 16GB, A1/A2 or Endurance class recommended).
2. Flash the .img.gz image using BalenaEtcher or Rufus.
3. After first boot, it is recommended to run: 
   sudo tune2fs -U random /dev/sda1

3. BAREBOX CONFIGURATION (UART 115200 baud)
--------------------------------------------------------------------
You MUST flash the kernel to NAND and set the boot parameters.

A. Flash the Kernel (via TFTP):
   eth0.serverip=192.168.0.XXX (Your PC IP)
   eth0.ipaddr=192.168.0.YYY   (NAS IP)
   tftp uImage /dev/nand0.kernel1.bb

B. Edit /env/config:
   Run command: edit /env/config
   Set/update the following lines:

   kernel_loc=nand
   kernelimage=uImage
   rootfs_loc=sata
   
   bootargs="console=ttyS0,115200 root=/dev/sda1 rootwait rw init=/lib/systemd/systemd systemd.unit=multi-user.target cgroup_enable=memory swapaccount=1"

C. CRITICAL: Watchdog Keep-Alive (Barebox level):
   To prevent the hardware watchdog from rebooting the NAS during 
   boot, ensure these commands are at the end of your /env/config:

   mw 0x904700D0 0x010000A0
   mw 0x904700D0 0x010000A0

D. Save and Boot:
   Press Ctrl+D, then run:
   saveenv
   boot

4. KEY FEATURES & OPTIMIZATIONS
--------------------------------------------------------------------
- WATCHDOG: Active nas-watchdog.service (FIFO 99 priority). 
  DO NOT DISABLE - this script maintains the device power supply.
- HDD SPINDOWN: OS on SD allows HDDs to sleep. Configure APM (127) 
  and Spindown time (20 min) in the OMV Web GUI (Storage -> Disks).
- FLASH MEMORY: Logs are stored in RAM to protect the SD card from wear.
- RAID 1: Configure your mirror via Web GUI in the Storage section.

5. TROUBLESHOOTING
--------------------------------------------------------------------
- If the system hangs on "Helper for ifupdown", wait 3 minutes for 
  the timeout, then log in and run: omv-firstaid
- To force boot from HDD instead of SD card, change in Barebox:
  root=/dev/sda1 to root=/dev/sdb1 (depending on your drive layout).

====================================================================
Project Author: Baxi
====================================================================
