#!/usr/bin/env bash
# Premier démarrage d'une clé : lit les réglages déposés par l'installeur, puis crée
# sur la clé elle-même la partition de persistance (connexion Claude mémorisée,
# réglages, journaux) et la partition « CR-WINDOWS » du mode Windows.
#
# Lancé par `claude-recovery` (via sudo) tant que la persistance n'est pas active. Ne touche
# qu'à la clé sur laquelle le système a démarré, et seulement à son espace libre.
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"

[ "$(id -u)" -eq 0 ] || { echo "firstboot : à lancer en root." >&2; exit 1; }

# Persistance déjà active : rien à faire.
mountpoint -q /etc/claude-recovery && exit 0

EDITION="$(cr_edition)"
PERSIST_SIZE_MIB="${PERSIST_SIZE_MIB:-16384}"

# --- Clé de démarrage ---------------------------------------------------------
SRC="$(findmnt -no SOURCE /run/live/medium 2>/dev/null || true)"
PK="$(lsblk -no PKNAME "$SRC" 2>/dev/null | head -n 1)"
[ -n "$PK" ] || { echo "Démarrage sans clé inscriptible (CD, image en mémoire) : pas de persistance."; exit 0; }
DISK="/dev/$PK"
if [ "$(lsblk -dno TRAN "$DISK")" != "usb" ]; then
  echo "Le support de démarrage ($DISK) n'est pas une clé USB : pas de persistance."
  exit 0
fi

# --- Réglages déposés par l'installeur ----------------------------------------
ISO_BYTES="$(isosize "$DISK" 2>/dev/null || echo 0)"
BLOB_OFF="$(cr_blob_find "$DISK" "$ISO_BYTES" || true)"
CONF=""
if [ -n "$BLOB_OFF" ]; then
  CONF="$(mktemp)"
  if cr_blob_read "$DISK" "$BLOB_OFF" > "$CONF"; then
    install -D -m 600 "$CONF" /etc/claude-recovery/config.env
    echo "Réglages de l'installeur appliqués."
  else
    echo "Réglages de l'installeur illisibles : ils sont ignorés."
    rm -f "$CONF"; CONF=""
  fi
fi

# --- Une persistance existe-t-elle déjà sur la clé ? ---------------------------
if lsblk -lno LABEL,FSTYPE "$DISK" | grep -Eq '(^persistence |crypto_LUKS)'; then
  echo "Une partition de persistance existe sur la clé mais n'est pas active."
  echo "Redémarrez (et saisissez la phrase de passe si elle est chiffrée)."
  exit 0
fi

echo
echo "Première utilisation de cette clé."
echo "Sans partition de persistance, rien n'est conservé d'un démarrage à l'autre"
echo "(connexion au compte Claude, réglages, journaux)."
read -r -p "Créer la persistance sur la clé maintenant ? [O/n] " answer
case "$answer" in n|N) exit 0 ;; esac

if [ "$(lsblk -dno PTTYPE "$DISK")" != "dos" ]; then
  echo "Table de partitions inattendue sur $DISK : création abandonnée, rien n'a été modifié."
  exit 0
fi

# Début de l'espace libre : après l'image et après la zone du bloc de réglages.
SECTOR=512
END_PARTS="$(sfdisk -l -o End "$DISK" | awk '$1 ~ /^[0-9]+$/ && $1 > m { m = $1 } END { print m + 0 }')"
END_IMG=$(( ISO_BYTES / SECTOR ))
[ "$END_PARTS" -gt "$END_IMG" ] && END_IMG="$END_PARTS"
START_MIB=$(( END_IMG * SECTOR / 1048576 + 1 ))
[ -n "$BLOB_OFF" ] && [ $(( BLOB_OFF / 1048576 + 1 )) -gt "$START_MIB" ] && START_MIB=$(( BLOB_OFF / 1048576 + 1 ))
START_MIB=$(( START_MIB + 1 ))
TOTAL_MIB=$(( $(blockdev --getsize64 "$DISK") / 1048576 ))
FREE_MIB=$(( TOTAL_MIB - START_MIB - 1 ))

if [ "$FREE_MIB" -lt 2048 ]; then
  echo "Moins de 2 Go libres sur la clé : persistance impossible."
  exit 0
