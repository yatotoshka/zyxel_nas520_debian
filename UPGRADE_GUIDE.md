# Zyxel NAS520 — обновление Debian 11 → 12 → 13

Пошаговое обновление уже установленной системы (см. `INSTALL_GUIDE.md`) с
Debian 11 (bullseye) до Debian 13 (trixie) **без переустановки**.

Меняется только userspace на SD-карте. Ядро `6.6.84+nas5xx` остаётся в NAND
(`mtd6`) и не трогается: ни `uloader`, ни `barebox`, ни `kernel1/rootfs1`,
ни `env`. Поэтому откат на любом шаге — это возврат образа SD, а не
перепрошивка.

Всё ниже проверено на реальном NAS520 19.11.2026: bullseye → bookworm →
trixie, с перезагрузкой и проверкой после каждого шага.

---

## 0. Итог

| | bullseye (старт) | bookworm | trixie (финал) |
|---|---|---|---|
| Пакетов установлено | 751 | 787 | 810 |
| Занято на SD | 1.9 ГиБ | 1.9 ГиБ | 2.3 ГиБ |
| Ядро | 6.6.84+nas5xx | 6.6.84+nas5xx | 6.6.84+nas5xx |
| Cockpit | 239 | 287 | 337 |
| 45Drives | 0.5.10 (focal) | 0.5.10 (focal) | 4.6.4 / 0.5.14 / 0.1.14 |
| Длительность шага | — | 49 мин | 55 мин |

После финала: сеть/DHCP, SSH, Cockpit (`:9090`), Samba, оба watchdog'а,
zram, вентилятор и NAND — в норме, `systemctl --failed` пуст.

---

## 1. Что понадобится

- SSH-доступ к NAS (`admin`, sudo без пароля);
- ~3 ГиБ свободного места на SD (у нас было 13 ГиБ);
- ноутбук с `zstd` и ~15 ГиБ для образа SD;
- желательно UART-консоль — если после апгрейда отвалится сеть или SSH,
  это единственный вход (см. `INSTALL_GUIDE.md` §7);
- время: ~2 часа на оба dist-upgrade (armhf, 1 ГиБ RAM).

Все команды ниже — на NAS, кроме явно помеченных «на ноутбуке».

---

## 2. Шаг 0. Полный бэкап SD

Образ автора (`nas520_rootfs.img`) — это «день 0», а не состояние перед
апгрейдом. Поэтому снимаем карту целиком.

```bash
# на ноутбуке
mkdir -p /opt/nas520-backup && cd /opt/nas520-backup

ssh admin@<nas> 'sync; sudo sync'
ssh admin@<nas> 'sudo dd if=/dev/sda bs=4M status=none' \
  | zstd -T0 -3 -q -o sd-bullseye-$(date +%F).img.zst

zstd -t sd-bullseye-*.img.zst
sha256sum sd-bullseye-*.img.zst | tee SHA256SUMS
```

Проверка содержимого без распаковки на диск:

```bash
zstd -dc sd-bullseye-*.img.zst | head -c 67108864 > prefix.bin
file prefix.bin          # Linux rev 1.0 ext4 filesystem data, label 'SD_SYSTEM'
rm prefix.bin
```

Рядом сохраняем метаданные — они пригодятся для diff после апгрейда:

```bash
ssh admin@<nas> 'dpkg --get-selections'              > dpkg-selections.txt
ssh admin@<nas> "dpkg-query -W -f='\${Package} \${Version} \${Architecture}\n'" > packages.txt
ssh admin@<nas> 'sudo tar -C / -czf - etc'           > etc.tar.gz
ssh admin@<nas> '{ uname -a; cat /proc/cmdline; lsblk; cat /proc/mtd; blkid; }' > system-info.txt
```

И пакеты, которых нет ни в одном репозитории:

```bash
ssh admin@<nas> 'sudo apt-get install -y dpkg-repack'
ssh admin@<nas> 'sudo mkdir -p /tmp/repack && cd /tmp/repack && \
  sudo dpkg-repack linux-image-6.6.84+nas5xx linux-bsp-nas5xx \
                  linux-bsp-nas5xx-init linux-bsp-nas5xx-boot'
scp 'admin@<nas>:/tmp/repack/*' .
```

