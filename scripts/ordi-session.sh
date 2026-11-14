#!/usr/bin/env bash
# Lanceur de session Claude Recovery (commande `ordi` sur la clé).
#   1. met la clé à jour (git pull)
#   2. demande le technicien, la référence du job et la destination
#   3. lance Claude Code dans le dossier du job
#   4. à la fermeture : envoie les journaux en attente et le rapport au serveur
set -u

REPO="${ORDI_REPO:-/opt/ordi/claude-recovery}"
STATE="${HOME}/.config/ordi"
mkdir -p "$STATE"

"$REPO/scripts/ordi-update.sh"

# shellcheck disable=SC1091
[ -r /etc/ordi/ordi.env ] && . /etc/ordi/ordi.env

echo
echo "=== Claude Recovery — nouvelle session ==="

last_tech="$(cat "$STATE/technicien" 2>/dev/null || true)"
read -r -p "Technicien [${last_tech:-?}] : " tech
tech="${tech:-$last_tech}"
[ -n "$tech" ] || { echo "Nom du technicien obligatoire."; exit 1; }
echo "$tech" > "$STATE/technicien"

read -r -p "Référence du job (ex. dupont-hdd) : " ref
# Lettres, chiffres, point, tiret, souligné : le nom sert de dossier et d'identifiant serveur.
ref="$(printf '%s' "$ref" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48)"
[ -n "$ref" ] || { echo "Référence obligatoire."; exit 1; }

jobs_dir="${ORDI_JOBS_DIR:-/mnt/jobs}"
read -r -p "Dossier de destination des jobs [$jobs_dir] : " answer
jobs_dir="${answer:-$jobs_dir}"

if [ ! -d "$jobs_dir" ]; then
  echo "Le dossier $jobs_dir n'existe pas. Montez le support de destination, puis relancez."
  exit 1
fi
if ! mountpoint -q "$jobs_dir" && [ "$(stat -f -c %T "$jobs_dir")" = "overlayfs" ]; then
  echo "ATTENTION : $jobs_dir est sur la clé live (mémoire vive), pas sur un disque de destination."
  read -r -p "Continuer quand même ? [o/N] " ok
  [ "$ok" = "o" ] || exit 1
fi

# Reprise d'un job existant portant cette référence, sinon création datée du jour.
job_dir="$(find "$jobs_dir" -maxdepth 1 -type d -name "*_$ref" 2>/dev/null | sort | tail -n 1)"
if [ -n "$job_dir" ]; then
  echo "Reprise du job existant : $job_dir"
else
  job_dir="$jobs_dir/$(date +%F)_$ref"
  mkdir -p "$job_dir"/{image,travail,recupere} || { echo "Création impossible dans $jobs_dir."; exit 1; }
  echo "Nouveau job : $job_dir"
fi

export ORDI_TECH="$tech"
export ORDI_JOB="${job_dir##*/}"
export ORDI_JOB_DIR="$job_dir"

echo
df -h "$job_dir" | sed 's/^/  /'
echo

cd "$job_dir" || exit 1
claude "$@"
status=$?

# --- Clôture -----------------------------------------------------------------
/opt/ordi/hooks/log-command.sh --flush

if [ -n "${ORDI_LOG_URL:-}" ] && [ -s "$job_dir/rapport.md" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X PUT \
    -H "Authorization: Bearer ${ORDI_LOG_TOKEN:-}" \
    -H 'Content-Type: text/markdown; charset=utf-8' \
    --data-binary @"$job_dir/rapport.md" \
    "${ORDI_LOG_URL%/}/api/jobs/$ORDI_JOB/rapport" 2>/dev/null)" || code=000
  case "$code" in
    2*) echo "Rapport envoyé au serveur." ;;
    *)  echo "Rapport NON envoyé (HTTP $code) : il reste dans $job_dir/rapport.md." ;;
  esac
fi

if [ -s "${ORDI_LOG_DIR:-/var/log/ordi}/queue.jsonl" ] || [ -s "${ORDI_LOG_DIR:-/var/log/ordi}/queue.sending" ]; then
  echo "Des journaux attendent encore sur la clé : ils partiront à la prochaine session connectée."
fi
exit "$status"
