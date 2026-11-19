# Zyxel NAS520 — Debian 11 on microSD, kernel in NAND

Debian 11 (Bullseye) on a Zyxel NAS520 (Mindspeed C2000, dual Cortex-A9).
The system lives on a microSD card connected over USB3; the kernel is flashed
into NAND and started by the stock barebox bootloader.

This repository contains the **hardware-verified installation procedure** for
the community image: NAND backup first, then the kernel in `kernel2`, then the
SD card as root filesystem.

> The full, detailed guide is in **[INSTALL_GUIDE.md](INSTALL_GUIDE.md)**
> (Russian: flash layout, dumps, TFTP, barebox env, watchdog, fan, rollback,
> troubleshooting).

---

## Status

Everything below was tested on a real NAS520:

| Item | State |
|------|-------|
| Full SPI NOR + NAND dump, md5 verified | ✅ done |
| Kernel flashed to `kernel2` (mtd6), read back and compared | ✅ done |
| Debian boots from microSD (`root=/dev/sda`) | ✅ done |
| Partition-less ext4 grown to the whole card (2.6 → 14.8 GiB) | ✅ done |
| barebox env edited (`rootfs_loc=sata`, `root=/dev/sda`, `rootwait`) | ✅ done |
| Unattended boot after `reset` | ✅ done |
| Both watchdogs, fan and temperature | ✅ checked |

`uloader`, `barebox`, `config`, `kernel1`, `rootfs1`, `rootfs2` and `reserved`
are **not** modified. Only `kernel2` and the `env` partition differ from stock.

---

## Hardware facts

| | |
|---|---|
| SoC | Mindspeed C2000 (`fsl,ls1024a`), 2× Cortex-A9 |
| RAM | 1 GiB |
| SPI NOR | 1 MiB: `uloader` 256K, `barebox` 512K, `env` 256K |
| NAND | 256 MiB, 2K pages, 128K erase blocks |
| microSD | via USB3 (dwc3) → visible as **`/dev/sda`** |
| LAN | 2 ports behind an AR8328 switch; `eth0` = PHY4, `eth1` = PHY6 |
| Kernel | uImage, uncompressed, DTB built in, load/entry `0x0f008000` |
| initrd | not needed (ext4, USB, xHCI, dwc3, sd are built in) |

The image is **ext4 on the whole card**, with no partition table — that is why
`root=/dev/sda` and not `/dev/sda1` or `/dev/mmcblk0p1`.

---

## Quick start

1. **Back up the flash** before writing anything — see
   [INSTALL_GUIDE.md §4](INSTALL_GUIDE.md#4-обязательно-резервная-копия-флеша).
   SPI with `dd`, NAND with `nanddump --bb=dumpbad`. Keep the dumps off the NAS.
2. **Write the image to the microSD** (`dd`/BalenaEtcher/Rufus) and grow the
   filesystem: `e2fsck -f /dev/sdX && resize2fs /dev/sdX`.
3. **Flash the kernel to NAND** — either from barebox
   (`update -t kernel2 -d nand -m tftp -f uImage -c`) or from Linux
   (`flash_erase /dev/mtd6 0 0 && nandwrite -a -p /dev/mtd6 uImage`).
4. **Test once by hand** in barebox, before touching the saved settings:

   ```text
   bootargs="console=ttyS0,115200n8 init=/etc/preinit root=/dev/sda rootwait rw rootfstype=ext4"
   bootm /dev/nand0.kernel2.bb
   ```

5. **Make it permanent** — edit `/env/config` and `/env/bin/boot` with `sedit`,
   then `saveenv`, `reset`:

   ```text
   /env/config:      rootfs_loc=sata        (was nand)
                     rootfs_type=ext4       (was ubifs)
                     eth0.serverip=<your TFTP/HTTP host>
   /env/bin/boot:    root=/dev/sda2 → /dev/sda ... rootwait
   ```

Expected kernel command line after step 5:

```text
console=ttyS0,115200n8 init=/etc/preinit  ip=dhcp root=/dev/sda \
  rootfstype=ext4 rootwait rw noinitrd mtdparts=… usb3_internal_clk=yes
```

---

## Default credentials

| | |
|---|---|
| Console / SSH | `admin` / `lol` |
| Cockpit | `https://<nas-ip>:9090` — `admin` / `lol` |

Change them after installation.

---

## What the image provides

From the upstream project:

- **Cockpit instead of OpenMediaVault** — on-demand UI, near-zero idle load.
- **RAID self-healing** — `/usr/local/bin/raid-auto-rebuild.sh`,
  udev rule `99-raid-rebuild.rules`, logging via `journalctl -t raid-auto`.
- **CPU-friendly backups** — raw dumps with `conv=sparse`.
- **Stability** — read-write enforcement after disk timeouts, action logging.

Optional post-install cleanup (not required to boot):

```bash
sudo sh tools/postinstall.sh
```

It stops the duplicate watchdog feeder (removes `Device or resource busy`
spam), masks the never-starting `fancontrol.service`, and prints watchdog,
temperature and fan state. Safe to re-run.

---

## Repository layout

| File | Purpose |
|------|---------|
| `README.md` | this file |
| `INSTALL_GUIDE.md` | complete Russian guide: dumps, flashing, env, rollback |
| `tools/postinstall.sh` | optional post-install tweaks, idempotent |
| `tools/envfs.py` | optional extract/build of the barebox `env` image |
| `.gitignore` | images and dumps are not committed |

---

## Notes for maintainers

- `root=/dev/sda` (whole card, no partition table), `rootwait` is required.
- `init=/etc/preinit` must stay: it runs `zy-nand-get` / `zy-hw-init` and then
  `exec /sbin/init`.
- `pcie_gen1_only=yes` and the `mac_addr=…` line in `bootargs` were needed by
  the vendor 3.2 kernel only; kernel 6.6 boots without them (they just add
  noise to the command line).
- Two independent watchdogs: the SoC WDT (15 s) and an external MCU watchdog
  (~60 s) petted through `0x904700D0`. See INSTALL_GUIDE §9.4.
- Kernel panic does not reboot by itself (`PANIC_TIMEOUT=0`); the MCU watchdog
  power-cycles the board after ~60 s back into barebox. Over serial you can
  force a reboot with `BREAK` + `b` (SysRq).

---

## Credits

The system image, its scripts and the original notes are the work of **Baxi**:

<https://mega.nz/folder/zwIUiaAZ#dWQR1B-A20QjlfZXmADpuQ>

This repository adds a verified installation procedure and small tooling for
it. The image itself is not modified here.

## Licensing

No license was published with the original image or scripts, so they remain
the property of their author and are only referenced, not redistributed. The
documentation and helper scripts in this repository are provided as-is, without
any warranty — flashing a bootloader-adjacent device is done at your own risk.
