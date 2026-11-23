#!/usr/bin/env python3
"""Round 192: a stand-in for a local Ollama, for tools/gpu_courtesy_check.gd.
GET /api/ps lists what's loaded; POST /api/generate {"model", "keep_alive": 0} unloads it. Port from argv (default 11434).
GET /_log returns what it was asked (for the check)."""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

loaded = {"qwen3.5:9b": 14.04e9, "nomic-embed-text:latest": 0.3e9}
asked = []

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def _send(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        if self.path == "/api/ps":
            asked.append("ps")
            self._send({"models": [dict({"name": k, "model": k, "size": v, "size_vram": v}, **({"context_length": 262144} if k == "qwen3.5:9b" else {})) for k, v in loaded.items()]})
        elif self.path == "/_log":
            self._send({"asked": asked, "loaded": list(loaded)})
        elif self.path.startswith("/_load"):
            loaded["qwen3.5:9b"] = 14.04e9
            self._send({"ok": True})
        else:
            self._send({"error": "no"}, 404)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        d = json.loads(self.rfile.read(n) or b"{}")
        if self.path == "/api/generate" and d.get("keep_alive") == 0:
            asked.append("unload " + d.get("model", ""))
            loaded.pop(d.get("model", ""), None)
            self._send({"model": d.get("model"), "done": True, "done_reason": "unload"})
        else:
            self._send({"error": "no"}, 400)

HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 11434), H).serve_forever()
