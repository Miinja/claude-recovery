#!/usr/bin/env bash
# Met la clé à jour : git pull du dépôt de config, puis installation de la procédure,
# des permissions et des hooks. Lancé au début de chaque session par `ordi`
# (et au démarrage par ordi-update.service). Hors ligne, la config locale est gardée.
set -u

REPO="${ORDI_REPO:-/opt/ordi/claude-recovery}"
CLAUDE_DIR="${HOME}/.claude"

# shellcheck disable=SC1091
[ -r /etc/ordi/ordi.env ] && . /etc/ordi/ordi.env

cd "$REPO" || { echo "ordi-update : dépôt introuvable ($REPO)" >&2; exit 1; }

if [ -n "${ORDI_GIT_URL:-}" ]; then
  git remote set-url origin "$ORDI_GIT_URL" 2>/dev/null || git remote add origin "$ORDI_GIT_URL"
  if GIT_TERMINAL_PROMPT=0 timeout 30 git pull --ff-only --quiet 2>/dev/null; then
    echo "Config à jour ($(git log -1 --format='%h du %cd' --date=short))."
  else
    echo "Serveur injoignable ou pull impossible : config locale conservée" \
         "($(git log -1 --format='%h du %cd' --date=short))."
  fi
else
  echo "ORDI_GIT_URL non défini dans /etc/ordi/ordi.env : pas de mise à jour."
fi

# Installation de la config dans le profil du technicien
mkdir -p "$CLAUDE_DIR" /opt/ordi/hooks
install -m 644 config/CLAUDE.md config/settings.json "$CLAUDE_DIR/"
install -m 755 hooks/*.sh /opt/ordi/hooks/

# Les interdictions sont aussi posées en paramètres gérés : elles priment sur tout
# réglage local et ne peuvent pas être levées pendant une session.
if command -v sudo >/dev/null && command -v jq >/dev/null; then
  tmp="$(mktemp)"
  if jq '{permissions: {deny: .permissions.deny}}' config/settings.json > "$tmp"; then
    sudo install -D -m 644 "$tmp" /etc/claude-code/managed-settings.json
  fi
  rm -f "$tmp"
fi
exit 0
