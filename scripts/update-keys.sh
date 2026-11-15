#!/usr/bin/env bash
# Updates the configuration of every Ctrl-Z key plugged into this machine,
# without booting them (keys also update themselves, by git pull, at every session).
# Keys are found by the label of their persistence partition. An encrypted (LUKS)
# persistence must be opened first with `cryptsetup open`.
set -euo pipefail

LABEL="persistence"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MNT="$(mktemp -d)"
EDITION="${1:-business}"   # edition of the plugged-in keys

[ "$(id -u)" -eq 0 ] || { echo "Must be run as root (sudo)." >&2; exit 1; }

mapfile -t PARTS < <(blkid -t LABEL="$LABEL" -o device || true)
[ ${#PARTS[@]} -gt 0 ] || { echo "No key found."; rmdir "$MNT"; exit 1; }

for part in "${PARTS[@]}"; do
  echo "→ Updating $part"
  mount "$part" "$MNT"
  dest="$MNT/home/recovery/.claude"
  mkdir -p "$dest" "$MNT/opt/ctrl-z/hooks"
  # Language of the key: the one in its config.env, French by default
  key_lang="$(sed -n "s/^RECOVERY_LANG='\(fr\|en\)'$/\1/p" "$MNT/etc/ctrl-z/config.env" 2>/dev/null | tail -n 1)"
  cp "$ROOT/config/$EDITION/CLAUDE.${key_lang:-fr}.md" "$dest/CLAUDE.md"
  cp "$ROOT/config/$EDITION/settings.json" "$dest/"
  rsync -a "$ROOT/hooks/" "$MNT/opt/ctrl-z/hooks/"
  # The live user "recovery" has uid 1000
  chown -R 1000:1000 "$MNT/home/recovery" "$MNT/opt/ctrl-z"
  sync && umount "$MNT"
done

rmdir "$MNT"
echo "${#PARTS[@]} key(s) updated."
