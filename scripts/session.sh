#!/usr/bin/env bash
# Lanceur de session Claude Recovery (commande `claude-recovery` sur la clé).
#
#   claude-recovery              démarre une session
#   claude-recovery lang fr|en   change la langue de la clé
#
# Une session :
#   1. premier démarrage : réglages de l'installeur, partition de persistance
#   2. met la clé à jour (git pull)
#   3. prépare le dossier de travail (job) sur le support de destination
#   4. lance Claude Code dedans
#   5. à la fermeture, édition entreprise : envoie journaux et rapport au serveur
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
# shellcheck disable=SC1091
[ -r /etc/claude-recovery/config.env ] && . /etc/claude-recovery/config.env

# --- Changement de langue -----------------------------------------------------
if [ "${1:-}" = "lang" ]; then
  if ! cr_set_lang "${2:-}"; then
    echo "Usage: claude-recovery lang fr|en"
    exit 1
  fi
  RECOVERY_LANG="$2"
  "$CR_REPO/scripts/update.sh" --install-only
  CR_LANG="$2"
  t "Langue de la clé : français." "Key language: English."
  exit 0
fi

# --- Réglages de l'installeur : lus avant toute question (ils fixent la langue) --
if [ -z "${RECOVERY_LANG:-}" ] && ! mountpoint -q /etc/claude-recovery; then
  sudo "$CR_REPO/scripts/firstboot.sh" --settings-only
  # shellcheck disable=SC1091
  [ -r /etc/claude-recovery/config.env ] && . /etc/claude-recovery/config.env
fi

# --- Langue : demandée une fois si l'installeur ne l'a pas fixée ---------------
if [ -z "${RECOVERY_LANG:-}" ]; then
  read -r -p "Langue / Language [fr/en] : " choice
  case "$choice" in en|EN|e|E) RECOVERY_LANG=en ;; fr|FR|f|F) RECOVERY_LANG=fr ;; *) RECOVERY_LANG="$(cr_lang)" ;; esac
  cr_set_lang "$RECOVERY_LANG"
fi
CR_LANG="$(cr_lang)"
export RECOVERY_LANG CR_LANG

EDITION="$(cr_edition)"
STATE="${HOME}/.config/claude-recovery"
mkdir -p "$STATE"

mountpoint -q /etc/claude-recovery || sudo RECOVERY_LANG="$RECOVERY_LANG" "$CR_REPO/scripts/firstboot.sh"
"$CR_REPO/scripts/update.sh"

# shellcheck disable=SC1091
[ -r /etc/claude-recovery/config.env ] && . /etc/claude-recovery/config.env
CR_LANG="$(cr_lang)"
export RECOVERY_LANG CR_LANG

echo
if [ "$EDITION" = "entreprise" ]; then
  t "=== Claude Recovery — édition entreprise ===" "=== Claude Recovery — business edition ==="
else
  t "=== Claude Recovery — édition particulier ===" "=== Claude Recovery — personal edition ==="
fi

if [ "$EDITION" = "entreprise" ]; then
  last_tech="$(cat "$STATE/technician" 2>/dev/null || true)"
  ask tech "Technicien [${last_tech:-?}] :" "Technician [${last_tech:-?}]:"
  tech="${tech:-$last_tech}"
  [ -n "$tech" ] || { t "Nom du technicien obligatoire." "The technician's name is required."; exit 1; }
  echo "$tech" > "$STATE/technician"
  ask ref "Référence du job (ex. dupont-hdd) :" "Job reference (e.g. smith-hdd):"
else
  tech="personal"
  t "Il vous faut un disque de destination (disque externe), différent du disque à" \
    "You need a destination drive (an external disk), different from the disk to recover"
  t "récupérer et avec plus d'espace libre que lui. Branchez-le maintenant." \
    "and with more free space than it. Plug it in now."
  ask ref "Donnez un nom à cette récupération [recovery] :" "Give this recovery a name [recovery]:"
  ref="${ref:-recovery}"
fi
# Lettres, chiffres, point, tiret, souligné : le nom sert de dossier et d'identifiant.
ref="$(printf '%s' "$ref" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48)"
[ -n "$ref" ] || { t "Référence obligatoire." "A reference is required."; exit 1; }

