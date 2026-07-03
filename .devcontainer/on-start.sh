#!/usr/bin/env bash
set -uo pipefail   # no -e: one hiccup here shouldn't kill the boot

set +u
source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$REPO_DIR/logs"
LOG="$REPO_DIR/logs/on-start.log"
echo "[$(date -u)] on-start firing" >> "$LOG"

# Launch the management listener if it isn't already up
if ! pgrep -f "scripts/listener.py" > /dev/null; then
  nohup python3 "$REPO_DIR/scripts/listener.py" >> "$LOG" 2>&1 &
  echo "[$(date -u)] listener launched, pid $!" >> "$LOG"
fi

# Make the listener's port public so the Worker can reach it.
# The port-forwarding service needs a moment to register the port
# after the listener starts, so retry a few times.
if [ -n "${GH_TOKEN:-}" ] && [ -n "${CODESPACE_NAME:-}" ]; then
  for attempt in 1 2 3 4 5; do
    if GH_TOKEN="$GH_TOKEN" gh codespace ports visibility 8787:public -c "$CODESPACE_NAME" >> "$LOG" 2>&1; then
      echo "[$(date -u)] port 8787 set to public on attempt $attempt" >> "$LOG"
      break
    fi
    echo "[$(date -u)] port visibility attempt $attempt failed, retrying in 5s" >> "$LOG"
    sleep 5
  done
fi
# Actually launch the Minecraft server + watcher + autopush
bash "$REPO_DIR/scripts/start.sh" >> "$LOG" 2>&1 &