fi

# Persistance plafonnée ; le reste va à la partition lisible sous Windows (mode Windows,
# présent dans les deux éditions).
[ "$PERSIST_SIZE_MIB" -gt $(( FREE_MIB / 2 )) ] && PERSIST_SIZE_MIB=$(( FREE_MIB / 2 ))
WIN_MIB=$(( FREE_MIB - PERSIST_SIZE_MIB ))

read -r -p "Chiffrer la persistance par une phrase de passe (recommandé) ? [O/n] " answer
LUKS=1; case "$answer" in n|N) LUKS=0 ;; esac

# Le bloc de réglages contient des jetons : on l'efface avant tout.
[ -n "$BLOB_OFF" ] && cr_blob_erase "$DISK" "$BLOB_OFF"

before="$(lsblk -lnpo NAME "$DISK" | wc -l)"
{
  echo "start=$(( START_MIB * 2048 )), size=$(( PERSIST_SIZE_MIB * 2048 )), type=83"
  [ "$WIN_MIB" -gt 0 ] && echo "start=$(( (START_MIB + PERSIST_SIZE_MIB) * 2048 )), size=$(( WIN_MIB * 2048 )), type=7"
} | sfdisk --append --force --no-reread "$DISK" >/dev/null
partx -u "$DISK" 2>/dev/null || partprobe "$DISK" 2>/dev/null || true
sleep 2
expected=$(( before + 1 )); [ "$WIN_MIB" -gt 0 ] && expected=$(( before + 2 ))
if [ "$(lsblk -lnpo NAME "$DISK" | wc -l)" -ne "$expected" ]; then
  echo "Les nouvelles partitions ne sont pas visibles. Redémarrez la clé, puis relancez claude-recovery."
  exit 0
fi
if [ "$WIN_MIB" -gt 0 ]; then
  PART="$(lsblk -lnpo NAME "$DISK" | tail -n 2 | head -n 1)"
  WINPART="$(lsblk -lnpo NAME "$DISK" | tail -n 1)"
else
  PART="$(lsblk -lnpo NAME "$DISK" | tail -n 1)"
  WINPART=""
fi

TARGET="$PART"
if [ "$LUKS" = 1 ]; then
  echo "Choisissez la phrase de passe de la clé (demandée à chaque démarrage) :"
  until cryptsetup luksFormat --batch-mode --verify-passphrase "$PART"; do :; done
  echo "Saisissez-la à nouveau pour ouvrir la partition :"
  until cryptsetup open "$PART" cr-persistence; do :; done
  TARGET=/dev/mapper/cr-persistence
fi
mkfs.ext4 -q -L persistence "$TARGET"

MNT="$(mktemp -d)"
mount "$TARGET" "$MNT"
cat > "$MNT/persistence.conf" <<'EOF'
/home
/etc/claude-recovery
/opt/claude-recovery
/var/log/claude-recovery
EOF
if [ -n "$CONF" ]; then
  install -D -m 600 "$CONF" "$MNT/etc/claude-recovery/config.env"
  rm -f "$CONF"
fi
sync; umount "$MNT"; rmdir "$MNT"
[ "$LUKS" = 1 ] && cryptsetup close cr-persistence

if [ -n "$WINPART" ]; then
  mkfs.exfat -L CR-WINDOWS "$WINPART" >/dev/null
  WMNT="$(mktemp -d)"
  mount "$WINPART" "$WMNT"
  mkdir -p "$WMNT/config"
  cp -r "$CR_REPO/windows" "$WMNT/"
  cp -r "$CR_REPO/config/windows" "$WMNT/config/"
  echo "$EDITION" > "$WMNT/windows/edition.txt"
  sync; umount "$WMNT"; rmdir "$WMNT"
  echo "Partition CR-WINDOWS créée (mode Windows)."
fi

echo
echo "Persistance créée. Elle sera active au PROCHAIN démarrage de la clé :"
echo "la connexion au compte Claude ne sera mémorisée qu'à partir de là."
read -r -p "Redémarrer maintenant ? [O/n] " answer
case "$answer" in n|N) ;; *) systemctl reboot ;; esac
exit 0
