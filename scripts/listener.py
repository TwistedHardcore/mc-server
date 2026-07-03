#!/usr/bin/env python3
import os, subprocess, json, http.server, socketserver, urllib.parse

PORT = 8787
TOKEN = os.environ.get("LISTENER_TOKEN", "")
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def tmux_send(cmd):
    subprocess.run(["tmux", "send-keys", "-t", "mc", cmd, "Enter"])

def tmux_capture(lines=50):
    out = subprocess.run(["tmux", "capture-pane", "-t", "mc", "-p"],
                          capture_output=True, text=True)
    return "\n".join(out.stdout.splitlines()[-lines:])

def server_running():
    r = subprocess.run(["tmux", "has-session", "-t", "mc"], capture_output=True)
    return r.returncode == 0

class Handler(http.server.BaseHTTPRequestHandler):
    def _auth(self):
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self._auth():
            return self._send(401, {"error": "unauthorized"})
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/status":
            self._send(200, {"running": server_running()})
        elif parsed.path == "/logs":
            qs = urllib.parse.parse_qs(parsed.query)
            n = int(qs.get("lines", ["50"])[0])
            self._send(200, {"log": tmux_capture(n)})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._auth():
            return self._send(401, {"error": "unauthorized"})
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw or b"{}")
        except Exception:
            data = {}

        if self.path == "/start":
            subprocess.Popen(["bash", os.path.join(REPO_DIR, "scripts", "start.sh")])
            self._send(200, {"status": "starting"})
        elif self.path == "/stop":
            subprocess.Popen(["bash", os.path.join(REPO_DIR, "scripts", "stop.sh")])
            self._send(200, {"status": "stopping"})
        elif self.path == "/console":
            cmd = data.get("command", "")
            if not cmd or not server_running():
                return self._send(400, {"error": "server not running or no command"})
            tmux_send(cmd)
            self._send(200, {"status": "sent"})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        pass

with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.serve_forever()