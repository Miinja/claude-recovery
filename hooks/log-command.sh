#!/usr/bin/env bash
# Hook PostToolUse : journalise chaque commande lancée par Claude.
# Claude Code envoie le détail de l'appel en JSON sur stdin.
#
#   log-command.sh           mode hook (lit stdin)
#   log-command.sh --flush   vide la file d'attente vers le serveur
#
# Chaque entrée est écrite dans commands.jsonl (archive locale) et dans une file
# d'attente envoyée au serveur. Hors ligne, la file s'accumule et part au prochain
# envoi réussi. Ce script n'échoue jamais : il ne doit pas bloquer un job.
set -u

# shellcheck disable=SC1091
[ -r /etc/claude-recovery/config.env ] && . /etc/claude-recovery/config.env

LOG_DIR="${RECOVERY_LOG_DIR:-/var/log/claude-recovery}"
SERVER_URL="${RECOVERY_LOG_URL:-}"
TOKEN="${RECOVERY_LOG_TOKEN:-}"
QUEUE="$LOG_DIR/queue.jsonl"        # entrées pas encore prises en charge
SENDING="$LOG_DIR/queue.sending"    # lot en cours d'envoi

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

flush_queue() {
  [ -n "$SERVER_URL" ] || return 0
  (
    # Un seul expéditeur à la fois.
    flock -n 8 || exit 0
    # Bascule de la file vers le lot, sous le même verrou que les écritures.
    (
      flock -w 5 9 || exit 0
      if [ -s "$QUEUE" ]; then
        cat "$QUEUE" >> "$SENDING" && : > "$QUEUE"
      fi
    ) 9>"$LOG_DIR/.queue.lock"
    [ -s "$SENDING" ] || exit 0
    code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/x-ndjson' \
      --data-binary @"$SENDING" "${SERVER_URL%/}/api/logs" 2>/dev/null)" || code=000
    case "$code" in
      2*) rm -f "$SENDING" ;;
    esac
  ) 8>"$LOG_DIR/.send.lock"
}

if [ "${1:-}" = "--flush" ]; then
  flush_queue
  exit 0
fi

payload="$(cat)"
entry="$(jq -c \
  --arg ts "$(date -Iseconds)" \
  --arg tech "${RECOVERY_TECH:-unknown}" \
  --arg job "${RECOVERY_JOB:-no-job}" \
  --arg key "${RECOVERY_KEY_ID:-}" \
  --arg host "$(hostname)" \
  '{ts: $ts, tech: $tech, job: $job, key: $key, host: $host,
    session: .session_id, cwd: .cwd, tool: .tool_name,
    command: .tool_input.command,
    interrupted: (.tool_response.interrupted // false)}' \
  <<<"$payload" 2>/dev/null)"

[ -n "$entry" ] || exit 0

(
  flock -w 5 9 || exit 0
  echo "$entry" >> "$LOG_DIR/commands.jsonl"
  echo "$entry" >> "$QUEUE"
) 9>"$LOG_DIR/.queue.lock"

flush_queue
exit 0
