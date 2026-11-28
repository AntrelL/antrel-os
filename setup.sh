#!/usr/bin/env bash
# shellcheck disable=SC2088 # "~/…" in messages is text for the user, not a path to expand.
# antrel-os: makes this Arch Linux system match the repository: packages, system files, user settings.
#
# install.sh runs it once inside the freshly installed system. Later, after changing packages/, system/ or links.txt:
#   sudo ~/antrel-os/setup.sh
#
# Safe to re-run: every step either checks first or overwrites with the repository's version.
# One failure does not stop the rest: each part runs on its own, failed parts are listed at the end.
set -euo pipefail

# Happ (VPN) from its vendor, who publishes a pacman package next to the .deb/.rpm. Not in Arch's repositories.
readonly HAPP_PKG=https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.pkg.tar.zst
readonly HAPP_RELEASE_API=https://api.github.com/repos/Happ-proxy/happ-desktop/releases/latest
readonly TIMEZONE=Europe/Minsk

die() { printf '\n\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
fail() { printf '  \e[31m✗\e[0m %s\n' "$*" >&2; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*" >&2; }
ok() { printf '  \e[32m✓\e[0m %s\n' "$*"; }
step() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

# Non-comment, non-empty lines of a list file.
list() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1" || true; }

as_user() { sudo -u "$user" -H "$@"; }

in_container() { systemd-detect-virt --container --quiet; }

# Runs "$@" in a subshell that stops at its first failing command, and never stops the caller: the exit code
# is left in $rc. Bash ignores `set -e` inside anything tested by if/||/&&, hence this shape.
isolated() {
  set +e
  (
    set -e
    "$@"
  )
  rc=$?
  set -e
}

# Names of the parts that failed, for the summary at the end.
failed=()

# One part of the setup. A failure is reported and remembered; the remaining parts still run.
part() {
  local name=$1
  shift
  step "$name"
  isolated "$@"
  if ((rc)); then
    failed+=("$name")
    fail "$name: failed, moving on"
  fi
}

# One item inside a part (a service, a link…): a failure is reported, the part goes on with the next item
# and fails at the end (`return "$item_failed"`).
item_failed=0
item() {
  local name=$1
  shift
  isolated "$@"
  if ((rc)); then
    item_failed=1
    fail "$name"
  fi
}

checks() {
  step "Checks (nothing is changed)"
  # shellcheck source=/dev/null
  . /etc/os-release
  [[ $ID == arch ]] || die "this is not Arch Linux: $PRETTY_NAME"
  ok "$PRETTY_NAME"
  curl -fsS --max-time 15 -o /dev/null https://github.com || die "no internet (github.com is unreachable)"
  ok "internet works"
  uid=$(id -u "$user")
  ok "user $user (uid $uid), repository $repo"
}

confirm() {
  cat <<EOF

Plan:
  1. system update and the packages from packages/pacman.txt (official Arch repositories only)
  2. Happ (VPN) from its vendor
  3. system files from system/, boot menu with Windows, services
  4. settings from home/ linked into $home (list: links.txt); omp agent
Windows and disk partitions are not touched.
If a part fails, the rest still runs; failed parts are listed at the end.

EOF
  local answer
  read -rp "Continue? Type yes: " answer
  [[ $answer == yes ]] || die "cancelled, nothing changed"
}

# A name pacman can't find fails the whole transaction. Then install one by one, so only the broken ones are left
# out, and name them.
packages() {
  local -a pkgs missing=()
  local p
  mapfile -t pkgs < <(list "$repo/packages/pacman.txt")
  if ! pacman -Syu --needed --noconfirm "${pkgs[@]}"; then
    warn "installing everything at once failed; installing one by one"
    for p in "${pkgs[@]}"; do
      pacman -Q "$p" >/dev/null 2>&1 || pacman -S --needed --noconfirm "$p" || true
    done
  fi
  for p in "${pkgs[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  ((${#missing[@]} == 0)) || die "not installed: ${missing[*]}"
  ok "pacman: ${#pkgs[@]} packages, system up to date"
}

happ() {
  # The release tag is the version without the build number: 4.8.3 → happ 4.8.3-345. Skip the 85 MB download
  # when it is already installed; if GitHub's API does not answer, just install.
  local latest installed
  latest=$(curl -fsS --max-time 15 "$HAPP_RELEASE_API" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' || true)
  installed=$(pacman -Q happ 2>/dev/null | cut -d' ' -f2 || true)
  if [[ -n $latest && $installed == "$latest"-* ]]; then
    ok "Happ $installed is the latest"
  else
    # pacman -U on a URL also fetches a .sig, which the vendor does not publish: download, then install the file.
    local pkg=/var/cache/pacman/pkg/Happ.linux.x64.pkg.tar.zst
    curl -fL --retry 3 -o "$pkg" "$HAPP_PKG"
    pacman -U --needed --noconfirm "$pkg"
    rm -f "$pkg"
    ok "Happ $(pacman -Q happ | cut -d' ' -f2)"
  fi
  # Happ derives its device id from /var/lib/dbus/machine-id, which dbus-broker never creates.
  if [[ ! -e /var/lib/dbus/machine-id ]]; then
    mkdir -p /var/lib/dbus
    ln -sfn /etc/machine-id /var/lib/dbus/machine-id
  fi
  ok "machine-id for Happ"
}

# Set by system_files: system/etc/default/grub differs from what was installed.
grub_changed=0

system_files() {
  local file rel
  local -a changed=()
  while IFS= read -r -d '' file; do
    rel=${file#"$repo/system/"}
    if ! cmp -s "$file" "/$rel"; then
      install -D -m 0644 "$file" "/$rel"
      changed+=("$rel")
      ok "/$rel"
    fi
  done < <(find "$repo/system" -type f -print0)
  ok "system files: ${#changed[@]} changed"

  # What has to be rebuilt after a change.
  for rel in "${changed[@]}"; do
    case $rel in
      etc/locale.gen) item "locale-gen" locale-gen ;;
      etc/mkinitcpio.conf.d/*) item "initramfs (mkinitcpio -P)" mkinitcpio -P ;;
      etc/default/grub) grub_changed=1 ;;
    esac
  done

  ln -sfn "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  ok "time zone $TIMEZONE"

  # Members of wheel use sudo. The file must be 0440, hence written here and not kept in system/.
  local sudoers=/etc/sudoers.d/10-wheel
  if [[ $(cat "$sudoers" 2>/dev/null) != '%wheel ALL=(ALL:ALL) ALL' ]]; then
    printf '%s\n' '%wheel ALL=(ALL:ALL) ALL' >"$sudoers.tmp"
    chmod 0440 "$sudoers.tmp"
    visudo -cqf "$sudoers.tmp"
    mv "$sudoers.tmp" "$sudoers"
  fi
  ok "sudo for the wheel group"

  # The logged-in session outweighs system services and keeps a memory floor.
  mkdir -p "/etc/systemd/system/user-$uid.slice.d"
  cat >"/etc/systemd/system/user-$uid.slice.d/50-antrel-os.conf" <<EOF
# Written by antrel-os setup.sh: the desktop session stays responsive under load.
[Slice]
CPUWeight=500
MemoryLow=2G
EOF
  ok "session priority: user-$uid.slice"

  local unit
  for unit in NetworkManager.service systemd-timesyncd.service plasmalogin.service fstrim.timer; do
    item "enable $unit" systemctl enable --quiet "$unit"
    ((rc)) || ok "$unit enabled"
  done
  return "$item_failed"
}

# GRUB's menu (kernels + Windows found by os-prober). Rebuilt when system/etc/default/grub changed or there is none.
# install.sh puts GRUB itself on the EFI partition; kernel updates need no rebuild (the file names stay the same).
boot_menu() {
  if in_container; then
    ok "in a container: no boot menu"
    return
  fi
  if ((grub_changed == 0)) && [[ -f /boot/grub/grub.cfg ]]; then
    ok "boot menu unchanged"
    return
  fi
  mkdir -p /boot/grub
  grub-mkconfig -o /boot/grub/grub.cfg
  if grep -q 'Windows Boot Manager' /boot/grub/grub.cfg; then
    ok "boot menu with Windows"
  else
    warn "Windows was not found for the boot menu (is the EFI partition mounted at /efi?)"
  fi
}

link_home() {
  local rel=$1 src dst
  src=$repo/home/$rel
  dst=$home/$rel
  [[ -e $src ]] || die "links.txt lists '$rel', but $src does not exist"
  if [[ $(readlink "$dst" || true) == "$src" ]]; then
    ok "~/$rel"
    return
  fi
  if [[ -f $dst && ! -L $dst ]] && cmp -s "$dst" "/etc/skel/$rel"; then
    rm "$dst" # Arch's stock copy from /etc/skel, nothing of the user's in it
  elif [[ -e $dst || -L $dst ]]; then
    mv "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
    warn "~/$rel already existed: kept as ~/$rel.bak-…"
  fi
  as_user mkdir -p "$(dirname "$dst")"
  as_user ln -s "$src" "$dst"
  ok "~/$rel → repository"
}

home_files() {
  local rel
  while read -r rel; do
    item "~/$rel" link_home "$rel"
  done < <(list "$repo/links.txt")

  item "xdg-user-dirs-update" as_user xdg-user-dirs-update
  ((rc)) || ok "~/Downloads, ~/Documents and the other user folders"

  # Happ's bundled Qt Wayland plugin crashed on Wayland (seen on Hyprland): a user copy of its menu entry runs it
  # through XWayland.
  local desktop
  desktop=$(pacman -Qlq happ 2>/dev/null | grep -m1 '^/usr/share/applications/.*\.desktop$' || true)
  if [[ -n $desktop ]]; then
    as_user mkdir -p "$home/.local/share/applications"
    sed 's|^Exec=|Exec=env QT_QPA_PLATFORM=xcb |' "$desktop" |
      as_user tee "$home/.local/share/applications/$(basename "$desktop")" >/dev/null
    ok "Happ through XWayland"
  else
    warn "Happ is not installed or has no menu entry: XWayland workaround not applied"
  fi
  return "$item_failed"
}

agent() {
  if [[ -x $home/.local/bin/omp ]]; then
    ok "omp is already installed (it updates itself)"
  else
    as_user sh -c 'curl -fsSL https://omp.sh/install | sh' ||
      die "omp did not install: turn on the VPN in Happ and run setup.sh again"
    ok "omp installed"
  fi
}

summary() {
  if ((${#failed[@]})); then
    step "Finished with errors"
    local name
    for name in "${failed[@]}"; do
      fail "$name"
    done
    cat <<EOF
Everything else is done. The reasons are in the red lines above each failed part.
Run again (done parts are quick): sudo ~/antrel-os/setup.sh
Often it is the network: try again later or with the VPN on.
EOF
    exit 1
  fi
  step "Done"
}

main() {
  local yes=0
  case ${1:-} in
    --yes) yes=1 ;;
    "") ;;
    *) die "unknown option '$1' (the only one is --yes)" ;;
  esac
  [[ $EUID -eq 0 ]] || die "run it with sudo: sudo ~/antrel-os/setup.sh"
  user=${SUDO_USER:-}
  [[ -n $user && $user != root ]] || die "run it as your own user through sudo, not as root"
  home=$(getent passwd "$user" | cut -d: -f6)
  repo=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
  [[ -f $repo/packages/pacman.txt ]] || die "$repo is not the antrel-os repository"

  checks
  ((yes)) || confirm
  part "Packages" packages
  part "Happ (VPN)" happ
  part "System files" system_files
  part "Boot menu" boot_menu
  part "User settings" home_files
  part "omp agent" agent
  summary
}

# Everything runs from here, so a half-written file never executes partially.
main "$@"