jobs_dir="${RECOVERY_JOBS_DIR:-/mnt/jobs}"
if [ "$EDITION" = "particulier" ] && ! mountpoint -q "$jobs_dir"; then
  echo
  t "Disques et partitions détectés :" "Detected disks and partitions:"
  lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,LABEL | sed 's/^/  /'
  echo
  t "Quelle partition du disque de DESTINATION utiliser ? (ex. sdc1)" \
    "Which partition of the DESTINATION drive should be used? (e.g. sdc1)"
  t "Elle ne sera pas effacée : un dossier y sera simplement ajouté." \
    "It will not be erased: a folder is simply added to it."
  ask dest "Partition :" "Partition:"
  dest="/dev/${dest#/dev/}"
  [ -b "$dest" ] || { t "$dest n'existe pas." "$dest does not exist."; exit 1; }
  echo
  lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$dest" | sed 's/^/  /'
  t "Cette partition va être ouverte en écriture. Si c'est le disque à récupérer," \
    "This partition is about to be opened for writing. If it is the disk to recover,"
  t "cela peut détruire ce que vous cherchez à sauver." \
    "this can destroy what you are trying to save."
  ask sure "Confirmez-vous que c'est bien le disque de DESTINATION ? [oui/N]" \
           "Do you confirm this is the DESTINATION drive? [yes/N]"
  case "$sure" in oui|Oui|OUI|yes|Yes|YES) ;; *) t "Annulé." "Cancelled."; exit 1 ;; esac
  sudo mkdir -p "$jobs_dir"
  sudo mount -o "uid=$(id -u),gid=$(id -g)" "$dest" "$jobs_dir" 2>/dev/null \
    || sudo mount "$dest" "$jobs_dir" \
    || { t "Montage de $dest impossible." "Could not mount $dest."; exit 1; }
  jobs_dir="$jobs_dir/claude-recovery"
  sudo mkdir -p "$jobs_dir" && sudo chown "$(id -u):$(id -g)" "$jobs_dir" 2>/dev/null
else
  ask answer "Dossier de destination des jobs [$jobs_dir] :" "Destination folder for jobs [$jobs_dir]:"
  jobs_dir="${answer:-$jobs_dir}"
fi

if [ ! -d "$jobs_dir" ]; then
  t "Le dossier $jobs_dir n'existe pas. Montez le support de destination, puis relancez." \
    "The folder $jobs_dir does not exist. Mount the destination drive, then start again."
  exit 1
fi
if [ "$(stat -f -c %T "$jobs_dir")" = "overlayfs" ]; then
  t "ATTENTION : $jobs_dir est sur la clé live (mémoire vive), pas sur un disque de destination." \
    "WARNING: $jobs_dir is on the live key (in memory), not on a destination drive."
  ask ok "Continuer quand même ? [o/N]" "Continue anyway? [y/N]"
  is_yes "$ok" || exit 1
fi

# Reprise d'un job existant portant cette référence, sinon création datée du jour.
job_dir="$(find "$jobs_dir" -maxdepth 1 -type d -name "*_$ref" 2>/dev/null | sort | tail -n 1)"
if [ -n "$job_dir" ]; then
  t "Reprise : $job_dir" "Resuming: $job_dir"
else
  job_dir="$jobs_dir/$(date +%F)_$ref"
  mkdir -p "$job_dir"/{image,work,recovered} \
    || { t "Création impossible dans $jobs_dir." "Could not create a folder in $jobs_dir."; exit 1; }
  t "Nouveau dossier : $job_dir" "New folder: $job_dir"
fi

export RECOVERY_EDITION="$EDITION"
export RECOVERY_COMPANY="${RECOVERY_COMPANY:-}"
export RECOVERY_TECH="$tech"
export RECOVERY_JOB="${job_dir##*/}"
export RECOVERY_JOB_DIR="$job_dir"

echo
df -h "$job_dir" | sed 's/^/  /'
echo

cd "$job_dir" || exit 1
claude "$@"
status=$?

# --- Clôture -----------------------------------------------------------------
[ "$EDITION" = "entreprise" ] || exit "$status"

/opt/claude-recovery/hooks/log-command.sh --flush

if [ -n "${RECOVERY_LOG_URL:-}" ] && [ -s "$job_dir/report.md" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X PUT \
    -H "Authorization: Bearer ${RECOVERY_LOG_TOKEN:-}" \
    -H 'Content-Type: text/markdown; charset=utf-8' \
    --data-binary @"$job_dir/report.md" \
    "${RECOVERY_LOG_URL%/}/api/jobs/$RECOVERY_JOB/report" 2>/dev/null)" || code=000
  case "$code" in
    2*) t "Rapport envoyé au serveur." "Report sent to the server." ;;
    *)  t "Rapport NON envoyé (HTTP $code) : il reste dans $job_dir/report.md." \
          "Report NOT sent (HTTP $code): it remains in $job_dir/report.md." ;;
  esac
fi

log_dir="${RECOVERY_LOG_DIR:-/var/log/claude-recovery}"
if [ -s "$log_dir/queue.jsonl" ] || [ -s "$log_dir/queue.sending" ]; then
  t "Des journaux attendent encore sur la clé : ils partiront à la prochaine session connectée." \
    "Some logs are still waiting on the key: they will be sent at the next connected session."
fi
exit "$status"
