#!/usr/bin/env bash
# shellcheck disable=SC2088 # "~/…" in messages is text for the user, not a path to expand.
# Puts a config under git: moves ~/<path> into home/<path>, links it back, records it in links.txt.
# Usage (no sudo): ~/antrel-os/track.sh ~/.config/DankMaterialShell
# Never track secrets: ~/.config/gh, ~/.config/happ (VPN subscription), browser profiles.
set -euo pipefail

die() { printf 'ОШИБКА: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "укажите один путь, например ~/.config/kitty"
[[ $EUID -ne 0 ]] || die "запускайте без sudo"

repo=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
target=$(realpath -s "$1")
[[ $target == "$HOME"/* ]] || die "$target не внутри $HOME"
[[ -e $target ]] || die "$target не существует"
[[ ! -L $target ]] || die "$target уже ссылка"

rel=${target#"$HOME"/}
dest=$repo/home/$rel
[[ ! -e $dest ]] || die "$dest уже есть в репозитории"

mkdir -p "$(dirname "$dest")"
mv "$target" "$dest"
ln -s "$dest" "$target"
grep -qxF "$rel" "$repo/links.txt" || printf '%s\n' "$rel" >>"$repo/links.txt"
echo "~/$rel теперь в репозитории: home/$rel"
