#!/usr/bin/env bash
# Prépare une clé Claude Recovery depuis Linux. Équivalent en ligne de commande de
# l'installeur Windows (installer/) : même image, mêmes réglages, même format.
#
#   sudo scripts/make-key.sh entreprise  /dev/sdX     # télécharge la dernière release
#   sudo scripts/make-key.sh particulier /dev/sdX
#   sudo scripts/make-key.sh chemin/vers/image.iso /dev/sdX
#
# Le script écrit l'image puis, pour l'édition entreprise, dépose les réglages saisis
# juste après elle. La partition de persistance est créée par la clé elle-même à son
# premier démarrage (scripts/firstboot.sh).
#
# ATTENTION : efface entièrement la clé désignée.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
RELEASES="https://github.com/Miinja/claude-recovery/releases/latest/download"

SRC="${1:-}"; DEV="${2:-}"
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)." >&2; exit 1; }
[ -n "$SRC" ] && [ -b "$DEV" ] || { echo "Usage : $0 <entreprise|particulier|image.iso> </dev/sdX>" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Image et édition ---------------------------------------------------------
case "$SRC" in
  entreprise|particulier)
    EDITION="$SRC"
    ISO="$TMP/claude-recovery-$EDITION.iso"
    echo "→ Téléchargement de la dernière release ($EDITION)…"
    curl -fL --progress-bar -o "$ISO" "$RELEASES/claude-recovery-$EDITION.iso"
    curl -fsSL -o "$ISO.sha256" "$RELEASES/claude-recovery-$EDITION.iso.sha256"
    ( cd "$TMP" && sha256sum -c --quiet "claude-recovery-$EDITION.iso.sha256" ) \
      || { echo "Empreinte de l'image incorrecte : téléchargement abandonné." >&2; exit 1; }
    ;;
  *)
    ISO="$SRC"
    [ -f "$ISO" ] || { echo "Image introuvable : $ISO" >&2; exit 1; }
    case "$(basename "$ISO")" in
      *entreprise*)  EDITION=entreprise ;;
      *particulier*) EDITION=particulier ;;
      *) read -r -p "Édition de cette image [entreprise/particulier] : " EDITION ;;
    esac
    ;;
esac
case "$EDITION" in entreprise|particulier) ;; *) echo "Édition inconnue." >&2; exit 1 ;; esac

# --- Garde-fous : disque entier, branché en USB, non monté --------------------
[ "$(lsblk -dno TYPE "$DEV")" = "disk" ] || { echo "$DEV n'est pas un disque entier." >&2; exit 1; }
[ "$(lsblk -dno TRAN "$DEV")" = "usb" ]  || { echo "$DEV n'est pas un périphérique USB : refus." >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -q .; then
  echo "$DEV a des partitions montées : démontez-les d'abord." >&2; exit 1
fi

# --- Réglages de l'édition entreprise -----------------------------------------
CONF=""
if [ "$EDITION" = "entreprise" ]; then
  echo
  echo "Réglages de la clé (édition entreprise). Entrée = laisser vide."
  read -r -p "Nom de l'entreprise : " company
  read -r -p "Nom de cette clé (ex. cle01) : " key_id
  read -r -p "Dépôt Forgejo de la config (vide = dépôt GitHub public) : " git_url
  read -r -p "URL du récepteur de journaux (vide = journal local seul) : " log_url
  log_token=""
  [ -z "$log_url" ] || { read -r -s -p "Jeton de cette clé pour les journaux : " log_token; echo; }
  CONF="$TMP/config.env"
  {
    echo "# Écrit par make-key.sh le $(date +%F)"
    cr_env_line RECOVERY_COMPANY   "$company"
    cr_env_line RECOVERY_KEY_ID    "$key_id"
    cr_env_line RECOVERY_GIT_URL   "$git_url"
    cr_env_line RECOVERY_LOG_URL   "$log_url"
    cr_env_line RECOVERY_LOG_TOKEN "$log_token"
    cr_env_line RECOVERY_JOBS_DIR  "/mnt/jobs"
  } > "$CONF"
fi

# --- Écriture -----------------------------------------------------------------
echo
echo "Clé cible :"
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL "$DEV"
echo
echo "TOUT le contenu de $DEV sera effacé."
read -r -p "Pour confirmer, retapez le nom du périphérique ($DEV) : " confirm
[ "$confirm" = "$DEV" ] || { echo "Annulé."; exit 1; }

echo "→ Écriture de l'image ($EDITION)…"
wipefs -aq "$DEV"
dd if="$ISO" of="$DEV" bs=4M conv=fsync status=progress

if [ -n "$CONF" ]; then
  cr_blob_write "$DEV" "$(cr_blob_offset "$(stat -c %s "$ISO")")" "$CONF"
  echo "→ Réglages déposés sur la clé."
fi
sync; partprobe "$DEV" 2>/dev/null || true

echo
echo "Clé prête. Démarrez un PC dessus et tapez : claude-recovery"
echo "Au premier démarrage, la clé crée sa partition de persistance."
