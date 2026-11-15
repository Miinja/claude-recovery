#!/usr/bin/env bash
# Functions shared by the key's scripts. Source it with `.`, do not run it.

CR_REPO="${CR_REPO:-/opt/ctrl-z/repo}"
CR_DEFAULT_GIT_URL="https://github.com/Miinja/ctrl-z.git"
CR_CONFIG="/etc/ctrl-z/config.env"

# Edition of the key: fixed in the image when it is built.
cr_edition() {
  local e
  e="$(cat /usr/share/ctrl-z/edition 2>/dev/null || true)"
  case "$e" in
    business|personal) echo "$e" ;;
    *) echo "business" ;;
  esac
}

# --- Settings block --------------------------------------------------------------
# The installer cannot create a Linux partition from Windows. It therefore drops the
# settings (the future /etc/ctrl-z/config.env) in a small raw block right
# after the image, on a 1 MiB boundary. On first boot the key reads it, creates its
# persistence partition, stores the settings there and erases the block.
#
#   CRCFGv01\n<size in bytes>\n<sha256 of the content>\n<content>
CR_BLOB_MAGIC="CRCFGv01"
CR_BLOB_AREA=$((1024 * 1024))     # area reserved for the block
CR_BLOB_MAX=$((60 * 1024))        # maximum size of the content

# cr_blob_offset <image size in bytes>: the next 1 MiB boundary
cr_blob_offset() {
  echo $(( ( ($1 + CR_BLOB_AREA - 1) / CR_BLOB_AREA ) * CR_BLOB_AREA ))
}

# cr_blob_write <device or file> <offset in bytes> <settings file>
cr_blob_write() {
  local target="$1" offset="$2" file="$3" size sum tmp
  size="$(stat -c %s "$file")"
  [ "$size" -le "$CR_BLOB_MAX" ] || { echo "Settings too large." >&2; return 1; }
  sum="$(sha256sum "$file" | cut -d' ' -f1)"
  tmp="$(mktemp)"
  { printf '%s\n%s\n%s\n' "$CR_BLOB_MAGIC" "$size" "$sum"; cat "$file"; } > "$tmp"
  truncate -s "$CR_BLOB_AREA" "$tmp"
  dd if="$tmp" of="$target" bs=1M seek=$((offset / CR_BLOB_AREA)) conv=notrunc,fsync status=none
  rm -f "$tmp"
}

# cr_blob_find <device or file> <starting byte>: looks for the block in the next
# 64 MiB; prints its offset and returns 0 when found.
cr_blob_find() {
  local target="$1" n first
  first=$(( $2 / CR_BLOB_AREA ))
  for n in $(seq "$first" $((first + 64))); do
    if [ "$(dd if="$target" bs=1M skip="$n" count=1 status=none 2>/dev/null | head -c 8 | tr -d '\0')" = "$CR_BLOB_MAGIC" ]; then
      echo $((n * CR_BLOB_AREA))
      return 0
    fi
  done
  return 1
}

# cr_blob_read <device or file> <offset>: prints the content if it is intact
cr_blob_read() {
  local target="$1" offset="$2" tmp size sum header
  tmp="$(mktemp)"
  dd if="$target" of="$tmp" bs=1M skip=$((offset / CR_BLOB_AREA)) count=1 status=none
  size="$(sed -n 2p "$tmp" | tr -cd '0-9')"
  sum="$(sed -n 3p "$tmp" | tr -cd 'a-f0-9')"
  if [ -z "$size" ] || [ "$size" -gt "$CR_BLOB_MAX" ]; then rm -f "$tmp"; return 1; fi
  header=$(( ${#CR_BLOB_MAGIC} + 1 + ${#size} + 1 + 64 + 1 ))
  if [ "$(tail -c +$((header + 1)) "$tmp" | head -c "$size" | sha256sum | cut -d' ' -f1)" != "$sum" ]; then
    rm -f "$tmp"; return 1
  fi
  tail -c +$((header + 1)) "$tmp" | head -c "$size"
  rm -f "$tmp"
}

# cr_blob_erase <device or file> <offset>
cr_blob_erase() {
  dd if=/dev/zero of="$1" bs=1M seek=$(( $2 / CR_BLOB_AREA )) count=1 conv=notrunc,fsync status=none
}

# cr_env_line NAME value: a `NAME='value'` line that is safe to source from a shell
cr_env_line() {
  printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
}

# --- Language ----------------------------------------------------------------------
# RECOVERY_LANG (fr or en) comes from /etc/ctrl-z/config.env: written by the
# installer, changed with `ctrlz lang fr|en`. Failing that, the system
# language is followed.
cr_lang() {
  case "${RECOVERY_LANG:-}" in
    fr|en) echo "$RECOVERY_LANG" ;;
    *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in fr*) echo fr ;; *) echo en ;; esac ;;
  esac
}

