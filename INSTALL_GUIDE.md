# Zyxel NAS520 — установка Debian 11 (ядро в NAND, система на SD)

> Проверенное на реальном устройстве руководство: что внутри, как снять резервную
> копию, как прошить ядро и как заставить barebox грузить Debian.
>
> Подробная русская версия. Краткий `README.md` — английский, для внешней
> аудитории; расхождения с исходными заметками автора образа перечислены в
> приложении C.

**Устройство:** Zyxel NAS520 (Mindspeed C2000 / `fsl,ls1024a`, 2× Cortex-A9)
**Загрузчик:** barebox 2011.06.0 + uloader 2011.06.0 (SPI NOR)
**Схема:** Debian на MicroSD (USB3), ядро — uImage в NAND
**Консоль:** USB-UART 3.3V, 115200 8N1

---

## 0. Статус проверки

Всё ниже проверено на реальном NAS520 (не «должно работать»):

| Шаг | Статус |
|-----|--------|
| Полный дамп SPI NOR + NAND снят и сверен по md5 | ✅ проверено |
| Сеть в barebox (`eth0`, PHY4) | ✅ проверено |
| `uImage` (ядро + встроенный DTB) распознаётся, CRC совпадает | ✅ проверено |
| Прошивка ядра в `kernel2`, обратное чтение совпало по md5 | ✅ проверено |
| Загрузка Debian с SD (`root=/dev/sda`) | ✅ проверено |
| Расширение ФС на всю карту (2.6 → 14.8 ГиБ) | ✅ проверено |
| Правка `/env/config` и `/env/bin/boot`, `saveenv` | ✅ проверено |
| Автозагрузка Debian без ручных команд (после `reset`) | ✅ проверено, дважды |
| `tools/envfs.py`: собранный образ принимается `loadenv` | ✅ проверено |
| `tools/postinstall.sh` | ✅ проверено на живой системе |
| Обновление bullseye → bookworm → trixie на месте | ✅ проверено (см. `UPGRADE_GUIDE.md`) |
| Watchdog (оба), вентилятор, температура | ✅ проверено (§9.4) |
| Резервное ядро в `kernel1` | ⛔ не делалось (см. приложение E) |

Результат: ядро Debian лежит в NAND (`mtd6`), корень — SD-карта через USB3,
`uloader`/`barebox`/слот 1 не изменены.

---

## 1. Факты о железе (проверено)

| Параметр | Значение |
|----------|----------|
| SoC | Mindspeed C2000, `compatible = "fsl,ls1024a"` |
| RAM | 1 ГБ (по логу загрузки штатной прошивки) |
| SPI NOR | 1 МБ: uloader 256K, barebox 512K, env 256K (стирание 64K) |
| NAND | 256 МБ, страница 2K, блок 128K |
| MicroSD | **через USB3** (dwc3), в Linux виден как **`/dev/sda`** |
| LAN | 2 порта через свитч Atheros AR8328; `eth0` = PHY4, `eth1` = PHY6 |
| Ядро | uImage, ARM, **uncompressed**, load/entry `0x0f008000`, DTB **внутри** образа |
| initrd | **не нужен** (ext4, USB-storage, xHCI, dwc3, sd — всё `=y` в ядре) |

Проверить «своё» железо можно так (Linux, штатная прошивка):

```sh
cat /proc/mtd
cat /proc/cpuinfo
free -m
```

### Образ системы

`nas520_rootfs.img` — это **ext4 на всём диске**, без таблицы разделов:

```
$ file nas520_rootfs.img
Linux rev 1.0 ext4 filesystem data, UUID=5660100c-…, volume name "SD_SYSTEM"
```

Отсюда важное следствие: в Linux карта — `/dev/sda` (не `sda1` и не
`mmcblk0p1`), и в `root=` должно быть `/dev/sda`.

Размер файловой системы в образе — около 2.6 ГиБ, поэтому на карте 16 ГБ после
записи нужно расширить ФС (§5).

---

## 2. Разметка флеш-памяти

### SPI NOR (`/dev/mtd0…2`)

| mtd | Раздел | Смещение | Размер |
|-----|--------|----------|--------|
| 0 | `uloader` | 0x000000 | 256K |
| 1 | `barebox` | 0x040000 | 512K |
| 2 | `env` | 0x0C0000 | 256K |

> `uloader` и `barebox` **не трогаем**. Настройки barebox лежат отдельно, в
> разделе `env` (`/dev/mtd2`).

### NAND (`/dev/mtd3…8`)

| mtd | Раздел | Смещение | Размер | Назначение |
|-----|--------|----------|--------|------------|
| 3 | `config` | 0x0000000 | 10M | конфиг/UBI `ubi_config` |
| 4 | `kernel1` | 0x0A00000 | 10M | ядро слота 1 |
| 5 | `rootfs1` | 0x1400000 | 110M | система слота 1 |
| 6 | `kernel2` | 0x8200000 | 10M | **ядро слота 2 — сюда пишем Debian** |
| 7 | `rootfs2` | 0x8C00000 | 110M | система слота 2 |
| 8 | `reserved` | 0xFA00000 | 6M | резерв |

Слоты A/B:

| Слот | Ядро | Система | Версия ШП | Переменные env |
|------|------|---------|-----------|----------------|
| 1 | mtd4 | mtd5 | V5.21(AASZ.4) | `kernel_mtd_1=4`, `sysimg_mtd_1=5` |
| 2 | mtd6 | mtd7 | V5.21(AASZ.5)C0 | `kernel_mtd_2=6`, `sysimg_mtd_2=7` |

На нашем экземпляре `next_bootfrom=2`, `curr_bootfrom=2`. Слот 1 остаётся
нетронутым — это страховка для отката.

Плохие блоки NAND: `0x0F280000` и `0x0F2A0000` — оба в `reserved`.
**`kernel2` чистый.**

---

## 3. Требования

- MicroSD от 4 ГБ (рекомендуется 16 ГБ, A1/A2 или Endurance)
- USB-UART **3.3V TTL** (5V может убить плату)
- TFTP-сервер на ноутбуке (или HTTP-сервер, если прошивать из Linux)
- LAN-кабель в **порт, который соответствует `eth0`** (см. §9.1)
- Терминал: `picocom`, `minicom`, `screen` или Python + pyserial

---

## 4. Обязательно: резервная копия флеша

Снимается **до** любых записей в NAND. Удобнее всего — из штатной системы
(слот 2), где уже есть `nanddump`, `/dev/mtd*` и рабочие драйверы.

