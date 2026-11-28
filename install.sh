#!/usr/bin/env bash
# antrel-os installer. Run it on the Arch Linux live USB:
#   curl -fsSL https://raw.githubusercontent.com/AntrelL/antrel-os/main/install.sh | bash
#
# First a menu: every disk with a picture of its partitions, and the places antrel-os can go:
#   - free (unpartitioned) space on a GPT disk;
#   - an existing antrel-os partition (reinstall);
#   - a whole disk, erased (confirmed by typing the disk's name).
# Then the plan and "yes" (anything else goes back to the menu). After that, on the chosen place only:
#   - btrfs with subvolumes @ and @home; GRUB on the disk's EFI partition (Windows' one when there is one,
#     a new 1 GiB one when the disk has none); kernels stay on btrfs;
#   - installs Arch, creates the user, clones this repository into ~/antrel-os and runs setup.sh inside;
#   - GRUB with a boot menu entry for Windows (found on any disk).
# Never touched: partitions other than the chosen one, except the EFI partition, which only gets GRUB.
set -euo pipefail

readonly REPO_URL=https://github.com/AntrelL/antrel-os
readonly USER_NAME=antrel
readonly LABEL=antrel-os
readonly MIN_GIB=30
readonly ESP_GIB=1
readonly GIB=$((1024 * 1024 * 1024))
readonly ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
readonly MS_RESERVED_TYPE=e3c9e316-0b5c-4db8-817d-f92df00215ae
readonly WIN_RECOVERY_TYPE=de94bba4-06d1-4d40-a16a-bfd50179d6ac
readonly MNT=/mnt
readonly BTRFS_OPTS=noatime,compress=zstd:1
# Arch mirrors nearest to Belarus (reflector picks the fastest of them).
readonly MIRROR_COUNTRIES=BY,LT,LV,PL,DE,FI,SE

# The live USB has a text console with 8 colors and the PC's own character set: √ and ► exist there, ✓ does not.
readonly RESET=$'\e[0m' BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' \
  BLUE=$'\e[34m' MAGENTA=$'\e[35m' CYAN=$'\e[36m'

die() { printf '\n%sERROR:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
ok() { printf '  %s√%s %s\n' "$GREEN" "$RESET" "$*"; }
step() { printf '\n%s== %s%s\n' "$BOLD" "$*" "$RESET"; }

# stdin is the script itself (curl | bash): questions and keys come from the terminal.
ask() { read -r "$@" </dev/tty; }
read_key() {
  local key rest=""
  IFS= read -rsn1 key </dev/tty
  if [[ $key == $'\e' ]]; then
    IFS= read -rsn2 -t 0.1 rest </dev/tty || true
  fi
  printf '%s' "$key$rest"
}

# 476.9 GiB, 40 GiB, 512 MiB.
human() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB PiB", u); i = 1
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    s = sprintf("%.1f", b)
    if (b >= 100 || s ~ /\.0$/) printf "%d %s", b + 0.5, u[i]; else printf "%s %s", s, u[i]
  }'
}

# One `lsblk -P` line (KEY="value" …) into the associative array named $1. lsblk escapes quotes in values.
parse_pairs() {
  local -n _row=$1
  local line=$2 re='^ *([A-Z]+)="([^"]*)"(.*)$'
  _row=()
  while [[ $line =~ $re ]]; do
    # shellcheck disable=SC2004 # _row is associative (a nameref): the key is text, not arithmetic.
    _row[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
    line=${BASH_REMATCH[3]}
  done
}

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

# ---- What is on the disks (filled by scan; nothing is changed) ----

disks=()   # disks antrel-os can go on
skipped=() # "sdb (the live USB)": shown under the menu
declare -A d_size d_model d_pt d_ss d_esp d_win d_parts d_order
any_windows=0
# Segments of the disk pictures: partitions and free space ≥ 1 GiB, in bytes.
seg_disk=() seg_first=() seg_last=() seg_kind=() seg_part=() seg_text=()
# Menu options. kind: free | reinstall | wipe; ok=0: shown, not selectable (reason in text).
opt_kind=() opt_disk=() opt_seg=() opt_first=() opt_last=() opt_part=() opt_ok=() opt_text=()

list_disks() { lsblk -dnpo NAME,TYPE | awk '$2 == "disk" && $1 !~ /zram/ { print $1 }'; }

# Kind (picture color) and description of a partition from its lsblk fields in the array named $1.
describe() {
  local -n _p=$1
  local label=${_p[LABEL]:-${_p[PARTLABEL]}}
  case $label in "Basic data partition" | "Microsoft reserved partition" | "EFI system partition" | EFI) label="" ;; esac
  if [[ ${_p[PARTLABEL]} == "$LABEL" ]]; then
    kind=antrel text="antrel-os"
    return
  fi
  case ${_p[PARTTYPE]} in
    "$ESP_TYPE") kind=esp text="EFI system" ;;
    "$MS_RESERVED_TYPE") kind=win text="Microsoft reserved" ;;
    "$WIN_RECOVERY_TYPE") kind=win text="Windows recovery" ;;
    *)
      case ${_p[FSTYPE]} in
        ntfs) kind=win text="Windows (NTFS)" ;;
        btrfs | ext4 | ext3 | ext2 | xfs | f2fs | swap | crypto_LUKS) kind=linux text="Linux (${_p[FSTYPE]})" ;;
        "") kind=other text="no file system" ;;
        *) kind=other text=${_p[FSTYPE]} ;;
      esac
      ;;
  esac
  if [[ -n $label ]]; then
    text+=" \"$label\""
  fi
}