# cr_use_locale: makes the system tools (cryptsetup, mount…) speak the key's language
cr_use_locale() {
  local want=en_US.UTF-8
  [ "${CR_LANG:-en}" = "fr" ] && want=fr_FR.UTF-8
  if locale -a 2>/dev/null | grep -qi "^${want%.*}\.utf-\?8$"; then
    export LANG="$want" LANGUAGE="${want%%_*}"
    unset LC_ALL LC_MESSAGES
  fi
}

# t "texte français" "English text": prints the text in the current language (CR_LANG)
t() {
  if [ "${CR_LANG:-en}" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}

# ask VARIABLE "question française" "English question": asks, stores the answer
ask() {
  local __p
  __p="$(t "$2" "$3")"
  read -r -p "$__p " "$1"
}

# is_yes / is_no: accept oui/yes and non/no in both languages
is_yes() { case "$1" in o|O|oui|Oui|OUI|y|Y|yes|Yes|YES) return 0 ;; esac; return 1; }
is_no()  { case "$1" in n|N|non|Non|NON|no|No|NO) return 0 ;; esac; return 1; }

# cr_set_conf NAME value: stores a setting in config.env (through sudo when needed)
cr_set_conf() {
  local sudo=""
  [ "$(id -u)" -eq 0 ] || sudo="sudo"
  $sudo mkdir -p "$(dirname "$CR_CONFIG")"
  $sudo touch "$CR_CONFIG"
  $sudo sed -i "/^$1=/d" "$CR_CONFIG"
  cr_env_line "$1" "$2" | $sudo tee -a "$CR_CONFIG" >/dev/null
  # The launcher runs unprivileged: it must be able to read this file back.
  $sudo chown 1000:1000 "$CR_CONFIG"; $sudo chmod 600 "$CR_CONFIG"
}

# cr_set_lang fr|en: stores the key's language
cr_set_lang() {
  case "$1" in fr|en) ;; *) return 1 ;; esac
  cr_set_conf RECOVERY_LANG "$1"
}

# --- Keyboard -----------------------------------------------------------------------
# cr_apply_keymap <layout or layout-variant, e.g. fr, us, ch-fr>: sets the console
# keyboard for this boot. The choice itself is kept in config.env (RECOVERY_KEYMAP).
cr_apply_keymap() {
  local layout="${1%%-*}" variant="" file=/etc/default/keyboard
  case "$1" in *-*) variant="${1#*-}" ;; esac
  case "$layout" in ''|*[!a-z]*) return 1 ;; esac
  [ -f "$file" ] || return 0
  if grep -q "^XKBLAYOUT=\"$layout\"" "$file" && grep -q "^XKBVARIANT=\"$variant\"" "$file"; then return 0; fi
  sudo sed -i -e "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$layout\"/" -e "s/^XKBVARIANT=.*/XKBVARIANT=\"$variant\"/" "$file"
  sudo setupcon --keyboard-only --force >/dev/null 2>&1 || true
}

# --- Network ------------------------------------------------------------------------
# cr_online [seconds]: is the Internet reachable? Waits up to that long for the
# network to come up first (right after boot the address may not be there yet).
cr_online() {
  local wait="${1:-0}" n=0
  while :; do
    curl -fsS -m 5 -o /dev/null -I https://api.github.com 2>/dev/null && return 0
    n=$(( n + 3 ))
    [ "$n" -ge "$wait" ] && return 1
    sleep 3
  done
}

