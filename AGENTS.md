# antrel-os: контекст для агента

Этот файл читается агентом (omp) автоматически при запуске в `~/antrel-os`.
Описание системы, структура репозитория, горячие клавиши и установка — в `README.md`; здесь то, чего в README
нет: кто пользователь, как с ним работать, почему приняты решения и что делать дальше.

## Пользователь

- Antrel, пишет по-русски; отвечать по-русски, просто, без жаргона. Не эксперт в Linux.
- Цель: красивая, удобная, не захламляющаяся система вместо Windows. Windows остаётся рядом (dual-boot).
- **Решения обсуждаются по шагам.** Не забегать вперёд: большие изменения (новый слой системы, замена
  компонента, разметка диска) — только после явного согласия.
- Мелкие правки, исправления, ведение репозитория — на агенте без отдельного согласования.
- Предпочитает готовые решения написанию с нуля; дизайн — свой, не копия Windows/macOS.
- Агент отвечает за репозиторий целиком: коммиты, теги, README, этот файл.

## Главная обязанность: репозиторий = текущая система

Пользователь хочет переустановить систему одной командой и получить ту же самую. Поэтому всё, что меняется
в системе, должно оказаться в репозитории:

| Что изменилось | Куда записать |
|---|---|
| Поставили программу через dnf | `packages/dnf.txt` (и COPR в `packages/copr.txt`, если он новый) |
| Поставили программу с Flathub | `packages/flatpak.txt` |
| Поменяли системный файл в `/etc` (или другой вне `~`) | положить его в `system/` по тому же пути |
| Настройка программы в `~/.config` (мышь, терминал, оболочка…) | если папка уже в `links.txt` — просто коммит; если нет — `./track.sh ~/.config/<папка>` и коммит |
| Разовое действие, которое нельзя описать файлом | шаг в `setup.sh`, повторный запуск должен быть безопасен |

- Перед коммитом смотреть `git status` и `git diff`: окно настроек 43PR (Super+I), выбор обоев и тем, kitty
  и др. пишут прямо в репозиторий через ссылки (`home/.config/quickshell/state/`, `home/.local/state/43pr/`,
  `home/Pictures/Wallpapers/`). Коммитить осмысленными порциями, а не всё подряд.
- **Репозиторий публичный — личное не коммитить:** заметки боковой панели (`todo-state.json`) уже в
  `.gitignore`; новые файлы в `quickshell/state/` проверять глазами перед коммитом.
- **Секреты не трекать никогда:** `~/.config/gh`, `~/.config/happ` (там ссылка подписки VPN), профили
  браузера, ключи, токены, кэш. Перед `track.sh` проверить, что в папке нет секретов и мусора (кэши, логи —
  в `.gitignore` внутри этой папки).
- `sudo` агент не знает: команды с `sudo` (включая `sudo ~/antrel-os/setup.sh`) просит выполнить пользователя.

## Ключевые решения и почему

