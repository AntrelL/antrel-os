#!/usr/bin/env bash
# shellcheck disable=SC2088 # "~/…" in messages is text for the user, not a path to expand.
# antrel-os: turns a fresh Fedora Workstation into the antrel-os desktop.
#
# First run, right after installing Fedora:
#   curl -fsSL https://raw.githubusercontent.com/AntrelL/antrel-os/main/setup.sh | sudo bash
# Later, after changing packages/, system/ or links.txt:
#   sudo ~/antrel-os/setup.sh
#
# Safe to re-run: every step either checks first or overwrites with the repo's version.
# One failure does not stop the rest: each part runs on its own, failed parts are listed at the end.
set -euo pipefail

readonly REPO_URL=https://github.com/AntrelL/antrel-os
readonly HAPP_RPM=https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.rpm
# Nerd Fonts the 43PR desktop uses (bar icons, rofi, terminal), from the project's own releases.
readonly NERD_FONTS=(JetBrainsMono Iosevka NerdFontsSymbolsOnly)
readonly NERD_FONTS_URL=https://github.com/ryanoasis/nerd-fonts/releases/latest/download
readonly NERD_FONTS_DIR=/usr/local/share/fonts/NerdFonts
# Not packaged by Fedora: zsh-autocomplete (git) and papirus-folders (single script), both from their authors.
readonly ZSH_AUTOCOMPLETE_REPO=https://github.com/marlonrichert/zsh-autocomplete
readonly ZSH_AUTOCOMPLETE_DIR=/usr/local/share/zsh-autocomplete
readonly PAPIRUS_FOLDERS_URL=https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders
# Fedora's openh264 repository: metadata comes from Fedora, the packages from Cisco's own server.
readonly CISCO_REPO=fedora-cisco-openh264

die() { printf '\n\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
fail() { printf '  \e[31m✗\e[0m %s\n' "$*" >&2; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*" >&2; }
ok() { printf '  \e[32m✓\e[0m %s\n' "$*"; }
step() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

# Non-comment, non-empty lines of a list file.
list() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1" || true; }

as_user() { sudo -u "$user" -H "$@"; }

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

# One item inside a part (a COPR, a font, a link…): a failure is reported, the part goes on with the next item
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

# Every dnf transaction goes through here. A single package that can't be downloaded fails the whole transaction;
# the usual culprit is openh264, which Cisco's server refuses with HTTP 403 in some countries (seen from Belarus).
# So on failure: once more without Cisco's repository. H.264 keeps working through RPM Fusion's ffmpeg;
# only openh264 (WebRTC calls in Firefox) is not updated until a run where Cisco answers.
dnf_y() {
  dnf -y "$@" && return
  warn "dnf failed; retrying without the $CISCO_REPO repository"
  dnf -y --disablerepo="$CISCO_REPO" "$@"
}

# Started as `curl | sudo bash`: fetch the repository, then run its own copy of this script.
bootstrap() {
  step "Repository"
  rpm -q git >/dev/null || dnf_y install git || die "could not install git"
  if [[ -d "$repo/.git" ]]; then
    as_user git -C "$repo" pull --ff-only || warn "git pull failed: using the copy already in $repo"
  else
    as_user git clone "$REPO_URL" "$repo" || die "could not download $REPO_URL"
  fi
  ok "$repo"
  # stdin is the downloaded script; the confirmation prompt needs the terminal.
  exec bash "$repo/setup.sh" </dev/tty
}

checks() {
  step "Checks (nothing is changed)"
  # shellcheck source=/dev/null
  . /etc/os-release
  [[ $ID == fedora ]] || die "this is not Fedora: $PRETTY_NAME"
  ok "$PRETTY_NAME"
  curl -fsS --max-time 15 -o /dev/null "$REPO_URL" || die "no internet ($REPO_URL is unreachable)"
  ok "internet works"
  uid=$(id -u "$user")
  ok "user $user (uid $uid), repository $repo"
}

confirm() {
  cat <<EOF

Plan:
  1. dnf: fastest mirror, parallel downloads; system update
  2. repositories: RPM Fusion, COPRs from packages/copr.txt; full ffmpeg from RPM Fusion
  3. apps from packages/dnf.txt and packages/flatpak.txt, Happ, Nerd Fonts, zsh-autocomplete, papirus-folders
  4. NVIDIA driver (kernel module build, up to 10 minutes)
  5. system files from system/, scx_bpfland scheduler, zsh as the default shell
  6. 43PR desktop and settings from home/ linked into $home (list: links.txt), theme; omp agent
Windows and disk partitions are not touched.
If a part fails, the rest still runs; failed parts are listed at the end.

EOF
  local answer
  read -rp "Continue? Type yes: " answer
  [[ $answer == yes ]] || die "cancelled, nothing changed"
}

dnf_setup() {
  # Fedora's mirror list has no mirrors in Belarus; pick the fastest one instead of the first.
  dnf config-manager setopt fastestmirror=True max_parallel_downloads=10
  ok "fastestmirror, 10 parallel downloads"
  dnf_y upgrade --refresh
  ok "system updated"
}

rpmfusion() {
  local fedora
  fedora=$(rpm -E %fedora)
  dnf_y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fedora.noarch.rpm"
  ok "RPM Fusion"
}

# owner/project [only=a,b | except=a,b]
copr() {
  local project=$1 filter=${2:-} repoid
  case $filter in
    only=* | except=* | "") ;;
    *) die "packages/copr.txt: unknown '$filter' for $project (expected only=… or except=…)" ;;
  esac
  dnf -y copr enable "$project"
  repoid="copr:copr.fedorainfracloud.org:${project/\//:}"
  case $filter in
    only=*) dnf config-manager setopt "$repoid.includepkgs=${filter#only=}" ;;
    except=*) dnf config-manager setopt "$repoid.excludepkgs=${filter#except=}" ;;
  esac
  ok "COPR $project${filter:+ ($filter)}"
}

