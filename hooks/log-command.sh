#!/usr/bin/env bash
# PostToolUse hook: logs every command Claude runs.
# Claude Code sends the details of the call as JSON on stdin.
#
#   log-command.sh           hook mode (reads stdin)
#   log-command.sh --flush   empties the queue to the server
#
# Each entry is written to commands.jsonl (local archive) and to a queue sent to the
# server. Offline, the queue builds up and leaves at the next successful send. This
# script never fails: it must not block a job.
set -u

# shellcheck disable=SC1091
[ -r /etc/ctrl-z/config.env ] && . /etc/ctrl-z/config.env

LOG_DIR="${RECOVERY_LOG_DIR:-/var/log/ctrl-z}"
SERVER_URL="${RECOVERY_LOG_URL:-}"
TOKEN="${RECOVERY_LOG_TOKEN:-}"
QUEUE="$LOG_DIR/queue.jsonl"        # entries not handled yet
SENDING="$LOG_DIR/queue.sending"    # batch being sent

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

flush_queue() {
  [ -n "$SERVER_URL" ] || return 0
  (
    # Only one sender at a time.
    flock -n 8 || exit 0
    # Move the queue to the batch, under the same lock as the writes.
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
    command: (.tool_input.command
      # A BitLocker recovery key (8 groups of 6 digits) never reaches a log.
      | if type == "string" then gsub("[0-9]{6}([- ]?[0-9]{6}){7}"; "[recovery key removed]") else . end),
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