# Windows Boot Manager on an EFI partition (mounted read-only for a look).
has_windows() {
  local tmp found=1
  tmp=$(mktemp -d)
  if mount -o ro "$1" "$tmp" 2>/dev/null; then
    [[ -f $tmp/EFI/Microsoft/Boot/bootmgfw.efi ]] && found=0
    umount "$tmp"
  fi
  rmdir "$tmp"
  return "$found"
}

add_option() { # kind disk seg first last part ok text
  opt_kind+=("$1") opt_disk+=("$2") opt_seg+=("$3") opt_first+=("$4") opt_last+=("$5") opt_part+=("$6")
  opt_ok+=("$7") opt_text+=("$8")
}

scan_disk() {
  local d=$1 line why="" kind text s first last bytes need loc prev_text="" ss
  local -A r p
  local -a parts=()
  parse_pairs r "$(lsblk -bdnpP -o NAME,SIZE,MODEL,TRAN,PTTYPE,RO "$d")"

  while IFS= read -r line; do
    parse_pairs p "$line"
    if [[ ${p[LABEL]} == ARCH_* || ${p[FSTYPE]} == iso9660 ]]; then
      why="the live USB"
    elif [[ -n ${p[MOUNTPOINT]} && -z $why ]]; then
      why="in use: ${p[MOUNTPOINT]} is mounted"
    fi
    [[ ${p[TYPE]} == part ]] && parts+=("$line")
  done < <(lsblk -bnpP -o NAME,TYPE,START,SIZE,FSTYPE,LABEL,PARTLABEL,PARTTYPE,MOUNTPOINT "$d")
  if [[ -z $why && ${r[RO]} == 1 ]]; then
    why="read-only"
  elif [[ -z $why ]] && ((r[SIZE] < (MIN_GIB + ESP_GIB) * GIB)); then
    why="$(human "${r[SIZE]}"), too small"
  fi
  if [[ -n $why ]]; then
    skipped+=("${d#/dev/} ($why)")
    return
  fi

  disks+=("$d")
  ss=$(blockdev --getss "$d")
  d_size[$d]=${r[SIZE]} d_pt[$d]=${r[PTTYPE]} d_ss[$d]=$ss d_esp[$d]="" d_win[$d]=0 d_parts[$d]=""
  d_model[$d]=${r[MODEL]:-disk}
  [[ -n ${r[TRAN]} ]] && d_model[$d]+=" · ${r[TRAN]^^}"

  for line in "${parts[@]}"; do
    parse_pairs p "$line"
    describe p
    if [[ $kind == esp ]]; then
      if has_windows "${p[NAME]}"; then
        text+=", Windows Boot Manager"
        d_win[$d]=1 any_windows=1
        d_esp[$d]=${p[NAME]}
      elif [[ -z ${d_esp[$d]} ]]; then
        d_esp[$d]=${p[NAME]}
      fi
    fi
    # lsblk counts START in 512-byte sectors whatever the disk's sector size is.
    first=$((p[START] * 512))
    seg_disk+=("$d") seg_first+=("$first") seg_last+=($((first + p[SIZE] - 1))) seg_kind+=("$kind")
    seg_part+=("${p[NAME]}") seg_text+=("$text")
    d_parts[$d]+="${p[NAME]#/dev/} $(human "${p[SIZE]}") $text"$'\n'
  done

  # Free space, in the disk's own sectors: "Start End Sectors Size" lines.
  if [[ -n ${d_pt[$d]} ]]; then
    while read -r first last _; do
      bytes=$(((last - first + 1) * ss))
      ((bytes >= GIB)) || continue
      seg_disk+=("$d") seg_first+=($((first * ss))) seg_last+=($(((last + 1) * ss - 1))) seg_kind+=(free)
      seg_part+=("") seg_text+=("free")
    done < <(sfdisk -F "$d" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { print $1, $2 }')
  fi

  # Options in disk order: free space and antrel-os partitions, then the whole disk.
  local -a order
  mapfile -t order < <(for s in "${!seg_disk[@]}"; do
    [[ ${seg_disk[s]} == "$d" ]] && echo "${seg_first[s]} $s"
  done | sort -n | cut -d' ' -f2)
  d_order[$d]="${order[*]}"
  for s in "${order[@]}"; do
    bytes=$((seg_last[s] - seg_first[s] + 1))
    if [[ ${seg_kind[s]} == free ]]; then
      need=$MIN_GIB
      [[ -z ${d_esp[$d]} ]] && need=$((MIN_GIB + ESP_GIB))
      loc=${prev_text:-at the start of the disk}
      if [[ ${d_pt[$d]} != gpt ]]; then
        add_option free "$d" "$s" "${seg_first[s]}" "${seg_last[s]}" "" 0 "$loc; MBR disk: erase it instead"
      elif ((bytes < need * GIB)); then
        add_option free "$d" "$s" "${seg_first[s]}" "${seg_last[s]}" "" 0 "$loc; too small (needs $need GiB)"
      else
        add_option free "$d" "$s" "${seg_first[s]}" "${seg_last[s]}" "" 1 "$loc"
      fi
    else
      prev_text="after ${seg_part[s]#/dev/} (${seg_text[s]})"
      if [[ ${seg_kind[s]} == antrel ]]; then
        if [[ -n ${d_esp[$d]} ]]; then
          add_option reinstall "$d" "$s" "" "" "${seg_part[s]}" 1 "${seg_part[s]#/dev/}: replaces the antrel-os on it"
        else
          add_option reinstall "$d" "$s" "" "" "${seg_part[s]}" 0 "${seg_part[s]#/dev/}: no EFI partition on this disk"
        fi
      fi
    fi
  done
  if ((${#parts[@]})); then
    add_option wipe "$d" -1 "" "" "" 1 "deletes everything on it"
  else
    add_option wipe "$d" -1 "" "" "" 1 "the disk is empty"
  fi
}

scan() {
  step "Disks (nothing is changed)"
  local d
  while read -r d; do
    scan_disk "$d"
  done < <(list_disks)
  ((${#disks[@]})) || die "no disk to install to.${skipped[*]:+ Not suitable: ${skipped[*]}}"
  ok "${#disks[@]} disk(s), ${#opt_kind[@]} possible place(s)"
}

# ---- The menu ----

kind_color() {
  case $1 in
    esp) printf %s "$MAGENTA" ;;
    win) printf %s "$BLUE" ;;
    antrel) printf %s "$GREEN" ;;
    linux) printf %s "$YELLOW" ;;
    other) printf %s "$CYAN" ;;
  esac
}

# How the bar shows erasing the whole disk: red when something is on it, white when it is empty.
wipe_style() { [[ -n ${d_parts[$1]} ]] && echo 1 || echo 2; }

# The disk as a bar: partitions in their colors, free space ░; the chosen place white. whole: 1 = all red (the
# disk is erased), 2 = all white (an empty disk is taken).
draw_bar() {
  local d=$1 hl=$2 whole=$3 w=$bar_w total=${d_size[$1]} s i c0 c1 end=0 style ch out="" last_style=""
  local -a cell=()
  for ((i = 0; i < w; i++)); do cell[i]=-1; done
  # In disk order, each segment at least one character and after the previous one: the tiny EFI and Microsoft
  # reserved partitions stay visible.
  for s in ${d_order[$d]}; do
    c0=$((seg_first[s] * w / total))
    c1=$(((seg_last[s] + 1) * w / total))
    ((c0 >= end)) || c0=$end
    ((c1 > c0)) || c1=$((c0 + 1))
    ((c1 <= w)) || c1=$w
    ((c0 < c1)) || c0=$((c1 - 1))
    for ((i = c0; i < c1; i++)); do cell[i]=$s; done
    end=$c1
  done
  for ((i = 0; i < w; i++)); do
    s=${cell[i]} ch='█'
    if ((whole == 1)); then
      style=$RED
    elif ((whole == 2)) || ((s == hl && s >= 0)); then
      style=$BOLD
    elif ((s < 0)) || [[ ${seg_kind[s]} == free ]]; then
      style=$DIM ch='░'
    else
      style=$(kind_color "${seg_kind[s]}")
    fi
    if [[ $style != "$last_style" ]]; then
      out+=$RESET$style
      last_style=$style
    fi
    out+=$ch
  done
  printf '   %s%s\n' "$out" "$RESET"
}

option_label() {
  case ${opt_kind[$1]} in
    free) echo "Free space" ;;
    reinstall) echo "Reinstall antrel-os" ;;
    wipe) [[ -n ${d_parts[${opt_disk[$1]}]} ]] && echo "Erase the whole disk" || echo "Use the whole disk" ;;
  esac
}

