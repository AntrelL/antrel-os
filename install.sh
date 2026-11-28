#!/usr/bin/env bash
# antrel-os installer. Run it on the Arch Linux live USB, on the computer with Windows:
#   curl -fsSL https://raw.githubusercontent.com/AntrelL/antrel-os/main/install.sh | bash
#
# What it does, after showing the plan and waiting for "yes":
#   - creates the antrel-os partition in the largest free space of the Windows disk (or, when an antrel-os
#     partition already exists, formats that one again: reinstall);
#   - btrfs with subvolumes @ and @home; kernels stay on it, the EFI partition only gets GRUB (it is Windows' and small);
#   - installs Arch, creates the user, clones this repository into ~/antrel-os and runs setup.sh inside;
#   - GRUB with a boot menu entry for Windows.
# Never touched: Windows, its partitions, any other partition. Free space is made in Windows beforehand.
set -euo pipefail

readonly REPO_URL=https://github.com/AntrelL/antrel-os
readonly USER_NAME=antrel
readonly LABEL=antrel-os
readonly MIN_GIB=30
readonly ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
readonly MNT=/mnt
readonly BTRFS_OPTS=noatime,compress=zstd:1
# Arch mirrors nearest to Belarus (reflector picks the fastest of them).
readonly MIRROR_COUNTRIES=BY,LT,LV,PL,DE,FI,SE

