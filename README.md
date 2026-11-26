# antrel-os

Личная система на базе NixOS. Вся система описана в этом репозитории: из него она
ставится с нуля и обновляется. Ручных изменений «мимо конфига» нет.

## Железо

| Компонент | Модель |
|---|---|
| Плата | HUANANZHI X99-QD4 (UEFI, Secure Boot выключен) |
| CPU | Intel Xeon E5-2680 v4, 14 ядер / 28 потоков |
| RAM | 16 ГБ |
| GPU | NVIDIA GeForce RTX 3070 «Frankenstein» (мобильный GA104) |
| Диск | NVMe 477 ГБ, общий с Windows 11 |
| Звук | Arturia MiniFuse 1 + встроенный |
| Сеть | Realtek GbE |
| Мониторы | 1920×1080 + 1280×1024 |

## Диск (dual-boot с Windows 11)

| Раздел | Назначение |
|---|---|
| ESP Windows, FAT32, 196 МБ, UUID `0041-D5AC` | общий; NixOS кладёт туда только GRUB |
| `C:` NTFS | Windows |
| btrfs, метка `nixos` | NixOS: подтома `@` (/), `@home`, `@nix` |
| Recovery | Windows |

Загрузчик: GRUB. Ядра лежат в `/boot` на btrfs: ESP слишком мал для поколений NixOS.

## Правила ведения репозитория

- Один коммит = одно логическое изменение.
- Сообщения в формате [Conventional Commits](https://www.conventionalcommits.org/):
  `тип(область): описание`, например `feat(hyprland): add blur`, `fix(audio): MiniFuse default output`.
  Типы: `feat`, `fix`, `perf`, `refactor`, `chore`, `docs`.
- Каждый коммит собирается: сломанных состояний в истории нет.
- Обновление входов (`flake.lock`) — всегда отдельный коммит `chore(flake): update ...`.
- Стабильные состояния помечаются тегами `vX.Y`.
- Секреты (пароли, токены, ключи VPN) в репозиторий не попадают.