option_bytes() {
  local i=$1
  case ${opt_kind[i]} in
    wipe) echo "${d_size[${opt_disk[i]}]}" ;;
    *) echo $((seg_last[opt_seg[i]] - seg_first[opt_seg[i]] + 1)) ;;
  esac
}

# What the selected option does, under the menu.
explain() {
  local i=$1 d=${opt_disk[$1]}
  case ${opt_kind[i]} in
    free)
      printf '   A new partition "%s" in this free space; nothing else on the disk changes.\n' "$LABEL"
      if [[ -n ${d_esp[$d]} ]]; then
        printf '   GRUB goes to the EFI partition %s.\n' "${d_esp[$d]#/dev/}"
      else
        printf '   The disk has no EFI partition: a %d GiB one for GRUB comes first.\n' "$ESP_GIB"
      fi
      ;;
    reinstall)
      printf '   %s is formatted again, files on it included; nothing else on the disk changes.\n' "${opt_part[i]#/dev/}"
      ;;
    wipe)
      if [[ -n ${d_parts[$d]} ]]; then
        printf '   %sEverything on %s is deleted:%s\n' "$RED" "${d#/dev/}" "$RESET"
        printf '%s' "${d_parts[$d]}" | sed 's/^/     /'
        ((d_win[$d])) && printf '   %sWindows on this disk will be gone.%s\n' "$RED" "$RESET"
      fi
      printf '   New: an EFI partition (%d GiB) and "%s" (the rest).\n' "$ESP_GIB" "$LABEL"
      ;;
  esac
}