coprs() {
  local project filter
  while read -r project filter; do
    item "COPR $project" copr "$project" "$filter"
  done < <(list "$repo/packages/copr.txt")
  return "$item_failed"
}

full_ffmpeg() {
  # RPM Fusion's full ffmpeg replaces Fedora's patent-free build (and its libraries) in one transaction.
  dnf_y swap ffmpeg-free ffmpeg --allowerasing
  ok "ffmpeg from RPM Fusion"
}

# Missing packages are skipped (and reported below) instead of blocking the others. If the transaction still fails,
# e.g. a package that can't be downloaded, install one by one so that only the broken ones are left out.
dnf_packages() {
  local -a rpms missing=()
  local p
  mapfile -t rpms < <(list "$repo/packages/dnf.txt")
  if ! dnf_y install --skip-unavailable "${rpms[@]}"; then
    warn "installing everything at once failed; installing one by one"
    for p in "${rpms[@]}"; do
      rpm -q --whatprovides "$p" >/dev/null 2>&1 || dnf_y install "$p" || true
    done
  fi
  for p in "${rpms[@]}"; do
    rpm -q --whatprovides "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  ((${#missing[@]} == 0)) || die "not installed: ${missing[*]}"
  ok "dnf: ${#rpms[@]} packages"
}

happ() {
  dnf_y install "$HAPP_RPM"
  ok "Happ"
}

