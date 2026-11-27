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
set -euo pipefail

readonly REPO_URL=https://github.com/AntrelL/antrel-os
readonly HAPP_RPM=https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.rpm
readonly NERD_FONT_ZIP=https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
readonly NERD_FONT_DIR=/usr/local/share/fonts/JetBrainsMonoNerdFont

die() { printf '\n\e[31mОШИБКА:\e[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*" >&2; }
ok() { printf '  \e[32m✓\e[0m %s\n' "$*"; }
step() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

# Non-comment, non-empty lines of a list file.
list() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1" || true; }

as_user() { sudo -u "$user" -H "$@"; }

# Started as `curl | sudo bash`: fetch the repository, then run its own copy of this script.
bootstrap() {
  step "Репозиторий"
  rpm -q git >/dev/null || dnf -y install git
  if [[ -d "$repo/.git" ]]; then
    as_user git -C "$repo" pull --ff-only
  else
    as_user git clone "$REPO_URL" "$repo"
  fi
  ok "$repo"
  # stdin is the downloaded script; the confirmation prompt needs the terminal.
  exec bash "$repo/setup.sh" </dev/tty
}

checks() {
  step "Проверки (ничего не меняется)"
  # shellcheck source=/dev/null
  . /etc/os-release
  [[ $ID == fedora ]] || die "это не Fedora: $PRETTY_NAME"
  ok "$PRETTY_NAME"
  curl -fsS --max-time 15 -o /dev/null "$REPO_URL" || die "нет интернета ($REPO_URL недоступен)"
  ok "интернет есть"
  uid=$(id -u "$user")
  ok "пользователь $user (uid $uid), репозиторий $repo"
}

confirm() {
  cat <<EOF

Будет сделано:
  1. dnf: самое быстрое зеркало, параллельная загрузка; обновление системы
  2. репозитории: RPM Fusion, COPR из packages/copr.txt
  3. программы из packages/dnf.txt и packages/flatpak.txt, Happ, шрифт JetBrainsMono Nerd Font
  4. драйвер NVIDIA (сборка модуля ядра, до 10 минут)
  5. системные файлы из system/, планировщик scx_bpfland, Dux Shell для сессии Hyprland
  6. настройки из home/ ссылками в $home (список: links.txt); агент omp
Windows и разделы диска не меняются.

EOF
  local answer
  read -rp "Продолжить? Введите yes: " answer
  [[ $answer == yes ]] || die "отменено, ничего не изменено"
}

dnf_setup() {
  step "dnf"
  # Fedora's mirror list has no mirrors in Belarus; pick the fastest one instead of the first.
  dnf config-manager setopt fastestmirror=True max_parallel_downloads=10
  ok "fastestmirror, 10 параллельных загрузок"
  dnf -y upgrade --refresh
  ok "система обновлена"
}

repos() {
  step "Репозитории"
  local fedora
  fedora=$(rpm -E %fedora)
  dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fedora.noarch.rpm"
  ok "RPM Fusion"

  local project pkgs
  while read -r project pkgs; do
    dnf -y copr enable "$project"
    if [[ -n $pkgs ]]; then
      # Only the listed packages may come from this COPR; it must not replace Fedora's own.
      dnf config-manager setopt "copr:copr.fedorainfracloud.org:${project/\//:}.includepkgs=${pkgs// /,}"
    fi
    ok "COPR $project${pkgs:+ (только: $pkgs)}"
  done < <(list "$repo/packages/copr.txt")
}

packages() {
  step "Программы"
  local -a rpms flatpaks
  mapfile -t rpms < <(list "$repo/packages/dnf.txt")
  dnf -y install "${rpms[@]}" "$HAPP_RPM"
  # akmods packaging lets autoremove drop the driver's build chain; keep it.
  dnf mark user akmod-nvidia
  ok "dnf: ${#rpms[@]} пакетов + Happ"

  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # Fedora ships Flathub filtered to a short allow-list.
  flatpak remote-modify --no-filter --enable flathub
  mapfile -t flatpaks < <(list "$repo/packages/flatpak.txt")
  if ((${#flatpaks[@]})); then
    flatpak install -y --noninteractive flathub "${flatpaks[@]}"
  fi
  ok "Flatpak: ${#flatpaks[@]} программ"

  if [[ ! -d $NERD_FONT_DIR ]]; then
    local zip
    zip=$(mktemp --suffix=.zip)
    curl -fsSLo "$zip" "$NERD_FONT_ZIP"
    mkdir -p "$NERD_FONT_DIR"
    unzip -q -o "$zip" '*.ttf' -d "$NERD_FONT_DIR"
    rm -f "$zip"
    fc-cache -f
  fi
  ok "JetBrainsMono Nerd Font (обновить: удалить $NERD_FONT_DIR и запустить снова)"
}

nvidia() {
  step "Драйвер NVIDIA"
  # The module is built for the newest installed kernel: the one that boots next.
  local kernel
  kernel=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n1)
  akmods --force --kernels "$kernel"
  modinfo -F version nvidia -k "$kernel" >/dev/null ||
    die "модуль nvidia не собрался для ядра $kernel: смотрите /var/cache/akmods/nvidia/*.log"
  ok "nvidia $(modinfo -F version nvidia -k "$kernel") для ядра $kernel"
}

system_files() {
  step "Системные файлы"
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
  ok "приоритет сессии: user-$uid.slice"

  # Happ derives its device id from /var/lib/dbus/machine-id, which dbus-broker never creates.
  if [[ ! -e /var/lib/dbus/machine-id ]]; then
    mkdir -p /var/lib/dbus
    ln -s /etc/machine-id /var/lib/dbus/machine-id
  fi
  ok "machine-id для Happ"

  systemctl enable scx_loader.service
  ok "scx_loader (scx_bpfland) включится после перезагрузки"
  # For every user; system/etc/systemd/user/dms.service.d keeps it out of GNOME.
  systemctl --global enable dms.service
  ok "Dux Shell запускается в сессии Hyprland"
}

home_files() {
  step "Настройки пользователя"
  local rel src dst
  while read -r rel; do
    src=$repo/home/$rel
    dst=$home/$rel
    [[ -e $src ]] || die "в links.txt есть '$rel', но нет $src"
    if [[ $(readlink "$dst" || true) == "$src" ]]; then
      ok "~/$rel"
      continue
    fi
    if [[ -e $dst || -L $dst ]]; then
      mv "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
      warn "~/$rel уже был: сохранён как ~/$rel.bak-…"
    fi
    as_user mkdir -p "$(dirname "$dst")"
    as_user ln -s "$src" "$dst"
    ok "~/$rel → репозиторий"
  done < <(list "$repo/links.txt")

  # Happ's bundled Qt Wayland plugin crashes on Hyprland: a user copy of its menu entry runs it through XWayland.
  local desktop
  desktop=$(rpm -ql happ | grep -m1 '^/usr/share/applications/.*\.desktop$' || true)
  if [[ -n $desktop ]]; then
    as_user mkdir -p "$home/.local/share/applications"
    sed 's|^Exec=|Exec=env QT_QPA_PLATFORM=xcb |' "$desktop" |
      as_user tee "$home/.local/share/applications/$(basename "$desktop")" >/dev/null
    ok "Happ через XWayland"
  else
    warn "у пакета happ нет ярлыка в /usr/share/applications: XWayland-обход не применён"
  fi

  # GTK4 (Nautilus etc.) skips hinting by default since 4.16 and looks soft at ~96 DPI.
  if as_user dbus-run-session -- sh -c '
      gsettings set org.gnome.desktop.interface font-rendering manual &&
      gsettings set org.gnome.desktop.interface font-antialiasing rgba &&
      gsettings set org.gnome.desktop.interface font-rgba-order rgb &&
      gsettings set org.gnome.desktop.interface font-hinting slight'; then
    ok "сглаживание шрифтов в GTK4"
  else
    warn "не удалось применить настройки шрифтов GTK4 (gsettings)"
  fi
}

agent() {
  step "Агент omp"
  if as_user bash -lc 'command -v omp' >/dev/null; then
    ok "omp уже установлен"
  elif as_user sh -c 'curl -fsSL https://omp.sh/install | sh'; then
    ok "omp установлен"
  else
    warn "omp не установился: включите VPN в Happ и запустите setup.sh снова"
  fi
}

done_message() {
  step "Готово"
  cat <<EOF
Перезагрузитесь: sudo reboot
На экране входа: выбрать пользователя → значок шестерёнки внизу справа → «Hyprland (uwsm-managed)».
Экран входа запомнит выбор. GNOME остаётся запасным рабочим столом.
EOF
}

main() {
  [[ $EUID -eq 0 ]] || die "запустите через sudo"
  user=${SUDO_USER:-}
  [[ -n $user && $user != root ]] || die "запускайте от своего пользователя через sudo, а не из-под root"
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
  dnf_setup
  repos
  packages
  nvidia
  system_files
  home_files
  agent
  done_message
}

# Everything runs from here, so a half-downloaded `curl | bash` never executes a partial script.
main "$@"
