#!/usr/bin/env bash
# Premier démarrage d'une clé : lit les réglages déposés par l'installeur, puis crée
# sur la clé elle-même la partition de persistance (connexion Claude mémorisée,
# réglages, journaux) et la partition « CR-WINDOWS » du mode Windows.
#
# Lancé par `claude-recovery` (via sudo) tant que la persistance n'est pas active. Ne
# touche qu'à la clé sur laquelle le système a démarré, et seulement à son espace libre.
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
CR_LANG="$(cr_lang)"

[ "$(id -u)" -eq 0 ] || { t "firstboot : à lancer en root." "firstboot: must be run as root." >&2; exit 1; }

# Persistance déjà active : rien à faire.
mountpoint -q /etc/claude-recovery && exit 0

EDITION="$(cr_edition)"
PERSIST_SIZE_MIB="${PERSIST_SIZE_MIB:-16384}"

# --- Clé de démarrage ---------------------------------------------------------
SRC="$(findmnt -no SOURCE /run/live/medium 2>/dev/null || true)"
PK="$(lsblk -no PKNAME "$SRC" 2>/dev/null | head -n 1)"
if [ -z "$PK" ]; then
  t "Démarrage sans clé inscriptible (CD, image en mémoire) : pas de persistance." \
    "Booted without a writable key (CD, image in memory): no persistence."
  exit 0
fi
DISK="/dev/$PK"
if [ "$(lsblk -dno TRAN "$DISK")" != "usb" ]; then
  t "Le support de démarrage ($DISK) n'est pas une clé USB : pas de persistance." \
    "The boot device ($DISK) is not a USB key: no persistence."
  exit 0
fi

# --- Réglages déposés par l'installeur ----------------------------------------
ISO_BYTES="$(isosize "$DISK" 2>/dev/null || echo 0)"
BLOB_OFF="$(cr_blob_find "$DISK" "$ISO_BYTES" || true)"
if [ -n "$BLOB_OFF" ]; then
  CONF="$(mktemp)"
  if cr_blob_read "$DISK" "$BLOB_OFF" > "$CONF"; then
    # Le lanceur tourne sans privilèges : il doit pouvoir relire ce fichier.
    install -D -m 600 -o 1000 -g 1000 "$CONF" /etc/claude-recovery/config.env
    # Langue choisie dans l'installeur ; sinon on garde celle déjà choisie sur la clé.
    blob_lang="$(sed -n "s/^RECOVERY_LANG='\(fr\|en\)'$/\1/p" "$CONF" | tail -n 1)"
    if [ -n "$blob_lang" ]; then
      RECOVERY_LANG="$blob_lang"
    elif [ -n "${RECOVERY_LANG:-}" ]; then
      cr_set_lang "$RECOVERY_LANG"
    fi
    CR_LANG="$(cr_lang)"
    t "Réglages de l'installeur appliqués." "Installer settings applied."
  else
    t "Réglages de l'installeur illisibles : ils sont ignorés." \
      "Installer settings are unreadable: they are ignored."
  fi
  rm -f "$CONF"
fi

# --- Une persistance existe-t-elle déjà sur la clé ? ---------------------------
if lsblk -lno LABEL,FSTYPE "$DISK" | grep -Eq '(^persistence |crypto_LUKS)'; then
  t "Une partition de persistance existe sur la clé mais n'est pas active." \
    "A persistence partition exists on the key but is not active."
  t "Redémarrez (et saisissez la phrase de passe si elle est chiffrée)." \
    "Reboot (and enter the passphrase if it is encrypted)."
  exit 0
fi

echo
t "Première utilisation de cette clé." "First use of this key."
t "Sans partition de persistance, rien n'est conservé d'un démarrage à l'autre" \
  "Without a persistence partition, nothing is kept from one boot to the next"
t "(connexion au compte Claude, réglages, journaux)." \
  "(Claude account sign-in, settings, logs)."
ask answer "Créer la persistance sur la clé maintenant ? [O/n]" "Create the persistence on the key now? [Y/n]"
is_no "$answer" && exit 0

