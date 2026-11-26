# antrel-os

Личная система на базе NixOS. Вся система описана в этом репозитории: из него она
ставится с нуля и обновляется. Ручных изменений «мимо конфига» нет.

## Состав

| Слой | Что |
|---|---|
| Основа | NixOS unstable, flake, Home Manager |
| Загрузка | GRUB, пункт «Windows 11» в меню |
| Видео | NVIDIA, открытые модули ядра, VA-API |
| Звук | PipeWire |
| Отзывчивость | `scx_bpfland`, сборки Nix с приоритетом idle, вес CPU сессии |
| Рабочий стол | Hyprland (UWSM), Dux Shell (бывш. DankMaterialShell) + его экран входа |
| Шрифты | Inter, JetBrains Mono Nerd Font; субпиксельное сглаживание, хинтинг, stem darkening |
| Программы | Firefox, kitty, Nautilus, Starship, Happ (VPN), omp |

## Структура

```
flake.nix                 входы и единственная конфигурация uiux-2680
hosts/uiux-2680/          имя машины, загрузка Windows, железо и разделы
modules/                  системные модули по темам (core, boot, nvidia, audio,
                          performance, desktop, fonts, happ)
pkgs/happ/                сборка Happ из .deb производителя
home/antrel/              Home Manager: программы пользователя, hyprland.lua
docs/design/              визуальные референсы
```

## Горячие клавиши

Повторяют Windows, где есть аналог. Полный список: `home/antrel/hyprland.lua`.

| Клавиши | Действие |
|---|---|
| Win / Win+Space | лаунчер |
| Win+Enter / Win+E / Win+B | терминал / файлы / браузер |
| Win+L | блокировка |
| Win+V | история буфера обмена |
| Win+I / Win+A / Win+N | настройки оболочки / быстрые настройки / уведомления |
| Win+Tab | обзор рабочих столов |
| Win+X | меню питания |
| Alt+Tab | следующее окно |
| Alt+F4 / Win+Q | закрыть окно |
| Win+F / Win+Shift+F | полный экран / плавающее окно |
| Win+стрелки / Win+Shift+стрелки | фокус / переместить окно (и между мониторами) |
| Win+1…0 / Win+Shift+1…0 | рабочий стол / отправить окно на рабочий стол |
| Win+Shift+S / Print | скриншот области / экрана в буфер |
| Ctrl+Shift+Esc | список процессов |
| Alt+Shift | раскладка us/ru |

## Железо

| Компонент | Модель |
|---|---|
| Плата | HUANANZHI X99-QD4 (UEFI, Secure Boot выключен) |
| CPU | Intel Xeon E5-2680 v4, 14 ядер / 28 потоков |
| RAM | 16 ГБ |
| GPU | NVIDIA GeForce RTX 3070 «Frankenstein» (мобильный GA104); работает с драйвером NVIDIA — проверено на Fedora (akmod-nvidia) |
| Диск | NVMe 477 ГБ, общий с Windows 11 |
| Звук | Arturia MiniFuse 1 + встроенный |
| Сеть | Realtek GbE |
| Мониторы | 1920×1080 + 1280×1024 |

## Диск (dual-boot с Windows 11)

| Раздел | Назначение |
|---|---|
| ESP Windows, FAT32, 196 МБ, UUID `0041-D5AC` | общий; NixOS кладёт туда только GRUB |
| `C:` NTFS | Windows |
| btrfs, метка `nixos`, 40 ГБ | NixOS: подтома `@` (/), `@home`, `@nix` |
| Recovery | Windows |

Загрузчик: GRUB. Ядра лежат в `/boot` на btrfs: ESP слишком мал для поколений NixOS.

## Установка с нуля

С live-флешки NixOS, от root. Нераспределённое место после `C:` должно уже быть (сжатие тома в Windows).
Быстрый запуск Windows и гибернация выключены (`powercfg /h off`).

```sh
lsblk -f                                   # найти NVMe и свободный промежуток
sgdisk -n 0:0:0 -t 0:8300 -c 0:nixos /dev/nvme0n1   # раздел в самом большом свободном промежутке
lsblk -f                                   # запомнить номер нового раздела: /dev/nvme0n1pN
mkfs.btrfs -L nixos /dev/nvme0n1pN

mount /dev/disk/by-label/nixos /mnt
btrfs subvolume create /mnt/@ /mnt/@home /mnt/@nix
umount /mnt
opts=compress=zstd,noatime
mount -o subvol=@,$opts /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/home /mnt/nix /mnt/boot/efi
mount -o subvol=@home,$opts /dev/disk/by-label/nixos /mnt/home
mount -o subvol=@nix,$opts /dev/disk/by-label/nixos /mnt/nix
mount /dev/disk/by-uuid/0041-D5AC /mnt/boot/efi

nixos-generate-config --root /mnt --show-hardware-config   # сверить с hosts/uiux-2680/hardware.nix

nix-shell -p gh git --run 'gh auth login && gh repo clone AntrelL/antrel-os /mnt/home/antrel/antrel-os'
nixos-install --flake /mnt/home/antrel/antrel-os#uiux-2680
nixos-enter --root /mnt -c 'passwd antrel && chown -R antrel:users /home/antrel'
reboot
```

## Ежедневная работа

```sh
cd ~/antrel-os
sudo nixos-rebuild switch --flake .#uiux-2680   # применить изменения конфига
nix flake update && sudo nixos-rebuild switch --flake .#uiux-2680   # обновить систему
sudo nixos-rebuild switch --rollback            # откатиться на прошлую сборку
```

Если система не загружается: в меню GRUB выбрать предыдущую сборку в «NixOS - All configurations».

## Правила ведения репозитория

- Один коммит = одно логическое изменение.
- Сообщения в формате [Conventional Commits](https://www.conventionalcommits.org/):
  `тип(область): описание`, например `feat(hyprland): add blur`, `fix(audio): MiniFuse default output`.
  Типы: `feat`, `fix`, `perf`, `refactor`, `chore`, `docs`.
- Каждый коммит собирается: сломанных состояний в истории нет.
- Обновление входов (`flake.lock`) — всегда отдельный коммит `chore(flake): update ...`.
- Стабильные состояния помечаются тегами `vX.Y`.
- Секреты (пароли, токены, ключи VPN) в репозиторий не попадают.
