#!/usr/bin/env bash
# First boot of a key: reads the settings left by the installer, then creates on the
# key itself the persistence partition (remembered Claude sign-in, settings, logs) and
# the "CTRL-Z" partition used by Windows mode.
#
# Started by `ctrlz` (through sudo) as long as the persistence is not active.
# It only touches the key the system booted from, and only its free space.
#
#   firstboot.sh                   full first boot
#   firstboot.sh --settings-only   only install the installer's settings (language…)
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
CR_LANG="$(cr_lang)"

[ "$(id -u)" -eq 0 ] || { t "firstboot : à lancer en root." "firstboot: must be run as root." >&2; exit 1; }

# Persistence already active: nothing to do.
mountpoint -q /etc/ctrl-z && exit 0

EDITION="$(cr_edition)"
PERSIST_SIZE_MIB="${PERSIST_SIZE_MIB:-16384}"

# --- Boot key ------------------------------------------------------------------------
PK="$(cr_boot_disk)"
if [ -z "$PK" ]; then
  [ "${1:-}" = "--settings-only" ] || t "Démarrage sans clé inscriptible (CD, image en mémoire) : pas de persistance." \
    "Booted without a writable key (CD, image in memory): no persistence."
  exit 0
fi
DISK="/dev/$PK"
if [ "$(lsblk -dno TRAN "$DISK")" != "usb" ]; then
  [ "${1:-}" = "--settings-only" ] || t "Le support de démarrage ($DISK) n'est pas une clé USB : pas de persistance." \
    "The boot device ($DISK) is not a USB key: no persistence."
  exit 0
fi

# --- Settings left by the installer ---------------------------------------------------
ISO_BYTES="$(isosize "$DISK" 2>/dev/null || echo 0)"
BLOB_OFF="$(cr_blob_find "$DISK" "$ISO_BYTES" || true)"
if [ -n "$BLOB_OFF" ]; then
  CONF="$(mktemp)"
  if cr_blob_read "$DISK" "$BLOB_OFF" > "$CONF"; then
    # Settings chosen on the key before this point (keyboard) are kept.
    keep="$(grep -E '^RECOVERY_KEYMAP=' "$CR_CONFIG" 2>/dev/null || true)"
    # The launcher runs unprivileged: it must be able to read this file back.
    install -D -m 600 -o 1000 -g 1000 "$CONF" "$CR_CONFIG"
    [ -n "$keep" ] && ! grep -q '^RECOVERY_KEYMAP=' "$CR_CONFIG" && echo "$keep" >> "$CR_CONFIG"
    # Language chosen in the installer; otherwise the one already chosen on the key.
    blob_lang="$(sed -n "s/^RECOVERY_LANG='\(fr\|en\)'$/\1/p" "$CONF" | tail -n 1)"
    if [ -n "$blob_lang" ]; then
      RECOVERY_LANG="$blob_lang"
    elif [ -n "${RECOVERY_LANG:-}" ]; then
      cr_set_lang "$RECOVERY_LANG"
    fi
    CR_LANG="$(cr_lang)"
    [ "${1:-}" = "--settings-only" ] || t "Réglages de l'installeur appliqués." "Installer settings applied."
  else
    [ "${1:-}" = "--settings-only" ] || t "Réglages de l'installeur illisibles : ils sont ignorés." \
      "Installer settings are unreadable: they are ignored."
  fi
  rm -f "$CONF"
fi

cr_use_locale

# Preliminary call from the launcher: it only wanted the settings (language included).
[ "${1:-}" = "--settings-only" ] && exit 0

# --- Is there already a persistence on the key? -----------------------------------------
if lsblk -lno LABEL,FSTYPE "$DISK" | grep -Eq '(^persistence |crypto_LUKS)'; then
  ui_msg "$(t "Une partition de persistance existe sur la clé mais n'est pas active. Redémarrez (et saisissez la phrase de passe si elle est chiffrée)." \
             "A persistence partition exists on the key but is not active. Reboot (and enter the passphrase if it is encrypted).")"
  exit 0
fi

ui_yesno "$(t "Première utilisation de cette clé.

Sans partition de persistance, rien n'est conservé d'un démarrage à l'autre (connexion au compte Claude, réglages, journaux).

Créer la persistance sur la clé maintenant ?" \
"First use of this key.

Without a persistence partition, nothing is kept from one boot to the next (Claude account sign-in, settings, logs).

Create the persistence on the key now?")" || exit 0

if [ "$(lsblk -dno PTTYPE "$DISK")" != "dos" ]; then
  ui_msg "$(t "Table de partitions inattendue sur $DISK : création abandonnée, rien n'a été modifié." \
             "Unexpected partition table on $DISK: creation aborted, nothing was changed.")"
  exit 0
fi

SECTOR=512
ISO_END=$(( (ISO_BYTES + SECTOR - 1) / SECTOR ))