if [ "$(lsblk -dno PTTYPE "$DISK")" != "dos" ]; then
  t "Table de partitions inattendue sur $DISK : création abandonnée, rien n'a été modifié." \
    "Unexpected partition table on $DISK: creation aborted, nothing was changed."
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
  t "Moins de 2 Go libres sur la clé : persistance impossible." \
    "Less than 2 GB free on the key: persistence is not possible."
  exit 0
fi

# Persistance plafonnée ; le reste va à la partition lisible sous Windows (mode Windows,
# présent dans les deux éditions).
[ "$PERSIST_SIZE_MIB" -gt $(( FREE_MIB / 2 )) ] && PERSIST_SIZE_MIB=$(( FREE_MIB / 2 ))
WIN_MIB=$(( FREE_MIB - PERSIST_SIZE_MIB ))

ask answer "Chiffrer la persistance par une phrase de passe (recommandé) ? [O/n]" \
           "Encrypt the persistence with a passphrase (recommended)? [Y/n]"
LUKS=1; is_no "$answer" && LUKS=0

# Le bloc de réglages contient des jetons : on l'efface avant tout.
[ -n "$BLOB_OFF" ] && cr_blob_erase "$DISK" "$BLOB_OFF"

before="$(lsblk -lnpo NAME "$DISK" | wc -l)"
{
  echo "start=$(( START_MIB * 2048 )), size=$(( PERSIST_SIZE_MIB * 2048 )), type=83"
  echo "start=$(( (START_MIB + PERSIST_SIZE_MIB) * 2048 )), size=$(( WIN_MIB * 2048 )), type=7"
} | sfdisk --append --force --no-reread "$DISK" >/dev/null
partx -u "$DISK" 2>/dev/null || partprobe "$DISK" 2>/dev/null || true
sleep 2
if [ "$(lsblk -lnpo NAME "$DISK" | wc -l)" -ne $(( before + 2 )) ]; then
  t "Les nouvelles partitions ne sont pas visibles. Redémarrez la clé, puis relancez claude-recovery." \
    "The new partitions are not visible. Reboot the key, then run claude-recovery again."
  exit 0
fi
PART="$(lsblk -lnpo NAME "$DISK" | tail -n 2 | head -n 1)"
WINPART="$(lsblk -lnpo NAME "$DISK" | tail -n 1)"

TARGET="$PART"
if [ "$LUKS" = 1 ]; then
  t "Choisissez la phrase de passe de la clé (demandée à chaque démarrage) :" \
    "Choose the key's passphrase (asked at every boot):"
  until cryptsetup luksFormat --batch-mode --verify-passphrase "$PART"; do :; done
  t "Saisissez-la à nouveau pour ouvrir la partition :" "Enter it again to open the partition:"
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
# Réglages courants (installeur + langue) : ils seront là au prochain démarrage.
if [ -f /etc/claude-recovery/config.env ]; then
  install -D -m 600 -o 1000 -g 1000 /etc/claude-recovery/config.env "$MNT/etc/claude-recovery/config.env"
fi
sync; umount "$MNT"; rmdir "$MNT"
[ "$LUKS" = 1 ] && cryptsetup close cr-persistence

mkfs.exfat -L CR-WINDOWS "$WINPART" >/dev/null
WMNT="$(mktemp -d)"
mount "$WINPART" "$WMNT"
mkdir -p "$WMNT/config"
cp -r "$CR_REPO/windows" "$WMNT/"
cp -r "$CR_REPO/config/windows" "$WMNT/config/"
echo "$EDITION" > "$WMNT/windows/edition.txt"
echo "$CR_LANG" > "$WMNT/windows/lang.txt"
sync; umount "$WMNT"; rmdir "$WMNT"
t "Partition CR-WINDOWS créée (mode Windows)." "CR-WINDOWS partition created (Windows mode)."

echo
t "Persistance créée. Elle sera active au PROCHAIN démarrage de la clé :" \
  "Persistence created. It becomes active at the NEXT boot of the key:"
t "la connexion au compte Claude ne sera mémorisée qu'à partir de là." \
  "the Claude account sign-in is only remembered from then on."
ask answer "Redémarrer maintenant ? [O/n]" "Reboot now? [Y/n]"
is_no "$answer" || systemctl reboot
exit 0