> **Про размер.** У нас образ вышел 13 ГиБ вместо ~2 ГиБ: свободное место
> на карте не было занулено, и `zstd` честно сжал старые данные. Для
> восстановления это не мешает. Если нужен компактный образ — перед `dd`
> сделайте `sudo fstrim -av` (если карта поддерживает discard) или
> перемонтируйте корень в `ro` и используйте `zerofree`.

**Критерий успеха:** `zstd -t` OK, sha256 записан, `dpkg-selections.txt` и
`etc.tar.gz` на месте, дампы NAND (`/home/valov/nas520-nand-dump/`) и
исходный образ автора не удалены.

---

## 3. Шаг 1. Чистка bullseye

Стоковый образ тянет за собой OpenMediaVault, PHP 7.4, Salt, nginx и ядро
3.2. Всё это не нужно и мешает апгрейду. Скрипт:
[`tools/bullseye-cleanup.sh`](tools/bullseye-cleanup.sh).

```bash
ssh admin@<nas> 'curl -fsSL http://<ноутбук>:8000/bullseye-cleanup.sh -o /tmp/c.sh'
ssh admin@<nas> 'sudo sh /tmp/c.sh 2>&1 | tee /root/phase1.log'
```

Сначала полезно посмотреть, что будет удалено:

```bash
sudo apt-get -s purge openmediavault-wol salt-minion salt-common \
  php7.4-bcmath php7.4-cgi php7.4-cli php7.4-common php7.4-fpm php7.4-json \
  php7.4-mbstring php7.4-opcache php7.4-readline php7.4-xml \
  php-cgi php-cli php-common php-fpm php-pam php-yaml \
  nginx nginx-common nginx-core libnginx-mod-http-geoip \
  libnginx-mod-http-image-filter libnginx-mod-http-xslt-filter \
  libnginx-mod-mail libnginx-mod-stream libnginx-mod-stream-geoip \
  wsdd linux-image-armhf linux-image-3.2.0-6-nas5xx \
  linux-headers-armhf linux-headers-3.2.0-6-nas5xx \
  linux-headers-3.2.0-6-common linux-kbuild-3.2
```

Удаляется ровно 30 пакетов + 4 autoremove (`geoip-database`, `libgd3`,
`libgeoip1`, `libxpm4`). **Не удаляются** `linux-bsp-nas5xx*` (в них
`/etc/preinit`, `zy-*`, LED, вентилятор) и `linux-image-6.6.84+nas5xx`.

Проверка и перезагрузка:

```bash
dpkg-query -W -f='${Package} ${Version}\n' | grep -E 'openmediavault|salt-|nginx|^php|wsdd|linux-.*3\.2' || echo none
sudo systemctl reboot
```

После перезагрузки: SSH, Cockpit на `:9090`, Samba, `watchdog`,
`nas-watchdog` — active; занято ~1.7 ГиБ.

---

## 4. Шаг 2. bookworm

```bash
sudo cp /etc/apt/sources.list /root/sources.list.bullseye
sudo tee /etc/apt/sources.list >/dev/null <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
sudo apt-get update
```

Сам апгрейд — [`tools/dist-upgrade.sh`](tools/dist-upgrade.sh), запускать
через `nohup`, чтобы обрыв SSH не убил `apt`:

```bash
scp tools/dist-upgrade.sh admin@<nas>:/tmp/
ssh admin@<nas> 'sudo nohup sh /tmp/dist-upgrade.sh bookworm >/dev/null 2>&1 &'
ssh admin@<nas> 'sudo tail -f /root/upgrade-bookworm.log'
```

Что происходит внутри: `apt-get upgrade --without-new-pkgs`, затем
`full-upgrade`, затем `autoremove --purge`. Conffiles сохраняются
(`--force-confdef --force-confold`), `needrestart` не задаёт вопросов.

Фактические цифры: 174 пакета в минимальном апгрейде, затем 442
обновлено / 100 новых / 4 удалено, 26 autoremove. 49 минут.