> В самом barebox дамп снять нельзя: `tftp` пишет в файл, а ramfs ограничен
> ~10 МБ (проверено: `tftp` 22 МБ → `Out of memory`, `bootm` 7.6 МБ → тоже
> `Out of memory`). Поэтому дамп снимаем из Linux.

### 4.1 Подготовить каталог

Карта при штатной системе смонтирована в `/e-data/<uuid>`:

```sh
D=/e-data/35b6074c9e7427375cef67d5406a73e8/nand-dump
mkdir -p "$D" && cd "$D"
df -h .        # нужно ~260 МБ свободного места
```

### 4.2 SPI NOR — обычный `dd`

```sh
dd if=/dev/mtd0 of=mtd0_uloader.bin bs=4096
dd if=/dev/mtd1 of=mtd1_barebox.bin bs=4096
dd if=/dev/mtd2 of=mtd2_env.bin    bs=4096
```

### 4.3 NAND — только `nanddump` (учитывает OOB/ECC)

```sh
for p in 3 4 5 6 7 8; do
    nanddump --bb=dumpbad -q -f mtd${p}.bin /dev/mtd${p}
done
```

`--bb=dumpbad` — сохраняет и содержимое плохих блоков (для полного дампа это
правильно). `--omitoob` включён по умолчанию: в файле только данные, без OOB.

### 4.4 Сверить и забрать с карты

```sh
md5sum *.bin > md5sums.txt
md5sum -c md5sums.txt
```

Наш дамп (эталон для сверки):

| mtd | Раздел | Размер, Б | md5 |
|-----|--------|-----------|-----|
| 0 | uloader | 262 144 | `6dc46d70479e3a93a84969c43822a16b` |
| 1 | barebox | 524 288 | `df8a067c91be376a8b22c5081114cce9` |
| 2 | env | 262 144 | `0c86253e9a6bf403484fd9381a62e055` |
| 3 | config | 10 485 760 | `dfd028c6da6d25052775c16f97994bea` |
| 4 | kernel1 | 10 485 760 | `00eb14712dc6419ef92511b418c119c3` |
| 5 | rootfs1 | 115 343 360 | `9d52e64a596d6fc680a914ffb7474586` |
| 6 | kernel2 | 10 485 760 | `ed62b015ebfb2459e2400af061a9ea0e` |
| 7 | rootfs2 | 115 343 360 | `9992781b0a1e51785948743a632083fa` |
| 8 | reserved | 6 291 456 | `045848c1ba838010840a3d12b9e9863c` |

**Пока копия не лежит на другом носителе — NAND не трогать.**

### 4.5 Восстановление (если понадобится)

```sh
# NAND: kernel2 — тем же, чем писали
flash_erase /dev/mtd6 0 0
nandwrite -a -p /dev/mtd6 mtd6_kernel2.bin

# SPI NOR: env (256 КиБ) — обычный dd после стирания
flash_erase /dev/mtd2 0 0
dd if=mtd2_env.bin of=/dev/mtd2 bs=64k
# dd может ругнуться «fsync failed» — это нормально для MTD,
# проверить чтением:
dd if=/dev/mtd2 of=/tmp/env-read.bin bs=64k count=4 status=none
md5sum /tmp/env-read.bin          # сверить с §4.4
```

`uloader`/`barebox` (`mtd0`/`mtd1`) восстанавливать не нужно, если их не
трогали. Если всё же понадобится — только `flashcp` из Linux или
`update -t barebox`/`update -t uloader` из barebox, и **только** при
работающем внешнем программаторе как запасном варианте.

---

## 5. Подготовка SD-карты

### 5.1 Запись образа

```sh
lsblk                                   # найти карту, например /dev/sdX
sudo umount /dev/sdX* 2>/dev/null
sudo dd if=nas520_rootfs.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

> ⚠️ `of=/dev/sdX` — **вся карта**, не раздел. В образе нет таблицы разделов.

### 5.2 Расширить ФС на всю карту

Образ занимает 2.7 ГБ; на 16-гигабайтной карте останется ~12 ГБ неиспользуемых,
если этого не сделать:

```sh
sudo e2fsck -f /dev/sdX
sudo resize2fs /dev/sdX
```

Проверено на 16-гигабайтной карте: было 2.6 ГиБ, стало **14.8 ГиБ**
(≈13 ГиБ свободно). Метка `SD_SYSTEM` и UUID при этом сохраняются.

### 5.3 Первая загрузка

При **самом первом** старте `/etc/preinit` запускает `zy-nand-get`: он
распаковывает вендорский initramfs в `/firmware` и вытаскивает `/boot/uImage`
(ядро 3.2) и `/boot/bb.env` из NAND в файлы на SD. Это занимает около минуты и
сопровождается шумным выводом в консоль — пугаться не нужно. Ядро системы при
этом уже наше, из NAND; файлы в `/boot` — просто копии для совместимости.

При следующих загрузках `zy-nand-get` вызывается снова (файл-маркер
`/etc/.zy-first.done` в этом образе не создаётся), но сразу выходит, потому что
файлы уже на месте — в логе это одна-две строки, а не минута распаковки.

```sh
# после первой успешной загрузки (необязательно)
sudo tune2fs -U random /dev/sdX
```

> UUID менять безопасно, потому что в `root=` используется `/dev/sda`, а не
> `UUID=`. Если хотите `root=UUID=…` — меняйте UUID **и** bootargs одновременно.

---

## 6. TFTP-сервер (openSUSE)

```sh
# конфликтующий пакет tftp удалить, поставить atftp
sudo zypper rm tftp
sudo zypper in atftp

# каталог по умолчанию
sudo mkdir -p /srv/tftpboot
sudo systemctl enable --now atftpd.socket

