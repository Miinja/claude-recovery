#!/usr/bin/env bash
# Opens a BitLocker partition READ-ONLY for the Windows Rescue mode.
#
#   sudo bitlocker-open.sh <partition, e.g. sda3>  < key
#
# The key (48-digit recovery key, with or without dashes, or the volume's password) is
# read from standard input, never from the command line: it must not appear in the
# process list nor in any log. The launcher asks for it; Claude never handles it.
# The volume appears as /dev/mapper/ctrlz-bl-<partition>, locked read-only.
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
CR_LANG="$(cr_lang)"

[ "$(id -u)" -eq 0 ] || { t "bitlocker-open : à lancer en root." "bitlocker-open: must be run as root." >&2; exit 1; }
part="${1:-}"
case "$part" in ''|*/*) echo "Usage: bitlocker-open.sh <partition>" >&2; exit 1 ;; esac
[ -b "/dev/$part" ] || { echo "/dev/$part ?" >&2; exit 1; }
[ "$(blkid -p -o value -s TYPE "/dev/$part" 2>/dev/null)" = BitLocker ] || {
  t "/dev/$part n'est pas une partition BitLocker." "/dev/$part is not a BitLocker partition." >&2; exit 2; }

name="ctrlz-bl-$part"
[ -b "/dev/mapper/$name" ] && exit 0

IFS= read -r key || true
# A recovery key is 8 groups of 6 digits: accept it typed with spaces, dashes or nothing.
digits="$(printf '%s' "$key" | tr -cd '0-9')"
if [ "${#digits}" -eq 48 ] && [ -z "$(printf '%s' "$key" | tr -d '0-9 -')" ]; then
  key="$(printf '%s' "$digits" | sed 's/.\{6\}/&-/g; s/-$//')"
fi
printf '%s' "$key" | cryptsetup open --type bitlk --readonly --key-file=- "/dev/$part" "$name" >/dev/null 2>&1
status=$?
key=""; digits=""
if [ "$status" -eq 0 ]; then
  blockdev --setro "/dev/mapper/$name"
  udevadm settle 2>/dev/null || true
fi
exit "$status"
