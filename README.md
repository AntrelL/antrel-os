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
AGENTS.md                 контекст для агента: решения, правила, чек-лист после установки
flake.nix                 входы, конфигурация uiux-2680, команда установки (nix run)
install.sh                установка с live-флешки (с проверками разметки)
hosts/installer/          live-флешка: официальная GNOME-флешка с текстовым меню загрузки
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

Нужно: 40 ГБ нераспределённого места сразу после `C:` (сжатие тома в Windows), гибернация и быстрый
запуск Windows выключены (`powercfg /h off`), live-флешка из этого репозитория, интернет по кабелю.

**Флешка.** Официальная флешка NixOS на этой плате не загружается: её графическое меню загрузки
зависает, гасит экран или выкидывает в BIOS ([nixpkgs#427235](https://github.com/NixOS/nixpkgs/issues/427235)).
Своя флешка — та же GNOME-флешка, но с текстовым меню. Сборка на Windows через Docker Desktop
(PowerShell, в любой папке, например `Downloads`; долго, скачивается ~3 ГБ):

```powershell
docker run --rm -v "${PWD}:/out" nixos/nix sh -c 'nix --extra-experimental-features "nix-command flakes" build github:AntrelL/antrel-os#iso && cp -L result/iso/*.iso /out/'
```

Получится `nixos-*.iso` в этой папке. Записать на флешку через Rufus, режим **DD**. Загружаться
с пункта «UEFI: <флешка>».

В live-системе (GNOME) программы открываются клавишей Win и поиском по имени: **Console** — терминал,
**GParted** — разделы, **Firefox** — этот README.

1. **Раздел — мышкой, в GParted.**
   Выбрать NVMe-диск → правой кнопкой по серому блоку «не распределено» (~40 ГБ) между `C:` и Recovery →
   «Создать» → файловая система **btrfs**, метка **nixos** → «Добавить» → зелёная галка «Применить».
   Другие разделы не трогать.
2. **Установка — одна команда в терминале:**
   ```sh
   sudo nix --extra-experimental-features "nix-command flakes" run github:AntrelL/antrel-os
   ```
   Скрипт (`install.sh`) ничего не размечает и не форматирует. Он проверяет EFI-раздел Windows,
   единственный пустой btrfs-раздел `nixos` на 35–45 ГиБ на том же диске, показывает план и ждёт `yes`.
   Дальше: подтома, монтирование, клон репозитория в `/home/antrel/antrel-os`, `nixos-install`,
   пароль пользователя. Повторный запуск после сбоя безопасен.
3. `sudo reboot`, вынуть флешку.

## Первый запуск

1. В меню GRUB по умолчанию NixOS. На экране входа — пароль, заданный при установке.
2. **Терминал:** Win+Enter. Любая программа: нажать Win и начать вводить имя.
3. **VPN:** Win → `Happ` → добавить подписку (вставить ссылку из буфера) → подключиться; режим TUN
   пускает через VPN всю систему. Ссылку подписки заранее скопировать из Happ на Windows: в репозитории её
   нет. Если подписка ограничивает число устройств, Linux считается отдельным устройством.
4. **GitHub** (чтобы агент мог отправлять коммиты): в терминале `gh auth login`.
5. **Агент:** при включённом VPN
   ```sh
   cd ~/antrel-os && omp
   ```
   omp сам прочитает `AGENTS.md`: решения, правила и чек-лист первой загрузки. Первая просьба к нему:
   «пройди чек-лист после первой загрузки».

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