Затем:

```bash
sudo systemctl reboot
```

### Грабли bookworm (все встречены на живой системе)

| Симптом | Причина | Решение |
|---|---|---|
| SSH: `Permission denied`, в логе `none of user's groups are listed in AllowGroups` | в `sshd_config` остался `AllowGroups` с группой OMV, которой больше нет | `sudo sed -i 's/^AllowGroups .*/AllowGroups root users/' /etc/ssh/sshd_config && sudo sshd -t && sudo systemctl restart ssh` |
| `wd_keepalive.service` failed, `watchdog.service` inactive | оба демона претендуют на `/dev/watchdog` | `sudo systemctl stop wd_keepalive; sudo systemctl reset-failed wd_keepalive; sudo systemctl start watchdog` |
| `ldconfig: /lib/libzy.so is not an ELF file` | в образе автора лежит 512-байтная заглушка Zyxel | безвредно, игнорировать |
| `/etc/resolv.conf` стал ссылкой на `systemd-resolved` | `resolvconf` удалён при апгрейде | нормально, DNS работает через `systemd-resolved` |

Проверка после перезагрузки — [`tools/post-upgrade-check.sh`](tools/post-upgrade-check.sh):

```bash
scp tools/post-upgrade-check.sh admin@<nas>:/tmp/
ssh admin@<nas> 'sudo sh /tmp/post-upgrade-check.sh'
```

Ожидаемо: `Debian GNU/Linux 12`, ядро `6.6.84+nas5xx`, `eth0` с адресом,
10 разделов MTD, `/proc/mcu_wdt` = 1, `apt-get check` без ошибок.

---

## 5. Шаг 3. trixie

То же самое, меняются только источники:

```bash
sudo cp /etc/apt/sources.list /root/sources.list.bookworm
sudo tee /etc/apt/sources.list >/dev/null <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
sudo apt-get update
sudo nohup sh /tmp/dist-upgrade.sh trixie >/dev/null 2>&1 &
```

Фактические цифры: 379 пакетов в минимальном апгрейде, затем 237
обновлено / 140 новых / 74 удалено, 60 autoremove. 55 минут.

Удаляются в основном старые библиотеки (переход на `t64`) и `libpython3.11`
(ставится 3.13), `insserv`/`sysv-rc`/`startpar`. **`isc-dhcp-client` и
`ifupdown` остаются** — от них зависит сеть в `zy-hw-init`.

После перезагрузки:

```bash
sudo sh /tmp/post-upgrade-check.sh
```

Ожидаемо: `Debian GNU/Linux 13`, ядро `6.6.84+nas5xx`, все юниты active,
`systemctl --failed` пуст (кроме `smartmontools` — см. §6.2), 2.1–2.3 ГиБ
занято.

---

## 6. Шаг 4. Последние хвосты OMV и плагины Cockpit

### 6.1. Остатки OpenMediaVault

После `apt purge` в системе остаются файлы, которые не принадлежат ни
одному пакету — их ставил автор образа. Самые заметные:

- `monit` с конфигами `openmediavault-*.conf` — каждые 30 секунд пишет в
  журнал, что не может запустить `php7.4-fpm`, `nginx`, `omv-engined`;
- `folder2ram` — дублирует `tmpfs` на `/var/log` из `/etc/fstab`;
- `/etc/openmediavault`, `/usr/share/openmediavault`, `/var/lib/openmediavault`,
  `/var/www/openmediavault`;
- SysV-скрипты `/etc/init.d/openmediavault*` и ссылки `K02*` в `/etc/rc?.d`;
- cron-задания `/etc/cron.d/openmediavault-*`, `openmediavault-flushmailq`,
  `openmediavault-samba-recycle`;
- `/etc/systemd/system.conf.d/openmediavault-watchdog.conf`,
  `/etc/modules-load.d/openmediavault-watchdog.conf`.

Всё это убирает [`tools/omv-cleanup.sh`](tools/omv-cleanup.sh):

```bash
sudo sh /tmp/omv-cleanup.sh
```

