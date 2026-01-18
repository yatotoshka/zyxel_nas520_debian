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
