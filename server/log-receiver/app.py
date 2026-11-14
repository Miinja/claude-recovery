#!/usr/bin/env python3
"""Claude Recovery log receiver (standard library only).

  GET  /healthz                   service status
  POST /api/logs                  JSON lines (NDJSON), one per command
  PUT  /api/jobs/<job>/report     end-of-job report.md

Authentication: `Authorization: Bearer <token>` header, one token per USB key,
declared in the tokens file (`key_name token`, one key per line).
Storage: <DATA>/<job>/commands.jsonl and <DATA>/<job>/report.md.
"""
import hmac
import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA = Path(os.environ.get("RECEIVER_DATA_DIR", "/data"))
TOKENS_FILE = Path(os.environ.get("RECEIVER_TOKENS_FILE", "/config/tokens.txt"))
PORT = int(os.environ.get("RECEIVER_PORT", "8080"))
MAX_LOG_BYTES = 4 * 1024 * 1024
MAX_REPORT_BYTES = 5 * 1024 * 1024
MIN_TOKEN_LEN = 24
PLACEHOLDER = "REPLACE_"          # unchanged example value from tokens.example

SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
REPORT_PATH = re.compile(r"^/api/jobs/([^/]+)/report$")
write_lock = threading.Lock()


def load_tokens():
    """Re-read on every request: adding or revoking a key needs no restart."""
    tokens = {}
    try:
        for line in TOKENS_FILE.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            parts = line.split()
            if (
                len(parts) == 2
                and SAFE_NAME.match(parts[0])
                and len(parts[1]) >= MIN_TOKEN_LEN
                and not parts[1].startswith(PLACEHOLDER)
            ):
                tokens[parts[0]] = parts[1]
    except OSError:
        pass
    return tokens


def job_name(value):
    return value if isinstance(value, str) and SAFE_NAME.match(value) else "no-job"


class Handler(BaseHTTPRequestHandler):
    server_version = "claude-recovery-logs/1"

    def reply(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def key_name(self):
        """Name of the authenticated USB key, or None."""
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return None
        given = header[7:].strip().encode("utf-8")
        found = None
        for name, token in load_tokens().items():
            # Constant-time comparison, no early exit.
            if hmac.compare_digest(given, token.encode("utf-8")):
                found = name
        return found

    def read_body(self, limit):
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self.reply(411, {"error": "Content-Length required"})
            return None
        if length < 0 or length > limit:
            self.reply(413, {"error": "body too large"})
            return None
        return self.rfile.read(length)

    def do_GET(self):
        if self.path == "/healthz":
            self.reply(200, {"status": "ok", "keys": len(load_tokens())})
        else:
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/logs":
            return self.reply(404, {"error": "not found"})
        key = self.key_name()
        if key is None:
            return self.reply(401, {"error": "invalid token"})
        body = self.read_body(MAX_LOG_BYTES)
        if body is None:
            return
        received = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        by_job, rejected = {}, 0
        for raw in body.decode("utf-8", errors="replace").splitlines():
            if not raw.strip():
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                rejected += 1
                continue
            if not isinstance(entry, dict):
                rejected += 1
                continue
            # The key name comes from the token, not from what the key claims.
            entry["key"] = key
            entry["received"] = received
            by_job.setdefault(job_name(entry.get("job")), []).append(
                json.dumps(entry, ensure_ascii=False)
            )
        with write_lock:
            for job, lines in by_job.items():
                folder = DATA / job
                folder.mkdir(parents=True, exist_ok=True)
                with open(folder / "commands.jsonl", "a", encoding="utf-8") as out:
                    out.write("\n".join(lines) + "\n")
        self.reply(200, {"accepted": sum(len(v) for v in by_job.values()), "rejected": rejected})

    def do_PUT(self):
        match = REPORT_PATH.match(self.path)
        if not match:
            return self.reply(404, {"error": "not found"})
        key = self.key_name()
        if key is None:
            return self.reply(401, {"error": "invalid token"})
        if not SAFE_NAME.match(match.group(1)):
            return self.reply(400, {"error": "invalid job reference"})
        body = self.read_body(MAX_REPORT_BYTES)
        if body is None:
            return
        folder = DATA / match.group(1)
        target = folder / "report.md"
        with write_lock:
            folder.mkdir(parents=True, exist_ok=True)
            if target.exists():
                # Earlier versions are kept: a report is never overwritten.
                target.rename(folder / f"report.{time.strftime('%Y%m%d-%H%M%S')}.md")
            target.write_bytes(body)
        self.reply(200, {"job": match.group(1), "bytes": len(body), "key": key})

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    DATA.mkdir(parents=True, exist_ok=True)
    print(f"log receiver: listening on :{PORT}, data in {DATA}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