Скрипт выключает `folder2ram`, ставит `purge` для `monit` и `cron-apt`,
удаляет перечисленные файлы и каталоги, делает `daemon-reload`.
После него `systemctl --failed` пуст.

### 6.2. smartd без дисков

`/etc/smartd.conf` в образе ссылается на `/dev/sdb` и `/dev/sdc`. Если
дисков нет, `smartd` завершается с кодом 17 и юнит висит в `failed`.
Правильнее сканировать то, что есть:

```bash
sudo cp /etc/smartd.conf /root/smartd.conf.bak
printf 'DEVICESCAN -d sat -n standby,q -a\n' | sudo tee /etc/smartd.conf
sudo mkdir -p /etc/systemd/system/smartmontools.service.d
printf '[Service]\nType=simple\nSuccessExitStatus=17\n' \
  | sudo tee /etc/systemd/system/smartmontools.service.d/no-devices.conf
sudo systemctl daemon-reload
sudo systemctl restart smartmontools
```

`Exit 17` = «нет ни одного SMART-устройства». Это не ошибка, поэтому юнит
считается успешным. Когда диски появятся, `smartd` запустится нормально и
будет их мониторить.

### 6.3. `comcerto_wdt` в `/etc/modules`

Драйвер watchdog в ядре 6.6 встроен, а `/etc/modules` пытается его
загрузить модулем:

```
Failed to find module 'comcerto_wdt'
```

Безвредно, но лучше закомментировать строку:

```bash
sudo sed -i 's/^comcerto_wdt$/# comcerto_wdt (built into the 6.6 kernel)/' /etc/modules
```

Строку `pfe` оставить — это модуль packet forwarding engine, он нужен.

### 6.4. Плагины 45Drives

Репозиторий `repo.45drives.com` объявляет архитектуры `all amd64`, поэтому
на armhf `apt` его индексы игнорирует. Пакеты при этом архитектурно
независимые (`all`), так что ставим их вручную:

```bash
# на ноутбуке
mkdir -p /srv/tftpboot/45drives && cd /srv/tftpboot/45drives
for p in cockpit-file-sharing/cockpit-file-sharing_4.6.4-1trixie_all.deb \
         cockpit-navigator/cockpit-navigator_0.5.14-1trixie_all.deb \
         cockpit-identities/cockpit-identities_0.1.14-1trixie_all.deb; do
  curl -fsSL --http1.1 -O "https://repo.45drives.com/enterprise/debian/pool/main/c/$p"
done
sha256sum *.deb | tee SHA256SUMS

# на NAS
cd /tmp/45d && curl -O http://<ноутбук>:8000/45drives/...   # все четыре файла
sha256sum -c SHA256SUMS
sudo apt-get install -y ./cockpit-*.deb
```

`apt` сам доставит `python3-botocore`, `inotify-tools`, `psmisc`, `rsync`,
`zip`, `file`, если их нет. У этих пакетов нет maintainer-скриптов, так что
ничего не перезапускается и не патчится.

Проверка:

```bash
cockpit-bridge --packages | grep -E 'file-sharing|navigator|identities'
dpkg-query -W -f='${Package} ${Version}\n' | grep cockpit
```

Ожидаемо: `4.6.4-1trixie`, `0.5.14-1trixie`, `0.1.14-1trixie`; в браузере
на `https://<nas>:9090` появляются File Sharing, Navigator и Identities.

> **Почему вручную, а не репозиторием.** Если добавить репозиторий с
> `[arch=all]`, `apt` начнёт ругаться на несовпадение архитектур при
> обновлении. Ручная установка `.deb` предсказуемее; новые версии так же
> скачиваются и ставятся поверх.

---

## 7. Шаг 5. Финальная проверка

```bash
sudo sh /tmp/post-upgrade-check.sh
```

