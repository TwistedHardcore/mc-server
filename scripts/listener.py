#!/usr/bin/env python3
import os, subprocess, json, time, urllib.request

WORKER_URL = os.environ.get("WORKER_URL", "").rstrip("/")
TOKEN = os.environ.get("LISTENER_TOKEN", "")
ACCOUNT_ID = os.environ.get("ACCOUNT_ID", "1")
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLL_INTERVAL = 3

def tmux_send(cmd):
    subprocess.run(["tmux", "send-keys", "-t", "mc", cmd, "Enter"])

def tmux_capture(lines=50):
    out = subprocess.run(["tmux", "capture-pane", "-t", "mc", "-p"], capture_output=True, text=True)
    return "\n".join(out.stdout.splitlines()[-lines:])

def server_running():
    r = subprocess.run(["tmux", "has-session", "-t", "mc"], capture_output=True)
    return r.returncode == 0

def http_json(url, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                  headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())

def poll():
    return http_json(f"{WORKER_URL}/poll?token={TOKEN}&account={ACCOUNT_ID}")

def send_result(request_id, content):
    http_json(f"{WORKER_URL}/result?token={TOKEN}", method="POST",
              body={"requestId": request_id, "content": content})

def handle(cmd):
    kind = cmd["type"]
    payload = cmd.get("payload", {})
    if kind == "stop":
        subprocess.Popen(["bash", os.path.join(REPO_DIR, "scripts", "stop.sh")])
        return "Stopping..."
    if kind == "status":
        return f"Running: {server_running()}"
    if kind == "logs":
        return "```\n" + tmux_capture(30)[:1800] + "\n```"
    if kind == "console":
        c = payload.get("command", "")
        if not c or not server_running():
            return "Server not running or no command given"
        tmux_send(c)
        return f"Sent: `{c}`"
    return "Unknown command"

if __name__ == "__main__":
    print(f"Listener polling {WORKER_URL} as account {ACCOUNT_ID}")
    while True:
        try:
            result = poll()
            cmd = result.get("command")
            if cmd:
                content = handle(cmd)
                send_result(cmd["requestId"], content)
        except Exception as e:
            print(f"poll error: {e}")
        time.sleep(POLL_INTERVAL)