# проверка
echo test | sudo tee /srv/tftpboot/test.txt
atftp -g -r test.txt -l /tmp/test.txt 127.0.0.1 && cat /tmp/test.txt
```

Положить в `/srv/tftpboot/` ядро:

```sh
sudo mount -o loop,ro nas520_rootfs.img /mnt
sudo cp /mnt/boot/vmlinuz-6.6.84+nas5xx /srv/tftpboot/uImage
sudo umount /mnt
```

(или взять `uImage` из архива автора). Файл уже является uImage с вложенным
DTB — ничего собирать не нужно.

Контрольные суммы нашего `uImage`:

```
размер  7 948 950 байт
md5     f9c83441a7f2815c0f95583a1522bdc5
CRC32   0x7c210d68
load    0x0f008000
```

### Если TFTP не нужен: HTTP

Для мелких файлов (скрипты, env-образ) удобнее обычный HTTP — им же потом
пользуется Debian:

```sh
python3 -m http.server 8000 --directory /srv/tftpboot
# на NAS:
wget http://192.168.0.194:8000/postinstall.sh -O /tmp/postinstall.sh
```

TFTP в barebox остаётся нужен только для прошивки разделов (`update … -m tftp`).

---

## 7. Консоль

```sh
sudo zypper in picocom
sudo picocom -b 115200 /dev/ttyUSB0
```

Если пользователь не в группе `dialout`/`uucp` — либо `sudo`, либо добавить
себя в группу. При проблемах вида `device reports readiness to read but returned
no data` — переподключить адаптер.

Вход в barebox: при включении в течение `autoboot_timeout` (3 с) нажать любую
клавишу. Приглашение: `Barebox-C2K >/`.

---

## 8. Прошивка ядра в NAND

Пишем **только `kernel2`** (mtd6). `uloader`, `barebox` и слот 1 не трогаем.

### Вариант A — из barebox по TFTP (штатный)

```text
Barebox-C2K >/ ethact eth0
Barebox-C2K >/ eth0.ethaddr=5C:F4:AB:64:B7:CA
Barebox-C2K >/ eth0.serverip=192.168.0.194
Barebox-C2K >/ dhcp
Barebox-C2K >/ ping 192.168.0.194
```

> `serverip` дополнительно прописан в `/env/config`; скрипт `update` его
> перечитывает, поэтому правильнее сразу указать свой IP ноутбука в
> `/env/config` (см. §9.3).

Две типичные ошибки на этом шаге:

- `warning: No MAC address set. Using random address …` и следом
  `tftp failed: Network is down` — не выполнен `dhcp` (или не задан
  `eth0.ethaddr`). Порядок именно такой: `ethact` → `eth0.ethaddr` → `dhcp`.
- `dhcp` печатает `T T T …` — не тот порт/нет линка, см. §9.1.

```text
Barebox-C2K >/ update -t kernel2 -d nand -m tftp -f uImage -c
```

`update` сам стирает раздел, заливает образ, ставит защиту и сверяет CRC.
Ожидаемый CRC32 — `0x7c210d68`.

### Вариант B — из Linux (mtd-utils)

Нужен файл `uImage` на самой NAS (в `/tmp` он не влезет — там tmpfs 5 МБ,
кладите на SD). Например, забрать по HTTP с ноутбука:

```sh
# на ноутбуке
python3 -m http.server 8000 --directory /srv/tftpboot

# на NAS
cd /e-data/<uuid>
wget http://192.168.0.194:8000/uImage -O uImage
md5sum uImage        # f9c83441a7f2815c0f95583a1522bdc5

flash_erase /dev/mtd6 0 0
nandwrite -a -p /dev/mtd6 ./uImage

# проверка: читаем обратно и сравниваем
nanddump -q /dev/mtd6 | head -c 7948950 | md5sum
```

### Проверка bootm

```text
Barebox-C2K >/ bootm /dev/nand0.kernel2.bb
```

Если образ битый, `bootm` вернётся с ошибкой, и `/env/bin/boot` сам переключится
на слот 1. Если же ядро **стартует и паникует** — автопереключения нет, откат
вручную (§11).

---

## 9. Загрузка Debian

### 9.1 Сеть: какой порт работает

В barebox статус линка смотрим так:

```text
Barebox-C2K >/ phy stat
Barebox-C2K >/ phy read 4 1      # PHY4 = eth0
Barebox-C2K >/ phy read 6 1      # PHY6 = eth1
```

Бит `0x0004` в регистре 1 (BMSR) — link up. На нашем экземпляре рабочим оказался
**`eth0` (PHY4)** — тот порт, который при штатной прошивке числится «вторым».
`eth1` (PHY6) давал link up, но MAC не передавал (`tx- carrier sense errors`) —
пакеты не уходили через свитч AR8328.

Если сеть не поднимается, помогает инициализация свитча:

```text
Barebox-C2K >/ switch init
```

### 9.2 Что должно быть в bootargs

Debian грузится с SD целиком (`/dev/sda`), а `/etc/preinit` **в образе есть** и
сам делает `zy-hw-init` + `exec /sbin/init`, поэтому `init=` оставляем:

```text
Barebox-C2K >/ bootargs="console=ttyS0,115200n8 init=/etc/preinit root=/dev/sda rootwait rw rootfstype=ext4"
Barebox-C2K >/ bootm /dev/nand0.kernel2.bb
```

Проверить вручную, до любых изменений env. Именно так и стоит делать первый
запуск Debian.

### 9.3 Сделать конфигурацию постоянной

Штатный `/env/bin/boot` собирает `bootargs` сам. Для SD-загрузки в нём уже есть
ветка `rootfs_loc=sata`, но она жёстко подставляет `root=/dev/sda2` (в образе
разделов нет, система — на всём диске).

Настройки загрузчика — это не файл на диске, а раздел `env` в SPI (`mtd2`).
barebox монтирует его как каталог `/env`; правятся два файла: `/env/config` и
`/env/bin/boot`.

#### Что правим

| Файл | Было | Стало |
|------|------|-------|
| `/env/config` | `rootfs_loc=nand` | `rootfs_loc=sata` |
| `/env/config` | `rootfs_type=ubifs` | `rootfs_type=ext4` |
| `/env/config` | `eth0.serverip=192.168.1.70` | IP вашего ноутбука (TFTP) |
| `/env/bin/boot` | `root=/dev/sda2 …` | `root=/dev/sda … rootwait` |

Дополнительно (необязательно, но чище): в `/env/config` убрать строку
`pcie_gen1_only=yes` и строку `bootargs="$bootargs mac_addr=…"`. Оба параметра
нужны были вендорскому ядру 3.2; ядро 6.6 грузится без них (проверено), а в
cmdline они давали мусор `mac_addr=,,`.

#### Как править: встроенный редактор

В этой сборке barebox **нет `setenv`**, зато есть `sedit`. Управление:

- `sedit /env/config` — открыть файл;
- **Ctrl-D** — сохранить и выйти, **Ctrl-C** — выйти без сохранения.

Порядок (проверено на устройстве):

```text
Barebox-C2K >/ mw 0x904700D0 0x010000A0     # покормить MCU-сторож
Barebox-C2K >/ sedit /env/config
Barebox-C2K >/ sedit /env/bin/boot
Barebox-C2K >/ cat /env/config              # проверить глазами
Barebox-C2K >/ cat /env/bin/boot
Barebox-C2K >/ saveenv
Barebox-C2K >/ reset
```

`saveenv` печатает примерно:

```text
saving environment
spi_sector_erase: erase sector 12
Erasing Done.
spi_sector_erase: erase sector 13
Erasing Done.
Erasing Done.
Wrote 13568 bytes at sec 12 in 53 iterations.
```

(13568 байт — это размер нашего env; у вас может отличаться. Стираются сектора
12–13 SPI, то есть только раздел `env`.)

#### Что должно получиться

После `reset` Debian грузится сам, а в консоли видна такая командная строка
(проверенная):

```text
Kernel command line: console=ttyS0,115200n8 init=/etc/preinit  ip=dhcp \
  root=/dev/sda rootfstype=ext4 rootwait rw noinitrd \
  mtdparts=spi0.0:256k(uloader)ro,512k(barebox)ro,256k(env);comcertonand:… \
  usb3_internal_clk=yes