| Решение | Почему |
|---|---|
| Fedora Workstation, а не NixOS | NixOS: официальная флешка не грузится на этой X99 (графический GRUB, nixpkgs#427235), и пользователю не понравился декларативный подход. Arch/CachyOS сравнивали: выбрали Fedora — проверена на этом железе, сторонние репозитории (COPR) нельзя захватить, как пакеты AUR (волны вредоносных пакетов в AUR в 2026) |
| Workstation, а не Everything | ставится с флешки без зеркал (у пользователя были проблемы с зеркалами), даёт живую систему для проверки железа; GNOME — запасной рабочий стол |
| `fastestmirror=True` | в списке зеркал Fedora нет ни одного в Беларуси; без этого скачивание тянулось или требовало VPN. Жёстко прописанное зеркало отвергли: при его падении ломается всё |
| Hyprland из COPR `lionheartp/Hyprland` | пакет Fedora удалён из репозиториев («Fails to install»). Этот COPR указан в wiki Hyprland для Fedora и в документации Noctalia, исходники спеков открыты (github.com/LionHeartP/hyprlandRPM). Риск: ведёт один человек (форк брошенного `solopasha`). `except=kitty*,cliphist,qt6ct` — эти пакеты берутся из Fedora |
| Hyprland, конфиг на **Lua** | 0.57 читает только `hyprland.lua`; API — `hl.config`, `hl.bind`, `hl.dsp.*` (wiki.hypr.land) |
| Рабочий стол — форк [43PR/dotfiles](https://github.com/43PR/dotfiles) в `home/` | выбор пользователя по внешнему виду. Панель, меню, настройки — Quickshell (QML в `home/.config/quickshell`), темы — `home/.config/43pr` (`theme.py` + шаблоны, цвета через matugen). Проект одного автора, только под Arch (с AUR) — поэтому не его установщик, а свой `setup.sh` с пакетами Fedora. Заменил Dux Shell |
| Правки 43PR под Fedora помечены комментарием `antrel-os` | страница обновлений (`dnf` вместо `pacman`, кнопка UPDATE DESKTOP = `git pull` + `setup.sh`), языки OCR (`tesseract-langpack-*`), очистка кэша (убраны pacman/yay), пути плагинов zsh, браузер Firefox, раскладка us,ru. Правок — минимум: каждая усложняет перенос обновлений автора |
| Обновления 43PR — вручную | `43pr-upstream.txt` хранит коммит, с которого взят рабочий стол. Перенос: сравнить upstream между этим коммитом и новым (`git diff old new -- .config`), применить к `home/`, сохранить правки `antrel-os`, обновить `43pr-upstream.txt`, прогнать `setup.sh` в контейнере. Только по просьбе пользователя |
| Генерируемые файлы темы — в `.gitignore` | `theme.py` пишет их из шаблонов и `state.json` (оба в git); `setup.sh` запускает `theme.py apply` |
| uwsm, сессия `hyprland-uwsm.desktop` из `system/` | Hyprland как systemd-сессия, получает переменные из `environment.d`. COPR не ставит файл сессии uwsm, поэтому он в `system/usr/share/wayland-sessions/` |
| Экран входа — GDM (из Workstation) | надёжен с NVIDIA, умеет выбирать сессию; блокировка экрана — hyprlock (Super+Tab) |
| zsh, Thunar, бинды 43PR | выбор пользователя («как у 43PR»); бинды меняются в Super+I → Keybinds |
| Vesktop с Flathub (`dev.vencord.Vesktop`, verified) | вместо Discord; публикует сам Vencord, обновляется через Flatpak. Значок — стандартный Discord (официальный, из карточки Discord Inc. на Flathub): `antrel-discord.png` в `~/.local/share/icons/hicolor`, своё имя — чтобы Papirus не подменил; ярлык меню переписывает `setup.sh`; значки в трее — `userAssets` Vesktop (`tray`, `trayUnread` с красной точкой). Flatpak видит только свою папку, поэтому `setup.sh` даёт ему доступ к `home/.var/app/dev.vencord.Vesktop` в репозитории (`flatpak override`), иначе ссылки не работают |
| Источники: Fedora → RPM Fusion → Flathub (verified) → сами разработчики → COPR | пользователь просил самые проверенные источники. Не из пакетов: Happ (`.rpm` производителя), Nerd Fonts (релизы ryanoasis), zsh-autocomplete (git автора), papirus-folders (скрипт PapirusDevelopmentTeam), omp. `power-profiles-daemon` не ставим: в Workstation `tuned-ppd` с тем же D-Bus API |
| NVIDIA: `akmod-nvidia` (RPM Fusion) | RPM Fusion по умолчанию собирает открытые модули — то, что нужно для RTX 3070. Если «Frankenstein» с ними не работает — проприетарный вариант описан в rpmfusion.org/Howto/NVIDIA («Kernel Open») |
| `scx_bpfland` через `scx_loader` (COPR `bieszczaders/kernel-cachyos-addons`, только `scx-scheds scx-tools`) | на Fedora+GNOME раньше лагал интерфейс под нагрузкой (Xeon с медленными ядрами). Ядро Fedora поддерживает sched_ext; остальной COPR — тюнинг CachyOS, он отрезан `only=` в `packages/copr.txt` |
| Вес CPU сессии (`user-<uid>.slice`, пишет `setup.sh`) | сессия пользователя важнее фоновых служб |
| Шрифты: subpixel RGB, hinting slight, stem darkening, GTK4 `font-rendering=manual` | пользователя раздражали тонкие/мыльные шрифты Linux. Следующий шаг при мыле — `hintfull` в `fonts.conf`; подбирать на живом мониторе |
| Happ — официальный `.rpm` производителя (последний релиз), запуск через XWayland | VPN (Беларусь): без него не работают сервисы моделей для omp. Встроенный Qt Wayland в Happ падал на Hyprland (на NixOS); `setup.sh` делает копию ярлыка с `QT_QPA_PLATFORM=xcb` |
| Настройки — ссылками из `home/` (`links.txt`, `track.sh`) | правки из окон настроек программ сразу попадают в git; ссылки на целые папки, а не на файлы: программы, сохраняющие файл через переименование, не рвут ссылку |
| ffmpeg из RPM Fusion (`dnf swap ffmpeg-free ffmpeg`) | полный набор кодеков для mpv, живых обоев, записи экрана |
| Репозиторий публичный | установка одной командой без входа в GitHub. Секретов в репозитории нет и быть не должно |

## Правила работы с репозиторием

- Conventional Commits (`feat(hyprland): …`, `fix(audio): …`), один коммит — одно логическое изменение,
  тело коммита — список изменений.
- `setup.sh` после правки: `shellcheck setup.sh track.sh`; поведение — прогон в контейнере `fedora:45`
  (пользователь с uid 1000 и sudo, `yes yes | sudo bash setup.sh`, затем повторный прогон — он должен
  пройти без ошибок и ничего не сломать).
- Ошибки конфига Hyprland: `hyprctl configerrors`; перечитать конфиг — `hyprctl reload`.
- Стабильные состояния — теги `vX.Y`. `v0.1` — первая удачная установка (ещё не поставлен).
- `nixos-archive` — последнее состояние на NixOS, для справки.

## Состояние на момент установки

`setup.sh` проверен в контейнере Fedora 45: репозитории подключаются, все пакеты находятся и ставятся,
модуль NVIDIA собирается, повторный запуск проходит. **На железе не проверено ничего**: ни загрузка
Hyprland, ни драйвер на этой видеокарте, ни экран входа — это задача первой загрузки.

## Чек-лист после первой загрузки

1. Видеокарта: `lspci -k | grep -EA3 'VGA|3D|Display'` → драйвер `nvidia`; `nvidia-smi` работает.
2. Сессия: `echo $XDG_CURRENT_DESKTOP` → `Hyprland`; панель 43PR на месте (`pgrep -x qs`);
   `hyprctl configerrors` — пусто. Super+I открывает настройки; страница Updates показывает число обновлений dnf.
3. Мониторы: оба на родном разрешении, масштаб 1; расставить слева/справа (`hl.monitor` по именам выходов
   из `hyprctl monitors`).
4. Windows в меню GRUB. Если нет: `sudo grub2-mkconfig -o /boot/grub2/grub.cfg` (os-prober).
5. `gh auth login`, затем `git push` из `~/antrel-os` работает.
6. 43PR: тема применена (цвета kitty/rofi/панели совпадают), Super+W меняет обои, Super+X переключает us/ru,
   Delete/Shift+Delete — скриншоты, Shift+F12 — OCR (русский язык включить в Super+I → Keybinds).
   Проверить `git status`: что пишут настройки в `quickshell/state/`, нет ли там личного.
7. Vesktop: войти, проверить значок Discord в меню, на панели и в трее; затем взять под git **только** настройки:
   `./track.sh ~/.var/app/dev.vencord.Vesktop/config/vesktop/settings.json`, `…/settings` (Vencord) и
   `…/themes`, если есть. Папку `sessionData` (вход в Discord) не трекать никогда.
8. Happ: запускается (через XWayland), подписка импортируется, TUN-режим поднимает `tun0`; если трафик не
   идёт — проверить firewalld (`tun0` в зону `trusted`) и `rp_filter`.
9. Отзывчивость: `systemctl status scx_loader`, `scxctl get` → `scx_bpfland`; нагрузка
   `stress-ng --cpu 28 -t 60` (пакет `stress-ng`) и одновременно двигать окна — рывков быть не должно.
10. Шрифты: сравнить с Windows на том же мониторе, подстроить hinting.
11. Звук: MiniFuse 1 выбирается выходом по умолчанию (Super+I → Audio или pavucontrol).
12. Чувствительность мыши (Super+I → Input), мониторы (Super+I → Display) — подстроить вместе с пользователем
    и закоммитить получившиеся файлы в `quickshell/state/` и `hypr/monitors.lua`.
13. Спросить, удобны ли бинды 43PR (пользователь раньше не пользовался тайлинговыми оконными менеджерами).
14. Всё работает → тег `v0.1`.

## Отложено (обсудить с пользователем, когда дойдёт очередь)

- Экран входа в стиле рабочего стола (вместо GDM).
- Программы с Windows: Unity Hub (главное; официальный RPM-репозиторий Unity, docs.unity.com/hub), Telegram,
  Steam, Blender, Krita, VS Code и др.; замены для Windows-only (КОМПАС, Equalizer APO → EasyEffects,
  Lossless Scaling → lsfg-vk, Wallpaper Engine → linux-wallpaperengine).
- Снимки btrfs с откатом из меню загрузки (snapper + grub-btrfs).
- Удалить GNOME, если запасной рабочий стол не понадобится.
- В Windows отключена защита системы (точки восстановления) ради сжатия диска; можно включить обратно.