| Проверка | Ожидаемое значение |
|---|---|
| `PRETTY_NAME` | `Debian GNU/Linux 13 (trixie)` |
| `uname -r` | `6.6.84+nas5xx` (ядро из NAND не менялось) |
| `ip -4 addr show eth0` | адрес по DHCP, default route |
| `systemctl --failed` | пусто |
| `cockpit.socket`, `smbd`, `watchdog`, `nas-watchdog` | active |
| `grep -c . /proc/mtd` | 10 |
| `/proc/mcu_wdt` | 1 |
| `/proc/swaps` | `/dev/zram0` 256 МиБ |
| `i2cget -y 0 0x0a 0x07` | температура, °C |
| `mmiotool -r 0x9045802C` | `0x000005dc` (ШИМ вентилятора) |
| `apt-get check` | без ошибок |
| `dpkg --audit` | пусто |

Замечания:

- `systemd-analyze` покажет ~50 секунд загрузки, из них ~30 — ожидание
  `UUID=c660be8e-…` из `/etc/fstab` (диск автора образа в `/srv/nas`).
  Если такого диска нет, строку можно закомментировать или уменьшить
  `x-systemd.device-timeout=`.
- `i2cget` лежит в `/usr/sbin` и не виден в `PATH` пользователя `admin` —
  запускайте через `sudo`.
- `wsdd` в trixie отсутствует. Если нужно обнаружение NAS в «Сети» Windows,
  поставьте `wsdd` из bookworm (`apt-get download wsdd` на bookworm-машине
  либо пакет `wsdd` 0.7 из bullseye) — это чистый Python, зависимостей
  почти нет.

---

## 8. Откат

NAND в этой процедуре не менялся, поэтому откат — только SD-карта.

**Из работающей системы** (если ssh ещё отвечает):

```bash
# на ноутбуке, карта в USB-кардридере, /dev/sdX — именно карта
zstd -dc /opt/nas520-backup/sd-bullseye-2026-11-19.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Образ снимался с карты целиком, поэтому `resize2fs` не нужен — размер ФС
уже совпадает. Проверка:

```bash
sudo e2fsck -fn /dev/sdX
sudo blkid /dev/sdX     # UUID должен совпасть с прежним
```

**Если система не грузится:** UART-консоль (`INSTALL_GUIDE.md` §7),
в barebox проверить, что `kernel2` на месте (`mtd6`), при необходимости
загрузиться с SD вручную. Ядро и `env` не изменялись, так что ломаться
там нечему.

**Если потерян SSH, но система жива:** вход по UART, `admin`/`lol`,
дальше — те же команды. Чаще всего это `AllowGroups` (§4) или
неподнявшийся `dhclient`.

---

## 9. Что осталось от исходного образа

Это не мусор, а рабочая часть BSP — удалять нельзя:

| Компонент | Зачем |
|---|---|
| `linux-bsp-nas5xx`, `-init`, `-boot` | `/etc/preinit`, `zy-*`, LED, кнопки, вентилятор, MCU |
| `linux-image-6.6.84+nas5xx` | модули и `/boot` текущего ядра |
| `/etc/rc.local` | `/dev/gpio`, кормление MCU, zram, LED, `mdadm --monitor` |
| `/etc/preinit` | `zy-hw-init`, `dhclient`, первый запуск |
| `nas_keep_alive.sh` | фидер `/dev/watchdog` |
| `/sbin/setLED`, `/sbin/buzzerc` | LED и зуммер (динамически слинкованы, после trixie работают) |

Все четыре пакета помечены `manual`, поэтому `apt autoremove` их не тронет.

---

## 10. Дальше

Следующий шаг проекта — собственный образ trixie с ядром 6.12 LTS,
авто-расширением ФС при первом старте, свежими SSH host keys и без
наследства OMV. Он публикуется отдельным репозиторием
`zyxel_nas520_debian_trixie`; этот репозиторий остаётся каноническим
руководством «со стока в Debian».

Скрипты, использованные здесь:

| Файл | Назначение |
|---|---|
| `tools/bullseye-cleanup.sh` | чистка bullseye перед апгрейдом |
| `tools/dist-upgrade.sh` | unattended `upgrade` + `full-upgrade` с логом |
| `tools/post-upgrade-check.sh` | проверка после каждого шага |
| `tools/omv-cleanup.sh` | остатки OMV, monit, folder2ram |
| `tools/postinstall.sh` | идемпотентные правки образа (watchdog, fancontrol) |