```

Ключевое: `root=/dev/sda` и `rootwait`. Если увидели `root=ubi0:rootfs` — env не
применился (не сохранён, либо правка не в тот файл): снова `sedit` + `saveenv`.

> ⚠️ Пока в env стоит `rootfs_loc=sata`, штатная прошивка из NAND больше не
> загружается: её корень остался в NAND (ubifs), а env теперь указывает на
> `/dev/sda`. Откат — §11.

#### Способ без редактора (необязательный)

Если править в терминале неудобно (например, доступ только «вслепую» по
serial), env можно собрать на ноутбуке и залить готовым образом:
`tools/envfs.py` (приложение D). Проверенный порядок:

```text
Barebox-C2K >/ ethact eth0; eth0.ethaddr=5C:F4:AB:64:B7:CA; dhcp
Barebox-C2K >/ tftp env.bin /env.bin
Barebox-C2K >/ memcpy -s /env.bin -d /dev/mem 0 0x3008000 0x40000
Barebox-C2K >/ addpart /dev/mem 256K@0x3008000(envtest)
Barebox-C2K >/ mkdir /envtest
Barebox-C2K >/ loadenv /dev/mem.envtest /envtest
Barebox-C2K >/ cat /envtest/config
Barebox-C2K >/ saveenv /dev/env0 /envtest
Barebox-C2K >/ reset
```

`loadenv` в `/envtest` ничего не меняет в рабочем `/env` — это «прогон» нового
образа до записи во флеш. Тем же способом восстанавливается исходный env из
дампа `mtd2_env.bin`.

### 9.4 Watchdog и вентилятор (подробно)

На плате **два независимых сторожа**. Именно из-за них плата «сама» перезагружалась
в barebox и сильно грелась.

| Сторож | Что это | Таймаут | Кто кормит |
|--------|---------|---------|------------|
| **SoC WDT** | аппаратный таймер C2000, `fsl,ls1024a-wdt`, драйвер `CONFIG_LS1024A_WATCHDOG=y` (встроен) | 15 с, пинг каждые 5 с (`/etc/watchdog.conf`) | `/usr/sbin/watchdog` (юнит `watchdog.service`) |
| **MCU watchdog** | внешний MCU (`zyxel,nas-mcu`, линия `wdt`); если не «гладить» — передёргивает питание CPU | ~60 с (по комментарию вендорского `zy-hw-init`) | прямая запись в GPIO-регистр `0x904700D0` (значение `0x010000A0`) и `nas_keep_alive.sh` |

#### barebox

`barebox` MCU-сторож не кормит. Отсюда «спонтанные» ребуты через некоторое время
после входа в консоль. Лечится ровно теми командами, что стоят в штатных
`/env/bin/init` / `/env/bin/boot`:

```text
mw 0x904700D0 0x010000A0     # MCU: сброс/стоп сторожа
mw 0x90470058 0x05000000     # вентилятор
mw 0x90458000 0x80000001     # PWM
mw 0x90458028 0x80001388
mw 0x9045802C 0x00000fa0
```

> Записи `mw` живут только в RAM — после каждого сброса их нужно повторять.
> Поэтому они и вписаны в скрипты, которые выполняются при каждой загрузке.

В ветках ошибок MFG-скрипта вендора используется другое значение —
`mw 0x904700D0 0x020000A0` (по смыслу — принудительный сброс). **Не путать** с
`0x010000A0`: первое «дёргает» плату, второе — успокаивает сторожа.

#### Что делает Debian

1. **`/etc/preinit` → `/usr/local/bin/zy-hw-init`** (выполняется как `init=`,
   то есть очень рано):
   - ждёт до 10 с появления `/dev/comcerto_wdt` **или** `/dev/watchdog0`;
   - если узел найден — запускает `/sbin/watchdog -t 8 -T 15 <узел>`;
   - `echo 1 > /proc/mcu_wdt` — «остановить MCU-watchdog» (`1` = стоп,
     `0` = снова включить). На нашем экземпляре `/proc/mcu_wdt` = `1`.
2. **`/etc/rc.local`** — `busybox devmem 0x904700D0 w 0x010000A0` (ещё раз
   кормит MCU до входа в multi-user).
3. **`watchdog.service`** — штатный демон Debian с `/etc/watchdog.conf`:

   ```text
   watchdog-device   = /dev/watchdog
   watchdog-timeout  = 15
   interval          = 5
   realtime          = yes
   priority          = 1
   ```

   Именно он (PID `watchdog`, родитель — `watchdogd`) держит `/dev/watchdog`.
4. **`nas-watchdog.service`** (`WantedBy=multi-user.target`,
   `DefaultDependencies=no`, `After=local-fs.target`, `Restart=always`,
   RT-приоритет 99) → **`/usr/local/bin/nas_keep_alive.sh`**:

   ```sh
   dmesg -n 1
   while true; do
       echo . > /dev/watchdog
       /bin/busybox devmem 0x904700D0 w 0x010000A0 > /dev/null 2>&1
       sleep 5
   done
   ```

   Задумано так, что один процесс кормит **оба** сторожа. На практике
   `/dev/watchdog` уже занят демоном из п. 3, поэтому `echo . > /dev/watchdog`
   каждые 5 секунд даёт `Device or resource busy` в журнале. MCU при этом
   действительно кормится (строка `devmem` работает). Лечится одной правкой —
   §10.1.

В ядре включено:

```
CONFIG_WATCHDOG=y
CONFIG_LS1024A_WATCHDOG=y
CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y   # если WDT уже запущен загрузчиком,
                                        # ядро кормит его до передачи в userspace
