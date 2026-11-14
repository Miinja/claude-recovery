#!/usr/bin/env bash
# Hook PostToolUse : journalise chaque commande lancée par Claude.
# Claude Code envoie le détail de l'appel en JSON sur stdin.
set -u

LOG_DIR="${ORDI_LOG_DIR:-/var/log/ordi}"
SERVER_URL="${ORDI_LOG_URL:-}"   # ex: https://serveur-ordi.local/api/logs (à définir)
TECH="${ORDI_TECH:-inconnu}"

mkdir -p "$LOG_DIR"
payload="$(cat)"
entry="$(jq -c --arg tech "$TECH" --arg host "$(hostname)" --arg ts "$(date -Iseconds)" \
  '{ts: $ts, tech: $tech, host: $host, command: .tool_input.command, session: .session_id}' \
  <<<"$payload" 2>/dev/null)"

[ -n "$entry" ] || exit 0
echo "$entry" >> "$LOG_DIR/commands.jsonl"

# Envoi au serveur si configuré (n'échoue jamais le job)
if [ -n "$SERVER_URL" ]; then
  curl -s -m 5 -H 'Content-Type: application/json' -d "$entry" "$SERVER_URL" >/dev/null 2>&1 || true
fi
exit 0
