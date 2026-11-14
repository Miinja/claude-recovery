#!/usr/bin/env bash
# Met la clé à jour : git pull du dépôt de config, puis installation de la procédure,
# des permissions et des hooks de l'édition de la clé. Lancé au début de chaque session
# par `ordi` (et au démarrage par ordi-update.service). Hors ligne, la config locale
# est gardée.
#
# Source des mises à jour : ORDI_GIT_URL (le Forgejo de l'entreprise) s'il est défini
# dans /etc/ordi/ordi.env, sinon le dépôt GitHub public du projet.
set -u

# shellcheck source=scripts/ordi-lib.sh
. "$(dirname "$(readlink -f "$0")")/ordi-lib.sh"
# shellcheck disable=SC1091
[ -r /etc/ordi/ordi.env ] && . /etc/ordi/ordi.env

EDITION="$(ordi_edition)"
CLAUDE_DIR="${HOME}/.claude"
GIT_URL="${ORDI_GIT_URL:-$ORDI_DEFAULT_GIT_URL}"

cd "$ORDI_REPO" || { echo "ordi-update : dépôt introuvable ($ORDI_REPO)" >&2; exit 1; }

git remote set-url origin "$GIT_URL" 2>/dev/null || git remote add origin "$GIT_URL"
if GIT_TERMINAL_PROMPT=0 timeout 30 git pull --ff-only --quiet origin main 2>/dev/null; then
  echo "Clé à jour ($(git log -1 --format='%h du %cd' --date=short))."
else
  echo "Mise à jour impossible (hors ligne ?) : version locale conservée" \
       "($(git log -1 --format='%h du %cd' --date=short))."
fi

# Installation de la config de l'édition dans le profil
mkdir -p "$CLAUDE_DIR" /opt/ordi/hooks
install -m 644 "config/$EDITION/CLAUDE.md" "config/$EDITION/settings.json" "$CLAUDE_DIR/"
install -m 755 hooks/*.sh /opt/ordi/hooks/

# Les interdictions sont aussi posées en paramètres gérés : elles priment sur tout
# réglage local et ne peuvent pas être levées pendant une session.
if command -v sudo >/dev/null && command -v jq >/dev/null; then
  tmp="$(mktemp)"
  if jq '{permissions: {deny: .permissions.deny}}' "config/$EDITION/settings.json" > "$tmp"; then
    sudo install -D -m 644 "$tmp" /etc/claude-code/managed-settings.json
  fi
  rm -f "$tmp"
fi
exit 0
