#!/usr/bin/env bash
# Prepares a Claude Recovery key from Linux. Command-line equivalent of the Windows
# installer (installer/): same image, same settings, same format.
#
#   sudo scripts/make-key.sh entreprise  /dev/sdX [fr|en]   # downloads the latest release
#   sudo scripts/make-key.sh particulier /dev/sdX [fr|en]
#   sudo scripts/make-key.sh path/to/image.iso /dev/sdX [fr|en]
#
# The third argument is the key's language (default: this machine's). The script
# writes the image, then drops the settings (language, and the business edition's
# settings) right after it. The persistence partition is created by the key itself on
# its first boot (scripts/firstboot.sh).
#
# WARNING: completely erases the given key.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
RELEASES="https://github.com/Miinja/claude-recovery/releases/latest/download"
CR_LANG="$(cr_lang)"          # language of this script's messages

SRC="${1:-}"; DEV="${2:-}"; KEY_LANG="${3:-$CR_LANG}"
[ "$(id -u)" -eq 0 ] || { t "À lancer en root (sudo)." "Must be run as root (sudo)." >&2; exit 1; }
if [ -z "$SRC" ] || [ ! -b "$DEV" ]; then
  echo "Usage: $0 <entreprise|particulier|image.iso> </dev/sdX> [fr|en]" >&2; exit 1
fi
case "$KEY_LANG" in fr|en) ;; *) echo "Usage: $0 <entreprise|particulier|image.iso> </dev/sdX> [fr|en]" >&2; exit 1 ;; esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Image and edition --------------------------------------------------------
case "$SRC" in
  entreprise|particulier)
    EDITION="$SRC"
    ISO="$TMP/claude-recovery-$EDITION.iso"
    t "→ Téléchargement de la dernière release ($EDITION)…" "→ Downloading the latest release ($EDITION)…"
    curl -fL --progress-bar -o "$ISO" "$RELEASES/claude-recovery-$EDITION.iso"
    curl -fsSL -o "$ISO.sha256" "$RELEASES/claude-recovery-$EDITION.iso.sha256"
    if ! ( cd "$TMP" && sha256sum -c --quiet "claude-recovery-$EDITION.iso.sha256" ); then
      t "Empreinte de l'image incorrecte : téléchargement abandonné." \
        "Wrong image checksum: download discarded." >&2
      exit 1
    fi
    ;;
  *)
    ISO="$SRC"
    [ -f "$ISO" ] || { t "Image introuvable : $ISO" "Image not found: $ISO" >&2; exit 1; }
    case "$(basename "$ISO")" in
      *entreprise*)  EDITION=entreprise ;;
      *particulier*) EDITION=particulier ;;
      *) ask EDITION "Édition de cette image [entreprise/particulier] :" "Edition of this image [entreprise/particulier]:" ;;
    esac
    ;;
esac
case "$EDITION" in entreprise|particulier) ;; *) t "Édition inconnue." "Unknown edition." >&2; exit 1 ;; esac

# --- Guards: whole disk, plugged in over USB, not mounted ----------------------
[ "$(lsblk -dno TYPE "$DEV")" = "disk" ] || { t "$DEV n'est pas un disque entier." "$DEV is not a whole disk." >&2; exit 1; }
[ "$(lsblk -dno TRAN "$DEV")" = "usb" ]  || { t "$DEV n'est pas un périphérique USB : refus." "$DEV is not a USB device: refusing." >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -q .; then
  t "$DEV a des partitions montées : démontez-les d'abord." "$DEV has mounted partitions: unmount them first." >&2
  exit 1
fi

# --- Settings -----------------------------------------------------------------
CONF="$TMP/config.env"
{
  echo "# make-key.sh $(date +%F)"
  cr_env_line RECOVERY_LANG "$KEY_LANG"
} > "$CONF"
if [ "$EDITION" = "entreprise" ]; then
  echo
  t "Réglages de la clé (édition entreprise). Entrée = laisser vide." \
    "Key settings (business edition). Enter = leave empty."
  ask company "Nom de l'entreprise :" "Company name:"
  ask key_id  "Nom de cette clé (ex. cle01) :" "Name of this key (e.g. key01):"
  ask log_url "Serveur de journaux (vide = journal sur la clé seulement) :" "Log server (empty = logs stay on the key only):"
  log_token=""
  if [ -n "$log_url" ]; then
    p="$(t "Jeton de cette clé pour le serveur de journaux :" "This key's token for the log server:")"
    read -r -s -p "$p " log_token; echo
  fi
  ask git_url "Dépôt de mise à jour (vide = dépôt GitHub du projet) :" "Update repository (empty = the project's GitHub repository):"
  {
    cr_env_line RECOVERY_COMPANY   "$company"
    cr_env_line RECOVERY_KEY_ID    "$key_id"
    cr_env_line RECOVERY_GIT_URL   "$git_url"
    cr_env_line RECOVERY_LOG_URL   "$log_url"
    cr_env_line RECOVERY_LOG_TOKEN "$log_token"
    cr_env_line RECOVERY_JOBS_DIR  "/mnt/jobs"
  } >> "$CONF"
fi

# --- Writing ------------------------------------------------------------------
echo
t "Clé cible :" "Target key:"
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL "$DEV"
echo
t "TOUT le contenu de $DEV sera effacé." "ALL content of $DEV will be erased."
ask confirm "Pour confirmer, retapez le nom du périphérique ($DEV) :" "To confirm, type the device name again ($DEV):"
[ "$confirm" = "$DEV" ] || { t "Annulé." "Cancelled."; exit 1; }

t "→ Écriture de l'image ($EDITION)…" "→ Writing the image ($EDITION)…"
wipefs -aq "$DEV"
dd if="$ISO" of="$DEV" bs=4M conv=fsync status=progress

cr_blob_write "$DEV" "$(cr_blob_offset "$(stat -c %s "$ISO")")" "$CONF"
t "→ Réglages déposés sur la clé." "→ Settings written to the key."
sync; partprobe "$DEV" 2>/dev/null || true

echo
t "Clé prête. Démarrez un PC dessus et tapez : claude-recovery" \
  "Key ready. Boot a PC from it and type: claude-recovery"
t "Au premier démarrage, la clé crée sa partition de persistance." \
  "On first boot, the key creates its persistence partition."
