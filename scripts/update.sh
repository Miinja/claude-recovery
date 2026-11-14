#!/usr/bin/env bash
# Met la clé à jour : git pull du dépôt, puis installation de la procédure (dans la
# langue de la clé), des permissions et des hooks de l'édition. Lancé au début de chaque
# session par `claude-recovery` (et au démarrage par claude-recovery-update.service).
# Hors ligne, la version locale est gardée.
#
#   update.sh                  mise à jour + installation
#   update.sh --install-only   installation seule (après un changement de langue)
#
# Source des mises à jour : RECOVERY_GIT_URL s'il est défini dans
# /etc/claude-recovery/config.env, sinon le dépôt GitHub du projet.
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
# shellcheck disable=SC1091
[ -r /etc/claude-recovery/config.env ] && . /etc/claude-recovery/config.env

EDITION="$(cr_edition)"
CR_LANG="$(cr_lang)"
CLAUDE_DIR="${HOME}/.claude"
GIT_URL="${RECOVERY_GIT_URL:-$CR_DEFAULT_GIT_URL}"

cd "$CR_REPO" || { t "Dépôt introuvable : $CR_REPO" "Repository not found: $CR_REPO" >&2; exit 1; }

if [ "${1:-}" != "--install-only" ]; then
  git remote set-url origin "$GIT_URL" 2>/dev/null || git remote add origin "$GIT_URL"
  if GIT_TERMINAL_PROMPT=0 timeout 30 git pull --ff-only --quiet origin main 2>/dev/null; then
    v="$(git log -1 --format='%h, %cd' --date=short)"
    t "Clé à jour ($v)." "Key up to date ($v)."
  else
    v="$(git log -1 --format='%h, %cd' --date=short)"
    t "Mise à jour impossible (hors ligne ?) : version locale conservée ($v)." \
      "Update not possible (offline?): keeping the local version ($v)."
  fi
fi

# Installation de la procédure de l'édition, dans la langue de la clé
mkdir -p "$CLAUDE_DIR" /opt/claude-recovery/hooks
install -m 644 "config/$EDITION/CLAUDE.$CR_LANG.md" "$CLAUDE_DIR/CLAUDE.md"
install -m 644 "config/$EDITION/settings.json" "$CLAUDE_DIR/settings.json"
install -m 755 hooks/*.sh /opt/claude-recovery/hooks/

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
