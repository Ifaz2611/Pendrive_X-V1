#!/usr/bin/env python3
"""Pendrive_X - lightweight LAN chat page for Ollama (macOS / Linux).

Serves a small mobile-friendly chat UI and proxies requests to the
Ollama instance running on this machine. Standard library only.

Usage:
    python3 tools/lan-chat.py --port 8090 --ollama http://127.0.0.1:11434
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHAT_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Pendrive_X Chat</title>
<style>
  :root { color-scheme: dark; --bg:#0b0f14; --panel:#121924; --accent:#31d0aa; --text:#e8f0f8; --muted:#8fa3b8; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         background: radial-gradient(1200px 600px at 20% -10%, #123 0%, var(--bg) 55%);
         color:var(--text); height:100dvh; display:flex; flex-direction:column; }
  header { padding:14px 16px; display:flex; align-items:center; gap:10px;
           border-bottom:1px solid #1d2938; background:#0b0f14cc; backdrop-filter: blur(8px); }
  header .dot { width:9px; height:9px; border-radius:50%; background:var(--accent); box-shadow:0 0 12px var(--accent); }
  header h1 { font-size:15px; margin:0; font-weight:600; letter-spacing:.02em; }
  header .model { margin-left:auto; font-size:11px; color:var(--muted); max-width:45%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  main { flex:1; overflow-y:auto; padding:16px; display:flex; flex-direction:column; gap:10px; }
  .msg { max-width:86%; padding:10px 13px; border-radius:16px; line-height:1.45; font-size:15px; white-space:pre-wrap; word-wrap:break-word; }
  .user { align-self:flex-end; background:linear-gradient(135deg,#1f8f78,#2bbd99); color:#04120e; border-bottom-right-radius:5px; }
  .bot { align-self:flex-start; background:var(--panel); border:1px solid #1e2a3a; border-bottom-left-radius:5px; }
  .bot.typing { color:var(--muted); font-style:italic; }
  footer { padding:10px 12px calc(10px + env(safe-area-inset-bottom)); border-top:1px solid #1d2938; background:#0b0f14; }
  .row { display:flex; gap:8px; align-items:flex-end; }
  textarea { flex:1; resize:none; min-height:44px; max-height:140px; padding:11px 13px; border-radius:14px;
             border:1px solid #24344a; background:#0e1520; color:var(--text); font:inherit; outline:none; }
  textarea:focus { border-color:#2bbd99; }
  button { height:44px; padding:0 18px; border:0; border-radius:14px; background:var(--accent); color:#04120e;
           font-weight:700; font-size:14px; }
  button:disabled { opacity:.45; }
  .hint { text-align:center; color:var(--muted); font-size:11px; margin-top:7px; }
</style>
</head>
<body>
<header>
  <span class="dot"></span>
  <h1>Pendrive_X</h1>
  <span class="model" id="model">__MODEL__</span>
</header>
<main id="messages">
  <div class="msg bot">Hi! This chat runs on the USB computer. Ask me anything.</div>
</main>
<footer>
  <div class="row">
    <textarea id="input" rows="1" placeholder="Message..." autocomplete="off"></textarea>
    <button id="send">Send</button>
  </div>
  <div class="hint">On your local network - keep the USB computer awake</div>
</footer>
<script>
const messages = document.getElementById('messages');
const input = document.getElementById('input');
const send = document.getElementById('send');
const modelLabel = document.getElementById('model');
let model = "__MODEL__";
let busy = false;

fetch('/api/models').then(r => r.json()).then(data => {
  const models = (data.models || []).map(m => m.name);
  if (!model && models.length) model = models[0];
  if (model) modelLabel.textContent = model;
}).catch(() => {});

function bubble(text, cls) {
  const div = document.createElement('div');
  div.className = 'msg ' + cls;
  div.textContent = text;
  messages.appendChild(div);
  messages.scrollTop = messages.scrollHeight;
  return div;
}
function resize() {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 140) + 'px';
}
input.addEventListener('input', resize);
input.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
});
send.addEventListener('click', submit);

async function submit() {
  const text = input.value.trim();
  if (!text || busy) return;
  busy = true; send.disabled = true;
  input.value = ''; resize();
  bubble(text, 'user');
  const pending = bubble('Thinking...', 'bot typing');
  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ model: model, messages: [{role:'user', content:text}], stream:false })
    });
    const data = await res.json();
    pending.classList.remove('typing');
    pending.textContent = (data.message && data.message.content) || data.error || 'No response';
  } catch (err) {
    pending.classList.remove('typing');
    pending.textContent = 'Connection error: ' + err.message;
  } finally {
    busy = false; send.disabled = false; input.focus();
    messages.scrollTop = messages.scrollHeight;
  }
}
</script>
</body>
</html>
"""


class ChatHandler(BaseHTTPRequestHandler):
    server_version = "PendriveX/1.0"
    ollama_url = "http://127.0.0.1:11434"
    default_model = ""

    def log_message(self, fmt: str, *args) -> None:  # quieter console
        return

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, payload) -> None:
        self._send(status, json.dumps(payload).encode("utf-8"), "application/json; charset=utf-8")

    def _upstream(self, path: str, payload: bytes | None = None):
        url = self.ollama_url.rstrip("/") + path
        req = urllib.request.Request(url, data=payload, method="POST" if payload else "GET")
        if payload is not None:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=600) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/":
            html = CHAT_HTML.replace("__MODEL__", self.default_model)
            self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
        elif path == "/health":
            self._json(200, {"status": "ok"})
        elif path == "/api/models":
            try:
                self._json(200, self._upstream("/api/tags"))
            except Exception:
                self._json(500, {"error": "Ollama is not reachable"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if path != "/api/chat":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b"{}"
            payload = json.loads(raw.decode("utf-8"))
            if not payload.get("model") and self.default_model:
                payload["model"] = self.default_model
            payload["stream"] = False
            self._json(200, self._upstream("/api/chat", json.dumps(payload).encode("utf-8")))
        except urllib.error.URLError as exc:
            self._json(500, {"error": "Ollama is not reachable: %s" % exc})
        except Exception as exc:  # noqa: BLE001 - return error to the phone
            self._json(500, {"error": str(exc)})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pendrive_X LAN chat page")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--ollama", default="http://127.0.0.1:11434")
    parser.add_argument("--model", default="")
    args = parser.parse_args(argv)

    ChatHandler.ollama_url = args.ollama
    ChatHandler.default_model = args.model

    try:
        server = ThreadingHTTPServer((args.bind, args.port), ChatHandler)
    except OSError as exc:
        print("LAN chat error: %s" % exc, file=sys.stderr)
        return 1

    print("[OK] LAN chat page: http://%s:%d/ (proxying %s)" % (args.bind, args.port, args.ollama), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