# Start sector of the first partition of the given type located after the image.
part_start() {
  sfdisk -d "$DISK" 2>/dev/null \
    | sed -n 's/.*start= *\([0-9]*\), *size= *[0-9]*, *type=\([0-9a-fA-F]*\).*/\1 \2/p' \
    | awk -v t="$1" -v min="$ISO_END" '$2 == t && $1 >= min { print $1; exit }'
}
# Device of the key's partition that starts at the given sector.
dev_at() {
  local f
  for f in /sys/block/"$PK"/*/start; do
    [ -e "$f" ] || continue
    if [ "$(cat "$f")" = "$1" ]; then echo "/dev/$(basename "$(dirname "$f")")"; return 0; fi
  done
  return 1
}

P_START="$(part_start 83)"
W_START="$(part_start 7)"
if [ -n "$P_START" ] && [ -n "$W_START" ]; then
  # An earlier attempt created the partitions without finishing: pick them up.
  t "Partitions déjà créées lors d'un essai précédent : reprise." \
    "Partitions already created by an earlier attempt: resuming."
else
  # Start of the free space: after the image and after the settings block area.
  END_PARTS="$(sfdisk -l -o End "$DISK" | awk '$1 ~ /^[0-9]+$/ && $1 > m { m = $1 } END { print m + 0 }')"
  END_IMG="$ISO_END"
  [ "$END_PARTS" -gt "$END_IMG" ] && END_IMG="$END_PARTS"
  START_MIB=$(( END_IMG * SECTOR / 1048576 + 1 ))
  [ -n "$BLOB_OFF" ] && [ $(( BLOB_OFF / 1048576 + 1 )) -gt "$START_MIB" ] && START_MIB=$(( BLOB_OFF / 1048576 + 1 ))
  START_MIB=$(( START_MIB + 1 ))
  TOTAL_MIB=$(( $(blockdev --getsize64 "$DISK") / 1048576 ))
  FREE_MIB=$(( TOTAL_MIB - START_MIB - 1 ))

  if [ "$FREE_MIB" -lt 2048 ]; then
    ui_msg "$(t "Moins de 2 Go libres sur la clé : persistance impossible." \
               "Less than 2 GB free on the key: persistence is not possible.")"
    exit 0
  fi

  # The persistence is capped; the rest goes to the partition Windows can read (Windows
  # mode, present in both editions).
  [ "$PERSIST_SIZE_MIB" -gt $(( FREE_MIB / 2 )) ] && PERSIST_SIZE_MIB=$(( FREE_MIB / 2 ))
  WIN_MIB=$(( FREE_MIB - PERSIST_SIZE_MIB ))
  P_START=$(( START_MIB * 2048 ))
  W_START=$(( (START_MIB + PERSIST_SIZE_MIB) * 2048 ))
  {
    echo "start=$P_START, size=$(( PERSIST_SIZE_MIB * 2048 )), type=83"
    echo "start=$W_START, size=$(( WIN_MIB * 2048 )), type=7"
  } | sfdisk --append --force --no-reread "$DISK" >/dev/null 2>&1
  if [ "$(part_start 83)" != "$P_START" ] || [ "$(part_start 7)" != "$W_START" ]; then
    ui_msg "$(t "Création des partitions impossible sur $DISK." "Could not create the partitions on $DISK.")"
    exit 0
  fi
fi

LUKS=1
ui_yesno "$(t "Chiffrer la persistance par une phrase de passe ?

Recommandé si la clé sort de chez vous : elle contiendra la session de votre compte Claude. La phrase de passe sera demandée à chaque démarrage." \
"Encrypt the persistence with a passphrase?

Recommended if the key leaves your home: it will hold your Claude account session. The passphrase is asked at every boot.")" || LUKS=0

# The key is in use: the kernel will not re-read the whole table, so the new partitions
# are announced to it. (The hybrid image has two overlapping partitions: partx reports
# an error on those, which is harmless.)
partx -a "$DISK" >/dev/null 2>&1 || true
udevadm settle 2>/dev/null || sleep 2
PART="$(dev_at "$P_START" || true)"
WINPART="$(dev_at "$W_START" || true)"
if [ ! -b "$PART" ] || [ ! -b "$WINPART" ]; then
  ui_msg "$(t "Les nouvelles partitions ne sont pas visibles. Redémarrez la clé : la création reprendra." \
             "The new partitions are not visible. Reboot the key: the creation will resume.")"
  exit 0
fi

TARGET="$PART"
if [ "$LUKS" = 1 ]; then
  clear 2>/dev/null || true
  t "Choisissez la phrase de passe de la clé (demandée à chaque démarrage)." \
    "Choose the key's passphrase (asked at every boot)."
  t "Rien ne s'affiche pendant la saisie : c'est normal." "Nothing is shown while you type: this is normal."
  echo
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
/etc/ctrl-z
/opt/ctrl-z
/var/log/ctrl-z
EOF
# Current settings (installer, language, keyboard): they will be there at the next boot.
if [ -f "$CR_CONFIG" ]; then
  install -D -m 600 -o 1000 -g 1000 "$CR_CONFIG" "$MNT/etc/ctrl-z/config.env"
fi
sync; umount "$MNT"; rmdir "$MNT"
[ "$LUKS" = 1 ] && cryptsetup close cr-persistence
# The settings block holds tokens: erase it as soon as they are in the persistence.
[ -n "$BLOB_OFF" ] && cr_blob_erase "$DISK" "$BLOB_OFF"

mkfs.exfat -L CTRL-Z "$WINPART" >/dev/null
WMNT="$(mktemp -d)"
mount "$WINPART" "$WMNT"
mkdir -p "$WMNT/config"
cp -r "$CR_REPO/windows" "$WMNT/"
cp -r "$CR_REPO/config/windows" "$WMNT/config/"
echo "$EDITION" > "$WMNT/windows/edition.txt"
echo "$CR_LANG" > "$WMNT/windows/lang.txt"
sync; umount "$WMNT"; rmdir "$WMNT"

if ui_yesno "$(t "Persistance créée, ainsi que la partition CTRL-Z (mode Windows).

Elle sera active au PROCHAIN démarrage de la clé : la connexion au compte Claude ne sera mémorisée qu'à partir de là.

Redémarrer maintenant ?" \
"Persistence created, along with the CTRL-Z partition (Windows mode).

It becomes active at the NEXT boot of the key: the Claude account sign-in is only remembered from then on.

Reboot now?")"; then
  systemctl reboot
  sleep 30
fi
exit 0