render() {
  local sel=$1 i d hl erase label size
  printf '\e[H\e[2J'
  printf '\n  %santrel-os installer%s · where should it go?\n' "$BOLD" "$RESET"
  printf '  %s↑/↓ move · Enter choose · q quit%s\n' "$DIM" "$RESET"
  for d in "${disks[@]}"; do
    printf '\n  %s%s%s  %s · %s · %s\n' "$BOLD" "${d#/dev/}" "$RESET" "${d_model[$d]}" "$(human "${d_size[$d]}")" \
      "$(case ${d_pt[$d]} in gpt) echo GPT ;; dos) echo MBR ;; *) echo "no partition table" ;; esac)"
    hl=-1 erase=0
    if [[ ${opt_disk[sel]} == "$d" ]]; then
      hl=${opt_seg[sel]}
      [[ ${opt_kind[sel]} == wipe ]] && erase=$(wipe_style "$d")
    fi
    draw_bar "$d" "$hl" "$erase"
    for i in "${!opt_kind[@]}"; do
      [[ ${opt_disk[i]} == "$d" ]] || continue
      label=$(option_label "$i")
      size=$(human "$(option_bytes "$i")")
      if ((i == sel)); then
        printf '   %s%s► %-21s %10s  %s%s\n' "$BOLD" "$GREEN" "$label" "$size" "${opt_text[i]}" "$RESET"
      elif ((opt_ok[i])); then
        printf '     %-21s %10s  %s\n' "$label" "$size" "${opt_text[i]}"
      else
        printf '     %s%-21s %10s  %s%s\n' "$DIM" "$label" "$size" "${opt_text[i]}" "$RESET"
      fi
    done
  done
  if ((${#skipped[@]})); then
    local joined
    printf -v joined '%s, ' "${skipped[@]}"
    printf '\n  %sNot offered: %s%s\n' "$DIM" "${joined%, }" "$RESET"
  fi
  printf '\n  %s█%s EFI  %s█%s Windows  %s█%s Linux  %s█%s antrel-os  %s█%s other  %s░%s free  %s█%s chosen\n' \
    "$MAGENTA" "$RESET" "$BLUE" "$RESET" "$YELLOW" "$RESET" "$GREEN" "$RESET" "$CYAN" "$RESET" "$DIM" "$RESET" "$BOLD" "$RESET"
  printf '\n'
  explain "$sel"
}

# Next selectable option from $1 in direction $2 (±1); stays put at the ends.
move() {
  local i=$(($1 + $2))
  while ((i >= 0 && i < ${#opt_kind[@]})); do
    if ((opt_ok[i])); then
      echo "$i"
      return
    fi
    i=$((i + $2))
  done
  echo "$1"
}

choose() {
  local i key cols
  cols=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2 || true)
  bar_w=$(((${cols:-80} > 82 ? 82 : ${cols:-80}) - 6))
  # Start on the first place that keeps everything else (free space, reinstall), else the first one at all.
  if ((chosen < 0)); then
    for i in "${!opt_kind[@]}"; do
      if ((opt_ok[i])) && [[ ${opt_kind[i]} != wipe ]]; then
        chosen=$i
        break
      fi
    done
    ((chosen >= 0)) || chosen=$(move -1 1)
  fi
  printf '\e[?25l'
  while true; do
    render "$chosen"
    key=$(read_key)
    case $key in
      $'\e[A' | k) chosen=$(move "$chosen" -1) ;;
      $'\e[B' | j) chosen=$(move "$chosen" 1) ;;
      "") break ;;
      q | Q)
        printf '\e[?25h'
        die "cancelled, nothing changed"
        ;;
    esac
  done
  printf '\e[?25h'
}

# The plan for the chosen place; sets what partition() needs. Returns 1 to go back to the menu.
confirm() {
  local i=$chosen answer again expect=yes
  disk=${opt_disk[i]} kind=${opt_kind[i]} target="" esp="" new_first="" new_last="" make_esp=0
  printf '\e[H\e[2J'
  step "Plan"
  printf '  %s%s%s  %s · %s\n' "$BOLD" "${disk#/dev/}" "$RESET" "${d_model[$disk]}" "$(human "${d_size[$disk]}")"
  draw_bar "$disk" "${opt_seg[i]}" "$([[ $kind == wipe ]] && wipe_style "$disk" || echo 0)"
  echo
  case $kind in
    free)
      new_first=${opt_first[i]} new_last=${opt_last[i]} esp=${d_esp[$disk]}
      [[ -z $esp ]] && make_esp=1
      echo "  1. A new partition \"$LABEL\" in the free $(human "$(option_bytes "$i")") ${opt_text[i]}: btrfs"
      if ((make_esp)); then
        echo "  2. Before it, a new $ESP_GIB GiB EFI partition for GRUB"
      else
        echo "  2. EFI partition ${esp#/dev/}: GRUB is added; leftovers of an old Fedora (EFI/fedora) are removed"
      fi
      ;;
    reinstall)
      target=${opt_part[i]} esp=${d_esp[$disk]}
      echo "  1. ${target#/dev/} ($(human "$(option_bytes "$i")")) is formatted again: btrfs, everything on it is lost"
      echo "  2. EFI partition ${esp#/dev/}: GRUB is added"
      ;;
    wipe)
      if [[ -n ${d_parts[$disk]} ]]; then
        printf '  1. %sEVERYTHING on %s is erased:%s\n' "$RED" "${disk#/dev/}" "$RESET"
        printf '%s' "${d_parts[$disk]}" | sed 's/^/       /'
        ((d_win[$disk])) && printf '     %sWindows on this disk will be gone.%s\n' "$RED" "$RESET"
        expect=${disk#/dev/}
      else
        echo "  1. The empty disk ${disk#/dev/} gets a partition table"
      fi
      echo "  2. New partitions: EFI ($ESP_GIB GiB, for GRUB) and \"$LABEL\" (the rest): btrfs"
      ;;
  esac
  echo "  3. Arch Linux, user '$USER_NAME', this repository in /home/$USER_NAME/antrel-os, setup.sh"
  echo "  4. Boot menu: antrel-os$( ((any_windows)) && echo " and Windows")"
  if [[ $kind == wipe ]]; then
    echo "  Other disks are not touched."
  else
    echo "  Nothing else on any disk changes."
  fi
  echo
  if [[ $expect == yes ]]; then
    ask -p "Type yes to install (anything else: back to the menu): " answer
  else
    ask -p "To erase ${disk#/dev/}, type its name ($expect); anything else: back to the menu: " answer
  fi
  [[ $answer == "$expect" ]] || return 1

  while true; do
    ask -s -p "Password for $USER_NAME (also for sudo): " password
    echo
    ask -s -p "Same password again: " again
    echo
    [[ -n $password && $password == "$again" ]] && break
    warn "empty or different, once more"
  done
}

