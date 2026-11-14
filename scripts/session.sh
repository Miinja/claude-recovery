#!/usr/bin/env bash
# Lanceur de session Claude Recovery (commande `claude-recovery` sur la clé).
#   1. premier démarrage : réglages de l'installeur, partition de persistance
#   2. met la clé à jour (git pull)
#   3. prépare le dossier de travail (job) sur le support de destination
#   4. lance Claude Code dedans
#   5. à la fermeture, édition entreprise : envoie journaux et rapport au serveur
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"

EDITION="$(cr_edition)"
STATE="${HOME}/.config/claude-recovery"
mkdir -p "$STATE"

mountpoint -q /etc/claude-recovery || sudo "$CR_REPO/scripts/firstboot.sh"
"$CR_REPO/scripts/update.sh"

# shellcheck disable=SC1091
[ -r /etc/claude-recovery/config.env ] && . /etc/claude-recovery/config.env

echo
echo "=== Claude Recovery — édition $EDITION ==="

if [ "$EDITION" = "entreprise" ]; then
  last_tech="$(cat "$STATE/technicien" 2>/dev/null || true)"
  read -r -p "Technicien [${last_tech:-?}] : " tech
  tech="${tech:-$last_tech}"
  [ -n "$tech" ] || { echo "Nom du technicien obligatoire."; exit 1; }
  echo "$tech" > "$STATE/technicien"
  read -r -p "Référence du job (ex. dupont-hdd) : " ref
else
  tech="particulier"
  echo "Il vous faut un disque de destination (disque externe), différent du disque à"
  echo "récupérer et avec plus d'espace libre que lui. Branchez-le maintenant."
  read -r -p "Donnez un nom à cette récupération [recuperation] : " ref
  ref="${ref:-recuperation}"
fi
# Lettres, chiffres, point, tiret, souligné : le nom sert de dossier et d'identifiant.
ref="$(printf '%s' "$ref" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48)"
[ -n "$ref" ] || { echo "Référence obligatoire."; exit 1; }

jobs_dir="${RECOVERY_JOBS_DIR:-/mnt/jobs}"
if [ "$EDITION" = "particulier" ] && ! mountpoint -q "$jobs_dir"; then
  echo
  echo "Disques et partitions détectés :"
  lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,LABEL | sed 's/^/  /'
  echo
  echo "Quelle partition du disque de DESTINATION utiliser ? (ex. sdc1)"
  echo "Elle ne sera pas effacée : un dossier y sera simplement ajouté."
  read -r -p "Partition : " dest
  dest="/dev/${dest#/dev/}"
  [ -b "$dest" ] || { echo "$dest n'existe pas."; exit 1; }
  echo
  lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$dest" | sed 's/^/  /'
  echo "Cette partition va être ouverte en écriture. Si c'est le disque à récupérer,"
  echo "cela peut détruire ce que vous cherchez à sauver."
  read -r -p "Confirmez-vous que c'est bien le disque de DESTINATION ? [oui/N] " sure
  [ "$sure" = "oui" ] || { echo "Annulé."; exit 1; }
  sudo mkdir -p "$jobs_dir"
  sudo mount -o "uid=$(id -u),gid=$(id -g)" "$dest" "$jobs_dir" 2>/dev/null \
    || sudo mount "$dest" "$jobs_dir" \
    || { echo "Montage de $dest impossible."; exit 1; }
  jobs_dir="$jobs_dir/claude-recovery"
  sudo mkdir -p "$jobs_dir" && sudo chown "$(id -u):$(id -g)" "$jobs_dir" 2>/dev/null
else
  read -r -p "Dossier de destination des jobs [$jobs_dir] : " answer
  jobs_dir="${answer:-$jobs_dir}"
fi

if [ ! -d "$jobs_dir" ]; then
  echo "Le dossier $jobs_dir n'existe pas. Montez le support de destination, puis relancez."
  exit 1
fi
if [ "$(stat -f -c %T "$jobs_dir")" = "overlayfs" ]; then
  echo "ATTENTION : $jobs_dir est sur la clé live (mémoire vive), pas sur un disque de destination."
  read -r -p "Continuer quand même ? [o/N] " ok
  [ "$ok" = "o" ] || exit 1
fi

# Reprise d'un job existant portant cette référence, sinon création datée du jour.
job_dir="$(find "$jobs_dir" -maxdepth 1 -type d -name "*_$ref" 2>/dev/null | sort | tail -n 1)"
if [ -n "$job_dir" ]; then
  echo "Reprise : $job_dir"
else
  job_dir="$jobs_dir/$(date +%F)_$ref"
  mkdir -p "$job_dir"/{image,travail,recupere} || { echo "Création impossible dans $jobs_dir."; exit 1; }
  echo "Nouveau dossier : $job_dir"
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

if [ -n "${RECOVERY_LOG_URL:-}" ] && [ -s "$job_dir/rapport.md" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X PUT \
    -H "Authorization: Bearer ${RECOVERY_LOG_TOKEN:-}" \
    -H 'Content-Type: text/markdown; charset=utf-8' \
    --data-binary @"$job_dir/rapport.md" \
    "${RECOVERY_LOG_URL%/}/api/jobs/$RECOVERY_JOB/rapport" 2>/dev/null)" || code=000
  case "$code" in
    2*) echo "Rapport envoyé au serveur." ;;
    *)  echo "Rapport NON envoyé (HTTP $code) : il reste dans $job_dir/rapport.md." ;;
  esac
fi

if [ -s "${RECOVERY_LOG_DIR:-/var/log/claude-recovery}/queue.jsonl" ] || [ -s "${RECOVERY_LOG_DIR:-/var/log/claude-recovery}/queue.sending" ]; then
  echo "Des journaux attendent encore sur la clé : ils partiront à la prochaine session connectée."
fi
exit "$status"