# CONFIG_WATCHDOG_NOWAYOUT is not set   # корректное закрытие (magic close) работает
CONFIG_WATCHDOG_OPEN_TIMEOUT=0          # нет принудительного таймаута открытия
```

Что реально на устройстве:

```text
$ ls -l /dev/watchdog*
crw------- 1 root root  10, 130 /dev/watchdog      # SoC WDT (misc)
crw------- 1 root root 248,   0 /dev/watchdog0     # тот же WDT (cdev)

$ pgrep -a watchdog
38 watchdogd               # поток ядра
550 /usr/sbin/watchdog     # демон Debian

$ cat /proc/mcu_wdt
1                          # MCU-сторож остановлен

$ systemctl is-active watchdog nas-watchdog
active
active
```

- `zy-hw-init` ищет `/dev/comcerto_wdt` **или** `/dev/watchdog0` — второй узел
  в 6.6 есть, поэтому демон стартует нормально.
- Узел открывается **эксклюзивно**, отсюда и `EBUSY` у `nas_keep_alive.sh`.
  Проверить, кто держит: `sudo fuser -v /dev/watchdog`.
- `wdctl` (util-linux) на этой сборке информации не отдаёт — смотрите
  `dmesg | grep -i wdt`.

#### Гонка на загрузке

`barebox` кормит MCU прямо перед `bootm` и даёт ~60 с. За это время Debian
должен дойти до `rc.local` / `nas-watchdog`. Если USB-корень определяется
долго (или ФС проверяется), возможен цикл перезагрузок каждые ~60 с.

Как отличить:

- ребут примерно через 60 с после старта ядра, паники нет → не кормится MCU;
- ребут через ~15 с после старта userspace → открыт SoC WDT, но его никто не
  пингует (нет `nas_keep_alive.sh`).

Если нужно гарантированно пережить медленную загрузку — добавить в `/etc/preinit`
(он выполняется как init до systemd) строку:

```sh
busybox devmem 0x904700D0 w 0x010000A0
```

`rootdelay=` для этого не годится: он задерживает монтирование корня, то есть
увеличивает именно то окно, в котором MCU не кормится.

#### Проверка

```bash
ls -l /dev/watchdog*
cat /proc/mcu_wdt 2>/dev/null      # 1 = MCU-сторож остановлен
sudo fuser -v /dev/watchdog        # кто держит узел
dmesg | grep -iE "wdt|watchdog|mcu"
systemctl is-active watchdog nas-watchdog
journalctl -b | grep -c "resource busy"   # должно быть 0 после §10.1
```

Если `/proc/mcu_wdt` существует: `echo 1 > /proc/mcu_wdt` — стоп (без ребута),
`echo 0 > /proc/mcu_wdt` — снова включить.

#### Если плата уходит в ребут-цикл

1. Остановить autoboot в barebox.
2. Не грузить Debian: `bootm /dev/nand0.kernel1.bb` (слот 1), либо временно
   `bootargs="console=ttyS0,115200 init=/bin/sh"` и в шелле:
   ```sh
   devmem 0x904700D0 w 0x010000A0
   mount -o remount,rw /
   ```
3. Починить `nas-watchdog` / `rc.local` либо добавить petting в `/etc/preinit`.

Если ядро уже загрузилось, но зависло (например, паника `VFS: Unable to mount
root fs`), перезагрузить плату можно по serial без кнопки питания:

```text
BREAK            # break-условие (в picocom — Ctrl-A Ctrl-B, в screen — Ctrl-A B)
b                # SysRq-b = reboot
```

В ядре `CONFIG_MAGIC_SYSRQ=y`, `CONFIG_MAGIC_SYSRQ_SERIAL=y`. После паники
`CONFIG_PANIC_TIMEOUT=0` — то есть ядро **не** перезагружается само, а висит;
через ~60 с его всё равно передёрнет MCU-сторож, и плата вернётся в barebox.

#### Вентилятор — это отдельно

Симптомы похожи (ребут/перегрев), причины разные: без PWM радиатор греется, без
petting'а плата перезагружается.

Что реально в образе:

- `fancontrol.service` есть, но **всегда inactive**: у него
  `ConditionFileNotEmpty=/etc/fancontrol`, а файла в образе нет (нет и
  `pwmconfig`-конфига, и `hwmon`-узлов).
- `zy-fanctrl.timer` **не существует** (его нет ни в `/etc/systemd/system`, ни в
  `/lib/systemd/system`).
- `/usr/local/bin/select-fan-speed.sh` — интерактивный whiptail-хелпер: читает
  текущий ШИМ и правит строку в `/etc/rc.local`. В неинтерактивной установке
  бесполезен.
- `/usr/local/sbin/fanctrl.sh` — авторегулятор по температуре (порог 40/42/45/49 °C),
  но он ниоткуда не запускается автоматически.
- `/sys/class/thermal` и `/sys/class/hwmon` в этом ядре **пусты**; температура
  читается напрямую с MCU: `sudo i2cget -y 0 0x0a 0x07` (значение в °C,
  например `0x1f` = 31 °C).

Вентилятор при этом работает: в `/env/bin/boot` перед `bootm` записываются
регистры PWM (`0x9045802C` = `0xfa0`), но после загрузки Debian читается другое
значение — им управляет уже ядро. Фактическое состояние смотрим так:

```bash
sudo mmiotool -r 0x9045802C     # ШИМ, на нашем экземпляре 0x000005dc
sudo mmiotool -r 0x90470058     # 0x05000000
```

`0x000005dc` соответствует примерно 1200 об/мин. Если вентилятор шумит или,
наоборот, стоит — задайте значение вручную (`sudo mmiotool -w 0x9045802C
0x00000fa0`) и проверьте температуру; чтобы значение сохранялось после
перезагрузки, добавьте такую строку в `/etc/rc.local`.

---

## 10. После установки

### 10.1 Опционально: `tools/postinstall.sh`

Скрипт лежит в репозитории, безопасен и идемпотентен (можно запускать сколько
угодно раз). Ничего не требует для загрузки — это мелкие правки «чтобы не
мешало». Лечит **уже установленную** систему: переустанавливать образ не нужно,
правки живут в файловой системе SD.

```bash
# на ноутбуке
python3 -m http.server 8000 --directory /srv/tftpboot