# ---- Installing ----

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

reread() {
  partprobe "$disk"
  udevadm settle
}

# The partition of $disk that starts within bytes [$1, $2].
part_in() {
  lsblk -rnpo NAME,START "$disk" | awk -v a="$1" -v b="$2" 'NF == 2 && $2 * 512 >= a && $2 * 512 <= b { print $1 }'
}

partition() {
  step "Partition"
  local ss=${d_ss[$disk]} first last esp_sectors
  case $kind in
    wipe)
      wipefs -aq "$disk"
      sgdisk -o -n "1:0:+${ESP_GIB}G" -t 1:ef00 -c 1:EFI -n 2:0:0 -t 2:8304 -c "2:$LABEL" "$disk" >/dev/null
      reread
      esp=$(part_in 0 $((ESP_GIB * GIB)))
      target=$(part_in $((ESP_GIB * GIB + 1)) "${d_size[$disk]}")
      ;;
    free)
      first=$((new_first / ss)) last=$(((new_last + 1) / ss - 1))
      if ((make_esp)); then
        esp_sectors=$((ESP_GIB * GIB / ss))
        sgdisk -n "0:$first:$((first + esp_sectors - 1))" -t 0:ef00 -c 0:EFI "$disk" >/dev/null
        reread
        esp=$(part_in "$new_first" $((new_first + ESP_GIB * GIB - 1)))
        first=$((first + esp_sectors))
      fi
      # 8304: Linux x86-64 root.
      sgdisk -n "0:$first:$last" -t 0:8304 -c "0:$LABEL" "$disk" >/dev/null
      reread
      target=$(part_in $((first * ss)) "$new_last")
      ;;
  esac
  [[ -n $target && -b $target ]] || die "the new partition did not show up"
  [[ -n $esp && -b $esp ]] || die "no EFI partition"
  if [[ $kind == wipe ]] || ((make_esp)); then
    mkfs.fat -F 32 -n EFI "$esp" >/dev/null
    ok "EFI partition $esp"
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
  ok "btrfs on $target (@ → /, @home → /home), EFI partition $esp → /efi"
}

# Fedora's boot files and boot entry, once Fedora itself is gone. Windows' EFI partition is only ~200 MB.
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
In the menu pick antrel-os$( ((any_windows)) && echo " (Windows is there too)"). Log in as $USER_NAME on the login screen: KDE Plasma starts.
EOF
}

main() {
  checks
  scan
  chosen=-1
  trap 'printf "\e[?25h"' EXIT
  while true; do
    choose
    confirm && break
  done
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