# --- Disks ---------------------------------------------------------------------------
# cr_boot_disk: name (sda, nvme0n1…) of the disk the live system booted from
cr_boot_disk() {
  local src
  src="$(findmnt -no SOURCE /run/live/medium 2>/dev/null || true)"
  [ -n "$src" ] || return 0
  lsblk -no PKNAME "$src" 2>/dev/null | head -n 1
}

# cr_list_disks <boot disk>: one line per disk that could be the one to recover,
# as  name|size|model|serial|transport . The boot key is left out.
# (Read as JSON through jq: labels and model names come from the disks themselves and
# must never be interpreted by the shell.)
cr_list_disks() {
  local name rest
  lsblk -dJo NAME,SIZE,MODEL,SERIAL,TRAN,TYPE 2>/dev/null \
    | jq -r --arg key "${1:-}" '.blockdevices[]
        | select(.type == "disk" and .name != $key and (.name | test("^(zram|fd|loop)") | not))
        | [.name, .size, (.model // ""), (.serial // ""), (.tran // "")]
        | map(tostring | gsub("[|\n\r]"; " ") | gsub("^ +| +$"; "")) | join("|")' \
    | while IFS='|' read -r name rest; do
        [ "$(cat "/sys/block/$name/size" 2>/dev/null || echo 0)" -gt 0 ] || continue
        printf '%s|%s\n' "$name" "$rest"
      done
}

# cr_list_destinations <boot disk> <disk to recover>: one line per partition that can
# receive the recovered data, as  name|size|filesystem|label|disk model . Partitions of
# the boot key and of the disk to recover are left out.
cr_list_destinations() {
  local name size fstype label disk
  lsblk -lJo NAME,SIZE,FSTYPE,LABEL,PKNAME,TYPE 2>/dev/null \
    | jq -r --arg key "${1:-}" --arg src "${2:-}" '.blockdevices[]
        | select(.type == "part" or .type == "disk")
        | (.pkname // .name) as $disk
        | select($disk != $key and ($src == "" or $disk != $src))
        | select(.fstype != null and (.fstype | test("^(vfat|exfat|ntfs|ext[234]|btrfs|xfs|f2fs|hfsplus)$")))
        | [.name, .size, .fstype, (.label // ""), $disk]
        | map(tostring | gsub("[|\n\r]"; " ")) | join("|")' \
    | while IFS='|' read -r name size fstype label disk; do
        printf '%s|%s|%s|%s|%s\n' "$name" "$size" "$fstype" "$label" \
          "$(lsblk -dno MODEL "/dev/$disk" 2>/dev/null | tr '|' ' ' | sed 's/ *$//')"
      done
}

# cr_describe_disk <name>: "model, size, S/N serial" on one line
cr_describe_disk() {
  local model size serial
  model="$(lsblk -dno MODEL "/dev/$1" 2>/dev/null | sed 's/ *$//')"
  size="$(lsblk -dno SIZE "/dev/$1" 2>/dev/null | tr -d ' ')"
  serial="$(lsblk -dno SERIAL "/dev/$1" 2>/dev/null | tr -d ' ')"
  printf '%s%s%s' "${model:+$model, }" "$size" "${serial:+, S/N $serial}"
}

# cr_lock_ro <name>: locks a disk and all its partitions read-only in the kernel, and
# checks it. From then on no command can write to it, mounting included. The lock
# lasts until the disk is unplugged or the system restarts.
cr_lock_ro() {
  local dev sudo=""
  [ "$(id -u)" -eq 0 ] || sudo="sudo"
  [ -b "/dev/$1" ] || return 1
  for dev in $(lsblk -lnpo NAME "/dev/$1"); do
    $sudo blockdev --setro "$dev" || return 1
  done
  for dev in $(lsblk -lnpo NAME "/dev/$1"); do
    [ "$($sudo blockdev --getro "$dev")" = "1" ] || return 1
  done
}

# shellcheck source=scripts/ui.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ui.sh"
