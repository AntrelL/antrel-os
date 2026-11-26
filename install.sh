#!/usr/bin/env bash
# Installs antrel-os (uiux-2680) from the NixOS live ISO.
#
# Before running: in GParted create ONE btrfs partition labelled "nixos" in the
# free space after C:. This script never partitions or formats anything: it
# only checks that layout, creates btrfs subvolumes on the "nixos" partition,
# mounts everything, clones the repository and runs nixos-install from it.
#
# Usage on the live ISO:
#   sudo nix --extra-experimental-features "nix-command flakes" run github:AntrelL/antrel-os
set -euo pipefail

readonly HOST=uiux-2680
readonly USER_NAME=antrel
readonly ESP_UUID=0041-D5AC
readonly LABEL=nixos
readonly MIN_GIB=35
readonly MAX_GIB=45
readonly SUBVOLS=(@ @home @nix)
readonly MNT=/mnt

readonly REPO_URL=https://github.com/AntrelL/antrel-os

die() { printf '\n\e[31mОШИБКА:\e[0m %s\n' "$*" >&2; exit 1; }
ok() { printf '  \e[32m✓\e[0m %s\n' "$*"; }
step() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

probe=""
cleanup() {
  if [[ -n "$probe" ]]; then
    umount "$probe" 2>/dev/null || true
    rmdir "$probe" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- checks ---
step "Проверки (ничего не меняется)"

[[ $EUID -eq 0 ]] || die "запустите через sudo"

curl -fsS --max-time 15 -o /dev/null https://cache.nixos.org/nix-cache-info ||
  die "нет интернета (cache.nixos.org недоступен)"
ok "интернет есть"

git ls-remote --exit-code "$REPO_URL" HEAD >/dev/null || die "репозиторий $REPO_URL недоступен"
ok "репозиторий доступен: $REPO_URL"

esp=$(blkid -U "$ESP_UUID" || true)
[[ -n "$esp" ]] || die "EFI-раздел Windows (UUID $ESP_UUID) не найден"
[[ $(blkid -o value -s TYPE "$esp") == vfat ]] || die "$esp не FAT32"
probe=$(mktemp -d)
mount -o ro "$esp" "$probe"
[[ -f "$probe/EFI/Microsoft/Boot/bootmgfw.efi" ]] || die "на $esp нет загрузчика Windows"
umount "$probe"
ok "EFI-раздел Windows: $esp (загрузчик Windows на месте)"

mapfile -t parts < <(blkid -t "LABEL=$LABEL" -o device || true)
((${#parts[@]} == 1)) || die "нужен ровно один раздел с меткой '$LABEL', найдено: ${#parts[@]}"
root=${parts[0]}
[[ $(blkid -o value -s TYPE "$root") == btrfs ]] || die "$root не btrfs: в GParted выберите файловую систему btrfs"

size_gib=$(($(lsblk -bndo SIZE "$root") / 1024 ** 3))
((size_gib >= MIN_GIB && size_gib <= MAX_GIB)) ||
  die "$root размером ${size_gib} ГиБ, ожидалось ${MIN_GIB}–${MAX_GIB}: это точно тот раздел?"

disk_root=$(lsblk -ndo PKNAME "$root")
disk_esp=$(lsblk -ndo PKNAME "$esp")
[[ -n "$disk_root" ]] || die "не удалось определить диск, на котором лежит $root"
[[ "$disk_root" == "$disk_esp" ]] || die "$root на /dev/$disk_root, а EFI-раздел на /dev/$disk_esp: раздел должен быть на диске с Windows"
ok "раздел NixOS: $root, btrfs, ${size_gib} ГиБ, диск /dev/$disk_root"

if findmnt -rno TARGET "$root" >/dev/null || mountpoint -q "$MNT"; then
  die "$root или $MNT уже смонтированы. Выполните: sudo umount -R $MNT"
fi

mount "$root" "$probe"
mapfile -t existing < <(ls -A "$probe")
umount "$probe"
for entry in "${existing[@]}"; do
  [[ " ${SUBVOLS[*]} " == *" $entry "* ]] ||
    die "на $root уже есть данные ('$entry'). Раздел должен быть пустым: пересоздайте его в GParted"
done
ok "раздел пустой${existing[*]:+ (подтома от прошлой попытки: ${existing[*]})}"

# --------------------------------------------------------------- confirm ---
cat <<EOF

Будет сделано:
  1. на $root созданы подтома btrfs: ${SUBVOLS[*]}
  2. $root смонтирован в $MNT, EFI-раздел $esp в $MNT/boot/efi (без форматирования)
  3. репозиторий склонирован в $MNT/home/$USER_NAME/antrel-os
  4. установлена система $HOST (GRUB, пункт «Windows 11» в меню загрузки)
Windows и её разделы не меняются, кроме добавления GRUB на EFI-раздел.

EOF
read -rp "Продолжить? Введите yes: " answer
[[ "$answer" == yes ]] || die "отменено, ничего не изменено"

# ---------------------------------------------------------------- install ---
step "Подтома btrfs"
mount "$root" "$probe"
for sv in "${SUBVOLS[@]}"; do
  [[ -d "$probe/$sv" ]] || btrfs subvolume create "$probe/$sv"
done
umount "$probe"
ok "подтома: ${SUBVOLS[*]}"

step "Монтирование"
opts=compress=zstd,noatime
mount -o "subvol=@,$opts" "$root" "$MNT"
mkdir -p "$MNT/home" "$MNT/nix" "$MNT/boot/efi"
mount -o "subvol=@home,$opts" "$root" "$MNT/home"
mount -o "subvol=@nix,$opts" "$root" "$MNT/nix"
mount "$esp" "$MNT/boot/efi"
findmnt -R "$MNT"

step "Репозиторий"
dest="$MNT/home/$USER_NAME/antrel-os"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
git clone --quiet "$REPO_URL" "$dest"
ok "$dest ($(git -C "$dest" log -1 --format='%h %s'))"
# Kept for comparison with hosts/$HOST/hardware.nix after the first boot.
nixos-generate-config --root "$MNT" --show-hardware-config >"$MNT/home/$USER_NAME/hardware-generated.nix"
ok "сгенерированный hardware-config: $MNT/home/$USER_NAME/hardware-generated.nix"

step "nixos-install (долго: скачивание ~3.6 ГБ, сборка omp и драйвера NVIDIA)"
# Builds run in this process; keep their temp files on disk, not in the RAM-backed /tmp of the live ISO.
export TMPDIR="$MNT/var/tmp/nixos-install"
mkdir -p "$TMPDIR"
nixos-install \
  --option experimental-features "nix-command flakes" \
  --no-root-passwd \
  --flake "$dest#$HOST"
rm -rf "$TMPDIR"

step "Пароль пользователя $USER_NAME"
until nixos-enter --root "$MNT" -c "passwd $USER_NAME"; do
  echo "Пароль не задан, попробуйте ещё раз."
done
nixos-enter --root "$MNT" -c "chown -R $USER_NAME:users /home/$USER_NAME"

step "Готово"
cat <<EOF
Перезагрузитесь и выньте флешку: sudo reboot
В меню GRUB по умолчанию NixOS; Windows — пункт «Windows 11».
EOF
