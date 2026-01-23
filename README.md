====================================================================
ZYXEL NAS520 - DEBIAN 11 (BULLSEYE) + COCKPIT
====================================================================
Author: Baxi
Version: 2024-Update
OS: Debian 11 Bullseye (Kernel 6.6.x)
Target Device: Zyxel NAS520 (Dual-Core ARM)
====================================================================

1. DESCRIPTION
--------------------------------------------------------------------
This is a modern, optimized OS image for the Zyxel NAS520. 
The system boots from a MicroSD card, allowing your HDDs to spin 
down completely for silence and energy savings. It features 
a real-time watchdog to ensure rock-solid stability.

2. DOWNLOAD LINKS
--------------------------------------------------------------------
Access the system image and kernel here:
👉 https://mega.nz/folder/zwIUiaAZ#dWQR1B-A20QjlfZXmADpuQ

Contents:
- NAS520_System_Image.img.gz : OS for MicroSD Card
- uImage                   : Kernel for NAND flash
- README.txt               : This installation guide

3. KEY OPTIMIZATIONS (WHAT'S NEW)
--------------------------------------------------------------------
* COCKPIT OVER OMV:
  Replaced OpenMediaVault with Cockpit. Cockpit is a "demand-based" 
  UI that consumes near-zero CPU/RAM when not in use. No heavy 
  background PHP/Python processes.

* INTELLIGENT RAID SELF-HEALING:
  - Custom script: /usr/local/bin/raid-auto-rebuild.sh handles
    array failures automatically.
  - Udev Rules: 99-raid-rebuild.rules monitors SATA ports and 
    triggers auto-repair immediately after a disk is re-inserted.
  - UUID Verification: Prevents accidental data corruption.

* CPU-FRIENDLY BACKUP:
  System backups are performed as raw binary dumps (bs=1M) with 
  'conv=sparse' to save space without choking the ARM CPU.

* STABILITY & MONITORING:
  - Read-Write Enforcement: Prevents the array from staying in 
    "read-only" mode after a disk timeout.
  - Action Logging: View logs via 'journalctl -t raid-auto'.

4. DEFAULT CREDENTIALS
--------------------------------------------------------------------
SYSTEM (SSH/Console):
  User: admin
  Pass: lol

WEB GUI (Cockpit):
  URL: https://[nas_ip_address]:9090
  User: admin
  Pass: lol

5. SD CARD PREPARATION
--------------------------------------------------------------------
1. Use a MicroSD card (min. 16GB, A1/A2 or Endurance recommended).
2. Flash the .img.gz using BalenaEtcher or Rufus.
3. After first boot, run: sudo tune2fs -U random /dev/sda1

6. BAREBOX CONFIGURATION (UART 115200 baud)
--------------------------------------------------------------------
You MUST flash the kernel to NAND and set boot parameters.

A. Flash the Kernel (via TFTP):
   eth0.serverip=19