flatpaks() {
  local -a flatpaks
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # Fedora ships Flathub filtered to a short allow-list.
  flatpak remote-modify --no-filter --enable flathub
  mapfile -t flatpaks < <(list "$repo/packages/flatpak.txt")
  if ((${#flatpaks[@]})); then
    flatpak install -y --noninteractive flathub "${flatpaks[@]}"
  fi
  ok "Flatpak: ${#flatpaks[@]} apps"
}

nerd_font() {
  local font=$1 zip
  if [[ ! -d $NERD_FONTS_DIR/$font ]]; then
    zip=$(mktemp --suffix=.zip)
    curl -fsSLo "$zip" "$NERD_FONTS_URL/$font.zip"
    mkdir -p "$NERD_FONTS_DIR/$font.tmp"
    unzip -q -o "$zip" '*.ttf' -d "$NERD_FONTS_DIR/$font.tmp"
    mv "$NERD_FONTS_DIR/$font.tmp" "$NERD_FONTS_DIR/$font"
    rm -f "$zip"
  fi
  ok "Nerd Font $font"
}

extras() {
  local font
  for font in "${NERD_FONTS[@]}"; do
    item "Nerd Font $font" nerd_font "$font"
  done
  fc-cache -f
  ok "to update a font: delete $NERD_FONTS_DIR/<font> and run again"
  item "zsh-autocomplete" zsh_autocomplete
  item "Papirus white folders" papirus_folders
  return "$item_failed"
}

zsh_autocomplete() {
  if [[ -d $ZSH_AUTOCOMPLETE_DIR/.git ]]; then
    git -C "$ZSH_AUTOCOMPLETE_DIR" pull -q --ff-only
  else
    rm -rf "$ZSH_AUTOCOMPLETE_DIR"
    git clone -q --depth 1 "$ZSH_AUTOCOMPLETE_REPO" "$ZSH_AUTOCOMPLETE_DIR"
  fi
  ok "zsh-autocomplete"
}

papirus_folders() {
  # White folder icons, as in 43PR. A papirus-icon-theme update resets them; the next setup.sh run restores them.
  curl -fsSLo /usr/local/bin/papirus-folders "$PAPIRUS_FOLDERS_URL"
  chmod 0755 /usr/local/bin/papirus-folders
  papirus-folders -C white >/dev/null
  ok "Papirus white folders"
}

nvidia() {
  rpm -q akmod-nvidia >/dev/null || die "akmod-nvidia is not installed (see the Apps part above)"
  # akmods packaging lets autoremove drop the driver's build chain; keep it.
  dnf mark user akmod-nvidia
  # The module is built for the newest installed kernel: the one that boots next.
  local kernel
  kernel=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n1)
  akmods --force --kernels "$kernel"
  modinfo -F version nvidia -k "$kernel" >/dev/null ||
    die "the nvidia module was not built for kernel $kernel: see /var/cache/akmods/nvidia/*.log"
  ok "nvidia $(modinfo -F version nvidia -k "$kernel") for kernel $kernel"
}

system_files() {
  local file
  while IFS= read -r -d '' file; do
    install -D -m 0644 "$file" "/${file#"$repo/system/"}"
    ok "/${file#"$repo/system/"}"
  done < <(find "$repo/system" -type f -print0)

  # The logged-in session outweighs system services and keeps a memory floor.
  mkdir -p "/etc/systemd/system/user-$uid.slice.d"
  cat >"/etc/systemd/system/user-$uid.slice.d/50-antrel-os.conf" <<EOF
# Written by antrel-os setup.sh: the desktop session stays responsive under load.
[Slice]
CPUWeight=500
MemoryLow=2G
EOF
  ok "session priority: user-$uid.slice"

  # Happ derives its device id from /var/lib/dbus/machine-id, which dbus-broker never creates.
  if [[ ! -e /var/lib/dbus/machine-id ]]; then
    mkdir -p /var/lib/dbus
    ln -s /etc/machine-id /var/lib/dbus/machine-id
  fi
  ok "machine-id for Happ"

  item "scx_loader" systemctl enable scx_loader.service
  ((rc)) || ok "scx_loader (scx_bpfland) starts after a reboot"

  # 43PR's terminal setup is zsh (~/.zshrc from the repo).
  if [[ -x /bin/zsh ]]; then
    if [[ $(getent passwd "$user" | cut -d: -f7) != /bin/zsh ]]; then
      usermod -s /bin/zsh "$user"
    fi
    ok "zsh is the default shell for $user"
  else
    item_failed=1
    fail "zsh is not installed: the default shell stays as it is"
  fi
  return "$item_failed"
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
  if [[ -e $dst || -L $dst ]]; then
    mv "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
    warn "~/$rel already existed: kept as ~/$rel.bak-…"
  fi
  as_user mkdir -p "$(dirname "$dst")"
  as_user ln -s "$src" "$dst"
  ok "~/$rel → repository"
}

# The avatar is 43PR's custom one (Super+I → System, home/.config/quickshell/imgs/pfp_custom, in git); the login
# screen and GNOME take theirs from AccountsService, so hand the same picture to it.
user_avatar() {
  local src=$repo/home/.config/quickshell/imgs/pfp_custom
  local icon=/var/lib/AccountsService/icons/$user conf=/var/lib/AccountsService/users/$user
  if [[ ! -f $src ]]; then
    ok "no custom avatar in the repository: system default"
    return
  fi
  if busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$uid" \
    org.freedesktop.Accounts.User SetIconFile s "$src" >/dev/null 2>&1; then
    ok "avatar on the login screen"
    return
  fi
  # accounts-daemon is not running (e.g. in a container): write its files, it reads them when it starts.
  install -D -m 0644 "$src" "$icon"
  mkdir -p "$(dirname "$conf")"
  grep -qs '^\[User\]' "$conf" || printf '[User]\n' >>"$conf"
  if grep -q '^Icon=' "$conf"; then
    sed -i "s|^Icon=.*|Icon=$icon|" "$conf"
  else
    sed -i "/^\[User\]/a Icon=$icon" "$conf"
  fi
  ok "avatar on the login screen (applies after a reboot)"
}

home_files() {
  local rel
  while read -r rel; do
    item "~/$rel" link_home "$rel"
  done < <(list "$repo/links.txt")

  # Happ's bundled Qt Wayland plugin crashes on Hyprland: a user copy of its menu entry runs it through XWayland.
  local desktop
  desktop=$(rpm -ql happ 2>/dev/null | grep -m1 '^/usr/share/applications/.*\.desktop$' || true)
  if [[ -n $desktop ]]; then
    as_user mkdir -p "$home/.local/share/applications"
    sed 's|^Exec=|Exec=env QT_QPA_PLATFORM=xcb |' "$desktop" |
      as_user tee "$home/.local/share/applications/$(basename "$desktop")" >/dev/null
    ok "Happ through XWayland"
  else
    warn "Happ is not installed or has no menu entry in /usr/share/applications: XWayland workaround not applied"
  fi

  # Vesktop (Flatpak) sees only its own ~/.var/app folder; let it follow the links into this repository.
  # Standard Discord icon instead of Vesktop's: the official one (Flathub listing by Discord Inc.) installed
  # under its own name, so the Papirus theme can't swap it. Tray icons are Vesktop userAssets in the repo.
  local vesktop=/var/lib/flatpak/exports/share/applications/dev.vencord.Vesktop.desktop
  if [[ -f $vesktop ]]; then
    as_user flatpak override --user --filesystem="$repo/home/.var/app/dev.vencord.Vesktop" dev.vencord.Vesktop
    as_user mkdir -p "$home/.local/share/applications"
    sed 's|^Icon=.*|Icon=antrel-discord|' "$vesktop" |
      as_user tee "$home/.local/share/applications/dev.vencord.Vesktop.desktop" >/dev/null
    ok "Vesktop: Discord icon, access to its settings in the repository"
  else
    warn "no $vesktop (Vesktop not installed): icon and settings access not applied"
  fi

  as_user xdg-user-dirs-update || warn "xdg-user-dirs-update failed"
  item "Login screen avatar" user_avatar

  # 43PR theme: first run starts from the bundled wallpaper; later runs re-apply the tracked state.json
  # (theme.py writes colors for kitty, rofi, GTK, btop, cava, Hyprland and the bar).
  local theme=$home/.config/43pr/bin/theme.py
  if ! grep -q '"wallpaper"' "$home/.local/state/43pr/state.json" 2>/dev/null; then
    as_user dbus-run-session -- python3 "$theme" wallpaper "$home/Pictures/Wallpapers/wallhaven-k8jvm7.jpg" ||
      warn "could not apply the default wallpaper"
  fi
  if as_user dbus-run-session -- python3 "$theme" apply; then
    ok "43PR theme applied"
  else
    warn "theme.py apply failed: the theme is applied on the first Hyprland login (Super+I → themes)"
  fi

  # GTK4 (Nautilus etc.) skips hinting by default since 4.16 and looks soft at ~96 DPI.
  if as_user dbus-run-session -- sh -c '
      gsettings set org.gnome.desktop.interface font-rendering manual &&
      gsettings set org.gnome.desktop.interface font-antialiasing rgba &&
      gsettings set org.gnome.desktop.interface font-rgba-order rgb &&
      gsettings set org.gnome.desktop.interface font-hinting slight'; then
    ok "GTK4 font smoothing"
  else
    warn "could not apply GTK4 font settings (gsettings)"
  fi

  # Mouse in the spare GNOME session: same as hyprland.lua (Windows 6/20 = ×0.5, no acceleration).
  if as_user dbus-run-session -- sh -c '
      gsettings set org.gnome.desktop.peripherals.mouse accel-profile flat &&
      gsettings set org.gnome.desktop.peripherals.mouse speed -0.5'; then
    ok "GNOME mouse: no acceleration, Windows speed"
  else
    warn "could not set up the mouse in GNOME (gsettings)"
  fi
  return "$item_failed"
}

agent() {
  if as_user bash -lc 'command -v omp' >/dev/null; then
    ok "omp is already installed"
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
  cat <<EOF
Reboot: sudo reboot
On the login screen: pick the user → gear icon at the bottom right → "Hyprland (uwsm-managed)".
The login screen remembers the choice. GNOME stays as the spare desktop.
In Hyprland: Super+D apps, Super+T terminal, Super+I settings (all hotkeys are listed there).
EOF
}

main() {
  [[ $EUID -eq 0 ]] || die "run it with sudo"
  user=${SUDO_USER:-}
  [[ -n $user && $user != root ]] || die "run it as your own user through sudo, not as root"
  home=$(getent passwd "$user" | cut -d: -f6)

  local self
  self=${BASH_SOURCE[0]:-}
  if [[ -n $self && -f $self && -f "$(dirname "$self")/packages/dnf.txt" ]]; then
    repo=$(cd "$(dirname "$self")" && pwd)
  else
    repo=$home/antrel-os
    bootstrap
  fi

  checks
  confirm
  part "System update" dnf_setup
  part "RPM Fusion" rpmfusion
  part "COPR repositories" coprs
  part "ffmpeg" full_ffmpeg
  part "Apps (dnf)" dnf_packages
  part "Happ" happ
  part "Apps (Flatpak)" flatpaks
  part "Fonts and extras" extras
  part "NVIDIA driver" nvidia
  part "System files" system_files
  part "User settings" home_files
  part "omp agent" agent
  summary
}

# Everything runs from here, so a half-downloaded `curl | bash` never executes a partial script.
main "$@"
