#!/usr/bin/env bash
# Met à jour la config de toutes les clés Claude Recovery branchées sur ce poste,
# sans les démarrer (les clés se mettent aussi à jour seules, par git pull, à chaque
# session). Les clés sont repérées par l'étiquette de leur partition de persistance.
# Une persistance chiffrée (LUKS) doit d'abord être ouverte avec `cryptsetup open`.
set -euo pipefail

LABEL="persistence"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MNT="$(mktemp -d)"
EDITION="${1:-entreprise}"   # édition des clés branchées

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)." >&2; exit 1; }

mapfile -t PARTS < <(blkid -t LABEL="$LABEL" -o device || true)
[ ${#PARTS[@]} -gt 0 ] || { echo "Aucune clé trouvée."; rmdir "$MNT"; exit 1; }

for part in "${PARTS[@]}"; do
  echo "→ Mise à jour de $part"
  mount "$part" "$MNT"
  dest="$MNT/home/recovery/.claude"
  mkdir -p "$dest" "$MNT/opt/claude-recovery/hooks"
  # Langue de la clé : celle de son config.env, français à défaut
  key_lang="$(sed -n "s/^RECOVERY_LANG='\(fr\|en\)'$/\1/p" "$MNT/etc/claude-recovery/config.env" 2>/dev/null | tail -n 1)"
  cp "$ROOT/config/$EDITION/CLAUDE.${key_lang:-fr}.md" "$dest/CLAUDE.md"
  cp "$ROOT/config/$EDITION/settings.json" "$dest/"
  rsync -a "$ROOT/hooks/" "$MNT/opt/claude-recovery/hooks/"
  # L'utilisateur live « recovery » a l'uid 1000
  chown -R 1000:1000 "$MNT/home/recovery" "$MNT/opt/claude-recovery"
  sync && umount "$MNT"
done

rmdir "$MNT"
echo "${#PARTS[@]} clé(s) mise(s) à jour."
