#!/usr/bin/env bash
# Met à jour la config de toutes les clés Claude Recovery branchées sur ce poste.
# Les clés sont repérées par l'étiquette de leur partition de persistance.
set -euo pipefail

LABEL="persistence"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MNT="$(mktemp -d)"

mapfile -t PARTS < <(blkid -t LABEL="$LABEL" -o device || true)
[ ${#PARTS[@]} -gt 0 ] || { echo "Aucune clé trouvée."; exit 1; }

for part in "${PARTS[@]}"; do
  echo "→ Mise à jour de $part"
  mount "$part" "$MNT"
  dest="$MNT/home/ordi/.claude"
  mkdir -p "$dest" "$MNT/opt/ordi/hooks"
  rsync -a "$ROOT/config/CLAUDE.md" "$ROOT/config/settings.json" "$dest/"
  rsync -a "$ROOT/hooks/" "$MNT/opt/ordi/hooks/"
  sync && umount "$MNT"
done

rmdir "$MNT"
echo "${#PARTS[@]} clé(s) mise(s) à jour."
