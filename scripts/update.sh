#!/usr/bin/env bash
# Updates the key: git pull of the repository, then installs the procedure (in the
# key's language), the permissions and the hooks of the edition. Run at the start of
# every session by `ctrlz` (and at boot by ctrlz-update.service).
# Offline, the local version is kept.
#
#   update.sh                  update + install
#   update.sh --install-only   install only (after a language change)
#
# Update source: RECOVERY_GIT_URL when it is set in /etc/ctrl-z/config.env,
# otherwise the project's GitHub repository.
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
# shellcheck disable=SC1091
[ -r /etc/ctrl-z/config.env ] && . /etc/ctrl-z/config.env

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

# Install the edition's procedure, in the key's language
mkdir -p "$CLAUDE_DIR" /opt/ctrl-z/hooks
install -m 644 "config/$EDITION/CLAUDE.$CR_LANG.md" "$CLAUDE_DIR/CLAUDE.md"
install -m 644 "config/$EDITION/settings.json" "$CLAUDE_DIR/settings.json"
install -m 755 hooks/*.sh /opt/ctrl-z/hooks/

# The deny rules are also installed as managed settings: they take precedence over
# any local setting and cannot be lifted during a session.
if command -v sudo >/dev/null && command -v jq >/dev/null; then
  tmp="$(mktemp)"
  if jq '{permissions: {deny: .permissions.deny}}' "config/$EDITION/settings.json" > "$tmp"; then
    sudo install -D -m 644 "$tmp" /etc/claude-code/managed-settings.json
  fi
  rm -f "$tmp"
fi
exit 0
