#!/usr/bin/env bash
# Prépare une clé Claude Recovery : écrit l'image, puis crée
#   - la partition de persistance (login Claude mémorisé, config, journaux en attente)
#   - une partition exFAT « ORDI-WIN », lisible sous Windows, pour le mode Windows.
#
#   sudo scripts/make-key.sh build/out/claude-recovery-AAAAMMJJ.iso /dev/sdX [--luks]
#
#   --luks   chiffre la persistance (phrase de passe demandée à chaque démarrage).
#            Recommandé : la persistance contient la session Claude et les jetons.
#
# ATTENTION : efface entièrement la clé désignée.
set -euo pipefail

ISO="${1:-}"; DEV="${2:-}"; LUKS="${3:-}"
PERSIST_SIZE="${PERSIST_SIZE:-16G}"   # taille de la persistance ; le reste va au mode Windows
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)." >&2; exit 1; }
[ -f "$ISO" ] && [ -b "$DEV" ] || { echo "Usage : $0 <image.iso> </dev/sdX> [--luks]" >&2; exit 1; }
[ -z "$LUKS" ] || [ "$LUKS" = "--luks" ] || { echo "Option inconnue : $LUKS" >&2; exit 1; }

# Garde-fous : disque entier, amovible, branché en USB
[ "$(lsblk -dno TYPE "$DEV")" = "disk" ] || { echo "$DEV n'est pas un disque entier." >&2; exit 1; }
[ "$(lsblk -dno TRAN "$DEV")" = "usb" ]  || { echo "$DEV n'est pas un périphérique USB : refus." >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -q .; then
  echo "$DEV a des partitions montées : démontez-les d'abord." >&2; exit 1
fi

echo "Clé cible :"
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL "$DEV"
echo
echo "TOUT le contenu de $DEV sera effacé."
read -r -p "Pour confirmer, retapez le nom du périphérique ($DEV) : " confirm
[ "$confirm" = "$DEV" ] || { echo "Annulé."; exit 1; }

echo "→ Écriture de l'image…"
dd if="$ISO" of="$DEV" bs=4M conv=fsync status=progress
sync; partprobe "$DEV"; sleep 2

echo "→ Création des partitions : persistance (${PERSIST_SIZE}) et ORDI-WIN (reste)…"
before="$(lsblk -lnpo NAME "$DEV" | wc -l)"
echo ",${PERSIST_SIZE},L" | sfdisk --append --no-reread "$DEV"
echo ',,7' | sfdisk --append --no-reread "$DEV"
partprobe "$DEV"; sleep 2
[ "$(lsblk -lnpo NAME "$DEV" | wc -l)" -eq $((before + 2)) ] \
  || { echo "Création des partitions échouée." >&2; exit 1; }
PART="$(lsblk -lnpo NAME "$DEV" | tail -n 2 | head -n 1)"
WINPART="$(lsblk -lnpo NAME "$DEV" | tail -n 1)"

# Partition lisible sous Windows : scripts du mode Windows + journaux d'intervention
mkfs.exfat -L ORDI-WIN "$WINPART" >/dev/null
WMNT="$(mktemp -d)"
mount "$WINPART" "$WMNT"
cp -r "$ROOT/windows" "$ROOT/config" "$WMNT/"
rm -f "$WMNT/config/ordi.env"
sync; umount "$WMNT"; rmdir "$WMNT"

TARGET="$PART"
if [ "$LUKS" = "--luks" ]; then
  echo "→ Chiffrement LUKS de $PART (choisissez la phrase de passe de la clé)…"
  cryptsetup luksFormat "$PART"
  cryptsetup open "$PART" ordi-persistence
  TARGET=/dev/mapper/ordi-persistence
fi

mkfs.ext4 -q -L persistence "$TARGET"

MNT="$(mktemp -d)"
mount "$TARGET" "$MNT"
# Dossiers conservés d'un démarrage à l'autre
cat > "$MNT/persistence.conf" <<'EOF'
/home
/etc/ordi
/opt/ordi
/var/log/ordi
EOF
mkdir -p "$MNT/etc/ordi"
install -m 600 "$ROOT/config/ordi.env.example" "$MNT/etc/ordi/ordi.env"
sync; umount "$MNT"; rmdir "$MNT"
[ "$LUKS" = "--luks" ] && cryptsetup close ordi-persistence

echo
echo "Clé prête. Reste à faire au premier démarrage :"
echo "  1. sudo nano /etc/ordi/ordi.env   (nom de la clé, URL du dépôt, jeton des journaux)"
echo "  2. ordi                            (connexion au compte Claude, mémorisée ensuite)"