# на NAS
curl -fsSL http://192.168.0.194:8000/postinstall.sh -o /tmp/postinstall.sh
sudo sh /tmp/postinstall.sh --check   # посмотреть, что будет сделано
sudo sh /tmp/postinstall.sh           # применить
```

Версия скрипта печатается в первой строке (`nas520 postinstall v1.1.0`),
применённые шаги пишутся в `/var/lib/nas520-postinstall/applied.log` с версией
и временем. Это значит, что после обновления скрипта достаточно скачать его
заново и запустить — новые шаги применятся, старые пропустятся.

Что делает:

1. В `/usr/local/bin/nas_keep_alive.sh` комментирует строку
   `echo . > /dev/watchdog` (делает резервную копию `.orig`), оставляя
   кормление MCU через `0x904700D0`, и перезапускает `nas-watchdog.service`.
   Результат: в журнале больше нет `Device or resource busy` каждые 5 секунд.
2. Маскирует `fancontrol.service`, который в этом образе не может запуститься
   (нет `/etc/fancontrol`). Если `/etc/fancontrol` есть — не трогает.
3. Печатает состояние: узлы watchdog, `/proc/mcu_wdt`, статусы юнитов,
   температуру (`i2cget 0 0x0a 0x07`) и текущий ШИМ вентилятора.

Проверенный вывод (первый запуск после отката правок):

```text
nas520 postinstall v1.1.0 (apply mode)
== 1/2 watchdog keep-alive ==
   comment out 'echo . > /dev/watchdog' in /usr/local/bin/nas_keep_alive.sh
   restarted nas-watchdog.service
== 2/2 fancontrol ==
   disable and mask fancontrol.service (no /etc/fancontrol; fan runs from the SoC PWM)
== state ==
   watchdog devices : /dev/watchdog /dev/watchdog0
   /proc/mcu_wdt    : 1 (1 = MCU watchdog stopped)
   watchdog.service    : active
   nas-watchdog.service: active
   fancontrol.service  : inactive
   CPU temperature  : 28 C
   fan PWM 0x9045802C: 0x000005dc

applied by this script:
nas_keep_alive.sh: drop duplicate /dev/watchdog feeder	v1.1.0	2026-11-19T04:00:52Z
fancontrol.service: masked (no /etc/fancontrol)	v1.1.0	2026-11-19T04:01:11Z

done.
```

Повторный запуск:

```text
   already done: watchdog feeder patched
   already done: fancontrol.service masked
```

`--check` (он же `--dry-run`) ничего не меняет, только печатает `would …`.

Откат: вернуть `nas_keep_alive.sh.orig` и выполнить
`sudo systemctl unmask fancontrol` (при желании — `rm -rf
/var/lib/nas520-postinstall`).

### 10.2 Проверки после установки

Это не пересказ авторских скриптов, а быстрый способ убедиться, что образ
живой:

```bash
# система и диск
uname -a                       # 6.6.84+nas5xx
lsblk                          # /dev/sda — ваша SD, без разделов
df -h /                        # весь объём карты (~15G)

# сеть (PFE)
ip -br a                       # eth0 UP с адресом
lsmod | grep pfe
dmesg | grep -i pfe | tail

# Cockpit
curl -k -s -o /dev/null -w '%{http_code}\n' https://127.0.0.1:9090   # 200

# watchdog и вентилятор
cat /proc/mcu_wdt              # 1
systemctl is-active watchdog nas-watchdog
sudo i2cget -y 0 0x0a 0x07     # температура в °C
sudo mmiotool -r 0x9045802C    # ШИМ

# RAID-обвязка автора образа
ls /etc/udev/rules.d/99-raid-rebuild.rules
cat /etc/mdadm/mdadm.conf
systemctl status mdmonitor --no-pager   # inactive, пока нет массивов — это нормально
journalctl -t raid-auto -n 20 --no-pager
```

Если Ethernet не появился:

```bash
dmesg | grep -i pfe
lsmod | grep pfe
ip link
```

---

## 11. Откат

`uloader`, `barebox`, `config`, `kernel1`, `rootfs1`, `rootfs2` и `reserved` не
менялись. Переписаны ровно два раздела:

| Раздел | Что теперь | Чем вернуть |
|--------|-----------|-------------|
| `kernel2` (mtd6) | ядро Debian | `mtd6_kernel2.bin` из дампа |
| `env` (mtd2) | `rootfs_loc=sata`, `root=/dev/sda` | `mtd2_env.bin` из дампа |

Полный откат = вернуть оба раздела. Порядок важен: **сначала ядро, потом env**,
иначе плата попробует загрузить вендорский корень с ядром Debian.

### Из Debian (проверено)

```sh
# на ноутбуке
python3 -m http.server 8000 --directory /home/valov/nas520-nand-dump

# на NAS
cd /tmp
wget http://192.168.0.194:8000/mtd6_kernel2.bin -O k2.bin
wget http://192.168.0.194:8000/mtd2_env.bin     -O env.bin
md5sum k2.bin env.bin      # сверить с таблицей §4.4

sudo flash_erase /dev/mtd6 0 0
sudo nandwrite -a -p /dev/mtd6 k2.bin