die() { printf '\n\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*" >&2; }
ok() { printf '  \e[32m✓\e[0m %s\n' "$*"; }
step() { printf '\n\e[1m== %s\e[0m\n' "$*"; }
gib() { echo $(($1 / 1024 / 1024 / 1024)); }

# stdin is the script itself (curl | bash): questions go to the terminal.
ask() { read -r "$@" </dev/tty; }

checks() {
  step "Checks (nothing is changed)"
  [[ $EUID -eq 0 ]] || die "run it as root (the live USB logs in as root)"
  [[ -d /sys/firmware/efi/efivars ]] || die "the USB stick was not booted in UEFI mode: pick 'UEFI: <stick>' in the boot menu"
  command -v pacstrap >/dev/null || die "this is not the Arch Linux live USB"
  curl -fsS --max-time 15 -o /dev/null "$REPO_URL" || die "no internet ($REPO_URL is unreachable): plug in the cable"
  ok "UEFI, Arch live USB, internet"
  if mountpoint -q "$MNT"; then
    umount -R "$MNT" || die "$MNT is in use"
  fi
}

# The EFI partition holding Windows Boot Manager; the disk it is on is where antrel-os goes.
find_windows() {
  local p tmp
  local -a found=()
  tmp=$(mktemp -d)
  while read -r p; do
    if mount -o ro "$p" "$tmp" 2>/dev/null; then
      [[ -f $tmp/EFI/Microsoft/Boot/bootmgfw.efi ]] && found+=("$p")
      umount "$tmp"
    fi
  done < <(lsblk -rnpo NAME,PARTTYPE | awk -v t="$ESP_TYPE" 'tolower($2) == t { print $1 }')
  rmdir "$tmp"
  ((${#found[@]} == 1)) || die "expected one EFI partition with Windows Boot Manager, found ${#found[@]}"
  esp=${found[0]}
  disk=$(lsblk -npo PKNAME "$esp")
  ok "Windows EFI partition $esp on $disk ($(lsblk -dno MODEL "$disk" | xargs))"
}

# Reinstall onto the existing antrel-os partition, or a new one over the largest free block of the disk.
find_target() {
  local -a existing
  mapfile -t existing < <(lsblk -rnpo NAME,PARTLABEL "$disk" | awk -v l="$LABEL" '$2 == l { print $1 }')
  if ((${#existing[@]} > 1)); then
    die "more than one partition named $LABEL on $disk"
  elif ((${#existing[@]} == 1)); then
    target=${existing[0]}
    size=$(lsblk -bndo SIZE "$target")
    ok "existing $LABEL partition $target, $(gib "$size") GiB: will be formatted again"
  else
    local ss
    ss=$(blockdev --getss "$disk")
    first=$(sgdisk -f "$disk" | tail -n1)
    last=$(sgdisk -E "$disk" | tail -n1)
    [[ $first =~ ^[0-9]+$ && $last =~ ^[0-9]+$ && $last -gt $first ]] || die "no free space on $disk"
    target=""
    size=$(((last - first + 1) * ss))
    ok "largest free space on $disk: $(gib "$size") GiB"
  fi
  (($(gib "$size") >= MIN_GIB)) || die "$(gib "$size") GiB is too little, need at least $MIN_GIB GiB.
In Windows, Disk Management: delete the old Linux partitions (or shrink C:) so there is free space after C:."
}

confirm() {
  step "Disk now"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$disk"
  cat <<EOF

Plan:
  1. $([[ -n $target ]] && echo "format $target ($LABEL) again" || echo "new partition '$LABEL' in the free $(gib "$size") GiB of $disk"): btrfs, everything on it is lost
  2. EFI partition $esp (Windows'): GRUB is added; leftovers of an old Fedora (EFI/fedora) are removed
  3. Arch Linux, user '$USER_NAME', this repository in /home/$USER_NAME/antrel-os, setup.sh
  4. boot menu: antrel-os and Windows
Windows and all other partitions are not touched.

EOF
  local answer
  ask -p "Continue? Type yes: " answer
  [[ $answer == yes ]] || die "cancelled, nothing changed"

  local again
  while true; do
    ask -s -p "Password for $USER_NAME (also for sudo): " password
    echo
    ask -s -p "Same password again: " again
    echo
    [[ -n $password && $password == "$again" ]] && break
    warn "empty or different, once more"
  done
}

mirrors() {
  step "Mirrors"
  # The live USB runs reflector once at boot; wait for it instead of racing it.
  systemctl stop reflector.service 2>/dev/null || true
  if reflector --protocol https --country "$MIRROR_COUNTRIES" --age 24 --fastest 10 \
    --save /etc/pacman.d/mirrorlist; then
    ok "fastest mirrors near Belarus"
  else
    warn "reflector failed: keeping the live USB's mirror list"
  fi
  pacman -Sy --noconfirm --needed archlinux-keyring
  ok "package signing keys up to date"
}

partition() {
  step "Partition"
  if [[ -z $target ]]; then
    # 8304: Linux x86-64 root.
    sgdisk -n "0:$first:$last" -t 0:8304 -c "0:$LABEL" "$disk"
    partprobe "$disk"
    udevadm settle
    target=$(lsblk -rnpo NAME,PARTLABEL "$disk" | awk -v l="$LABEL" '$2 == l { print $1 }')
    [[ -n $target && -b $target ]] || die "the new partition did not show up"
    ok "created $target"
  fi
  mkfs.btrfs -q -f -L "$LABEL" "$target"
  mount "$target" "$MNT"
  btrfs -q subvolume create "$MNT/@"
  btrfs -q subvolume create "$MNT/@home"
  umount "$MNT"
  mount -o "$BTRFS_OPTS,subvol=@" "$target" "$MNT"
  mkdir -p "$MNT/home" "$MNT/efi"
  mount -o "$BTRFS_OPTS,subvol=@home" "$target" "$MNT/home"
  mount "$esp" "$MNT/efi"
  ok "btrfs on $target (@ → /, @home → /home), EFI partition → /efi"
}

# Fedora's boot files and boot entry, once Fedora itself is gone. The EFI partition is only ~200 MB.
clean_esp() {
  local n
  if [[ -d $MNT/efi/EFI/fedora ]] && ! lsblk -rno LABEL "$disk" | grep -qx fedora; then
    rm -rf "$MNT/efi/EFI/fedora"
    ok "removed EFI/fedora"
  fi
  while read -r n; do
    efibootmgr -q -b "$n" -B && ok "removed boot entry Fedora ($n)"
  done < <(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Fedora.*/\1/p')
  ok "EFI partition: $(df -h --output=avail "$MNT/efi" | tail -n1 | xargs) free"
}

base() {
  step "Base system"
  pacstrap -K "$MNT" base sudo git
  genfstab -U "$MNT" >>"$MNT/etc/fstab"
  ok "base system, /etc/fstab"

  arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$USER_NAME"
  printf '%s:%s\n' "$USER_NAME" "$password" | arch-chroot "$MNT" chpasswd
  arch-chroot "$MNT" passwd -q -l root
  ok "user $USER_NAME (root login locked: use sudo)"

  arch-chroot "$MNT" runuser -u "$USER_NAME" -- env HOME="/home/$USER_NAME" \
    git clone -q "$REPO_URL" "/home/$USER_NAME/antrel-os"
  ok "repository in /home/$USER_NAME/antrel-os"
}

setup() {
  step "setup.sh"
  # setup.sh is meant to be run through sudo by the user; SUDO_USER tells it who that is.
  if arch-chroot "$MNT" env SUDO_USER="$USER_NAME" bash "/home/$USER_NAME/antrel-os/setup.sh" --yes; then
    setup_ok=1
  else
    setup_ok=0
  fi
  [[ -f $MNT/boot/vmlinuz-linux && -f $MNT/boot/initramfs-linux.img ]] ||
    die "the kernel is not installed (see the errors above): nothing to boot. Run this installer again."
}

bootloader() {
  step "Boot menu"
  arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=antrel-os
  [[ -f $MNT/boot/grub/grub.cfg ]] || arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
  ok "GRUB on the EFI partition, first in the boot order"
}

finish() {
  # pacstrap -K leaves a gpg-agent for the new system's keyring running here: it keeps $MNT busy.
  gpgconf --homedir "$MNT/etc/pacman.d/gnupg" --kill all || true
  sleep 1
  umount -R "$MNT"
  step "Done"
  if ((setup_ok == 0)); then
    warn "some parts of setup.sh failed (listed above). After the first login: sudo ~/antrel-os/setup.sh"
  fi
  cat <<EOF
Next: reboot, pull out the USB stick (command: reboot).
In the menu pick antrel-os (Windows is there too). Log in as $USER_NAME on the login screen: KDE Plasma starts.
EOF
}

main() {
  checks
  find_windows
  find_target
  confirm
  mirrors
  partition
  clean_esp
  base
  setup
  bootloader
  finish
}

# Everything runs from here, so a half-downloaded `curl | bash` never executes a partial script.
main "$@"