sudo flash_erase /dev/mtd2 0 0
sudo dd if=env.bin of=/dev/mtd2 bs=64k
```

`dd: fsync failed for '/dev/mtd2': Invalid argument` — это нормально: MTD не
поддерживает `fsync`, запись при этом выполняется. Проверка чтением:

```sh
sudo dd if=/dev/mtd2 of=/tmp/env-read.bin bs=64k count=4 status=none
md5sum /tmp/env-read.bin   # должен совпасть с mtd2_env.bin
```

После `sudo reboot` плата грузится ровно как до установки.

### Из barebox (если Debian не грузится)

Env можно вернуть и без Linux — тем же проверенным способом, что в §9.3:
`tftp` → `memcpy` → `loadenv` в отдельный каталог → `saveenv /dev/env0 <каталог>`.
Ядро в NAND из barebox удобнее всего вернуть штатной командой вендора:

```text
Barebox-C2K >/ ethact eth0; eth0.ethaddr=5C:F4:AB:64:B7:CA; dhcp
Barebox-C2K >/ update -t kernel2 -d nand -m tftp -f mtd6_kernel2.bin
```

> Этот вариант **не проверялся**: `update` рассчитан на uImage и сам считает CRC.
> Если он откажется — восстановите `kernel2` из Debian командой `nandwrite`
> (см. выше): Debian грузится независимо от содержимого `kernel2`, пока живы
> env и SD.

### Если испорчен только env

`env` — отдельный раздел SPI; `uloader`/`barebox` он не затрагивает, плата в
любом случае дойдёт до приглашения `Barebox-C2K >/`. Достаточно восстановить
`mtd2_env.bin` любым из способов выше.

> ⚠️ После отката Debian-загрузка пропадёт: в env снова будет
> `rootfs_loc=nand`. Чтобы вернуться на Debian — повторить §9.3 (ядро в
> `kernel2` при этом уже на месте, если вы его не перезаписывали).

---

## 12. Troubleshooting

| Симптом | Причина / решение |
|---------|-------------------|
| `bootm` → `ERROR: out of memory` | образ грузится в файл в ramfs (~10 МБ malloc). Грузить из NAND (`/dev/nand0.kernel*.bb`) или из Linux |
| `tftp` большого файла → `out of memory` | то же: ramfs мал. Писать сразу в раздел (`update -t kernel2 …`) |
| `dhcp` печатает `T T T` | нет ответа/не тот порт. Ctrl+C, `switch init`, проверить `phy stat`, переставить кабель в другой LAN-порт |
| `warning: No MAC address set…`, затем `tftp failed: Network is down` | не выполнен `dhcp` или не задан `eth0.ethaddr`. Порядок: `ethact eth0` → `eth0.ethaddr=…` → `dhcp` (§8) |
| `addpart … cannot create : File exists` | раздел с таким именем уже создан в ramfs; возьмите другое имя (например `envtest2`). `rm -r` в barebox не поддерживается — только `rm`/`rmdir` |
| Link up, но ping не идёт | пакеты не проходят через AR8328 (`gemac_stats` → `tx- carrier sense errors`). Порт не тот: нужен `eth0`/PHY4 |
| `Rx pkt not on expected port` | DHCP-ответ пришёл на другой порт свитча; это сообщение не фатально, адрес выдаётся |
| Плата перезагружается через ~15 с в barebox | не сброшен MCU-watchdog и не включён вентилятор: `mw 0x904700D0 0x010000A0` + команды PWM выше (§9.4) |
| Debian ребутится через ~60 с после старта ядра | не кормится MCU-watchdog: нет `nas-watchdog`/`rc.local` или слишком медленная загрузка (§9.4) |
| Debian ребутится через ~15 с после старта userspace | открыт SoC WDT, но его никто не пингует: проверьте `pgrep -a watchdog`, `systemctl status nas-watchdog` |
| В журнале каждые 5 с `Device or resource busy` для `/dev/watchdog` | `/dev/watchdog` уже держит `/usr/sbin/watchdog`; безвредно, лечится `tools/postinstall.sh` (§10.1) |
| `fancontrol.service` всегда `inactive` | в образе нет `/etc/fancontrol` — условие юнита не выполняется. Вентилятор работает от PWM; `postinstall.sh` маскирует юнит (§9.4, §10.1) |
| Сильно греется в barebox | вентилятор не включён (см. §9.4) |
| Debian паникует `VFS: Unable to mount root fs` | неверный `root=` (`/dev/sda`, не `sda1`/`sda2`/`mmcblk0`) или не тот `uImage`. Ядро при этом висит (`PANIC_TIMEOUT=0`), через ~60 с плату передёргивает MCU и она возвращается в barebox |
| Плата висит после паники, кнопки питания нет под рукой | по serial: `BREAK` (picocom: `Ctrl-A Ctrl-B`), затем `b` — SysRq-reboot |
| `dd: fsync failed for /dev/mtd2: Invalid argument` | нормально для MTD: запись выполняется, проверяйте чтением (§4.5, §11) |
| Debian паникует `Requested init` | уберите/проверьте `init=/etc/preinit` (в образе файл есть) |
| SD видна как `sda`, а не `mmcblk0` | так и должно быть: слот MicroSD подключён по USB3 |
| Не хватает места на `/` | не сделан `resize2fs` (§5.2) |

Полезные команды barebox:

```text
help                 список команд
ls / cat / printenv
phy stat             состояние PHY
gemac_stats eth0     статистика MAC
switch init          инициализация AR8328
crc32 -f FILE        CRC файла/раздела
md / mw              чтение/запись регистров
update -t …          прошивка разделов
```

---

## Приложение A. Переменные env

Штатные значения с нашего устройства (из дампа `mtd2_env.bin`):

```text
ip=dhcp
eth0.serverip=192.168.1.70
kernel_loc=nand
rootfs_loc=nand
rootfs_type=ubifs
kernelimage_type=uimage
kernelimage=uImage
rootfsimage=root.$rootfs_type-128k
spi_parts=256k(uloader)ro,512k(barebox)ro,256k(env)
nand_parts=10M(config),10M(kernel1),110M(rootfs1),10M(kernel2),110M(rootfs2),-(reserved)
rootfs_mtdblock_nand=2
autoboot_timeout=3
usb3_internal_clk=yes
bootargs=console=ttyS0,115200n8, init=/etc/preinit pcie_gen1_only=yes
bootargs=$bootargs mac_addr=$eth0.ethaddr,$eth1.ethaddr,$eth2.ethaddr
next_bootfrom=2
curr_bootfrom=2
kernel_mtd_1=4
sysimg_mtd_1=5
kernel_mtd_2=6
sysimg_mtd_2=7
fwversion_1=V5.21(AASZ.4)
fwversion_2=V5.21(AASZ.5)C0
ethaddr=5C:F4:AB:64:B7:CA
eth2addr=5C:F4:AB:64:B7:CB
serial_number=S150Z29005267
```

Что меняется для Debian (§9.3) — построчно:

```diff
-eth0.serverip=192.168.1.70
+eth0.serverip=192.168.0.194
-rootfs_loc=nand
+rootfs_loc=sata
-rootfs_type=ubifs
+rootfs_type=ext4
-bootargs="console=ttyS0,115200n8, init=/etc/preinit pcie_gen1_only=yes "
-bootargs="$bootargs mac_addr=$eth0.ethaddr,$eth1.ethaddr,$eth2.ethaddr"
+bootargs="console=ttyS0,115200n8 init=/etc/preinit "
```

и одна строка в `/env/bin/boot`:

```diff
-	bootargs="$bootargs root=/dev/sda2 rootfstype=$rootfs_type rw noinitrd"
+	bootargs="$bootargs root=/dev/sda rootfstype=$rootfs_type rootwait rw noinitrd"
```

Логика `/env/bin/boot` (кратко):

- `kernel_loc=nand` → `kdev=/dev/nand0.kernel${curr_bootfrom}.bb`
- `kernel_loc=tftp` → скачать `$kernelimage` в `/dev/ram0.kernel`
- `rootfs_loc=nand` + `rootfs_type=ubifs` → `root=ubi0:rootfs ubi.mtd=$rootfs_mtdblock,2048`
- `rootfs_loc=sata` → `root=/dev/sda rootfstype=$rootfs_type rootwait rw noinitrd`
- после неудачи `bootm` — переключение `curr_bootfrom` 1↔2 и повтор (при панике
  ядра этого не происходит)
- перед `bootm` — вентилятор/PWM/watchdog (см. §9.4)

---

## Приложение B. Как снимался дамп

- Штатная прошивка слота 2 загружена с NAND (`/firmware/mnt/nand` — UBI rootfs2).
- SD смонтирована как `/dev/sda` в `/e-data/<uuid>`.
- Дампы: `dd` для `/dev/mtd0…2`, `nanddump --bb=dumpbad` для `/dev/mtd3…8`.
- Файлы: 257 МБ, 9 штук + `md5sums.txt`, все md5 совпали (таблица §4.4).
- Копия хранится вне NAS (на ноутбуке), в репозиторий бинарные дампы не кладутся.

---

## Приложение C. Расхождения с исходными заметками автора

Заметки из архива автора (`README.txt`) написаны для более старого образа.
Наши `README.md` и это руководство уже учитывают всё перечисленное; таблица —
чтобы понимать, почему команды отличаются.

| Было в `README.txt` | Фактически |
|-------------|-----------|
| `root=/dev/sda1`, `tune2fs … /dev/sda1` | в образе нет разделов, система — `/dev/sda` |
| `root=/dev/mmcblk0p1` | MicroSD на USB3, устройство `/dev/sda` |
| «нужен initrd» / загрузка ядра + initrd | ядро с встроенным DTB, initrd не нужен |
| `setenv` / `saveenv` в barebox | `setenv` в этой сборке нет: переменные задаются присваиванием (`eth0.serverip=…`), файлы — `sedit`, сохранение env — `saveenv` (проверено) |
| «отредактируйте конфиг» без указания чем | в этой сборке есть только `sedit <file>`: **Ctrl-D** — сохранить, **Ctrl-C** — выйти |
| `nand erase.part barebox`, `nand write … barebox` | **нельзя**: barebox/uloader не трогаем, пишем только `kernel1`/`kernel2` |
| TFTP-каталог не указан | в openSUSE у atftp это `/srv/tftpboot` |
| прошивка «`update -t kernel`» | для слота 2: `update -t kernel2 -d nand -m tftp -f uImage` |
| `bootargs` без `init=` | `init=/etc/preinit` обязателен: в образе есть `/etc/preinit` |

---

## Приложение D. `tools/envfs.py` (необязательно)

Env в SPI — это образ файловой системы barebox (`envfs`). Скрипт умеет его
распаковывать, собирать и показывать содержимое — если удобнее править файлы на
ноутбуке, а не в `sedit`.

```sh
./tools/envfs.py list    nand-dump/mtd2_env.bin
./tools/envfs.py extract nand-dump/mtd2_env.bin env/
$EDITOR env/config env/bin/boot
./tools/envfs.py build   env/ env.bin --template nand-dump/mtd2_env.bin
```

Формат (barebox 2011.06.0 этой платы): заголовок 0x1C байт
(`0x798fba79`, priority, crc32 записей, длина записей, два поля нуля, crc32
первых 0x18 байт), дальше записи `{stamp, size, namelen, name, data}` с
выравниванием по 4 байта. `build` берёт метку `stamp` из шаблона.

Проверено: образ, собранный этим скриптом, `loadenv` в barebox принимает без
ошибок CRC, содержимое совпадает с исходным, а после `saveenv /dev/env0` плата
грузится с новыми настройками.

> Обычному пользователю скрипт не нужен: `sedit` + `saveenv` проще и не требует
> держать ноутбук рядом.

---

## Приложение E. Резервное ядро в `kernel1` (не сделано)

Идея: записать то же ядро Debian ещё и в `kernel1` (mtd4), чтобы авто-fallback
в `/env/bin/boot` (переключение `curr_bootfrom` 1↔2 при неудачном `bootm`)
грузил рабочее ядро, а не вендорское 3.2.

Почему не сделано в этом заходе:

- `/env/bin/boot` подставляет `root=/dev/sda` независимо от слота, так что
  загрузка «резервного» ядра пройдёт только при живых env и SD — то есть
  защищает от порчи `kernel2`, но не от проблем с картой;
- вендорское ядро в `kernel1` при этом теряется (восстанавливается из дампа
  `mtd4_kernel1.bin`), то есть плата перестаёт быть «откатываемой в штатную
  прошивку» без перепрошивки;
- выигрыш невелик: `kernel2` — тот же файл, что лежит в дампе/архиве.

Если делать: `flash_erase /dev/mtd4 0 0 && nandwrite -a -p /dev/mtd4 uImage`
из Debian, затем проверить `bootm /dev/nand0.kernel1.bb` вручную и только потом
полагаться на fallback.

---

## Приложение F. Что лежит в репозитории

| Файл | Назначение |
|------|-----------|
| `README.md` | краткое описание проекта (английский), быстрый старт, ссылки |
| `INSTALL_GUIDE.md` | это руководство |
| `tools/envfs.py` | разбор/сборка envfs (приложение D) |
| `tools/postinstall.sh` | необязательные правки после установки (§10.1) |
| `.gitignore` | образы и дампы (`*.img`, `*.img.gz`, `uImage`, `*.bin`) не коммитятся |

---

## Источники

- Образы автора: <https://mega.nz/folder/zwIUiaAZ#dWQR1B-A20QjlfZXmADpuQ>
- barebox: <https://www.barebox.org/doc/latest/>
- mtd-utils (`nanddump`, `nandwrite`, `flash_erase`): пакет `mtd-utils`
