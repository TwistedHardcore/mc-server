#!/usr/bin/env bash
set -uo pipefail
set +u
source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$REPO_DIR/logs"
LOG="$REPO_DIR/logs/on-start.log"
echo "[$(date -u)] on-start firing" >> "$LOG"

# Launch the listener immediately, fully detached
if ! pgrep -f "scripts/listener.py" > /dev/null; then
  nohup python3 "$REPO_DIR/scripts/listener.py" >> "$LOG" 2>&1 &
  disown
  echo "[$(date -u)] listener launched" >> "$LOG"
fi

# Launch Minecraft immediately too, fully detached — don't wait on
# anything else first, in case this script gets cut off early
nohup bash "$REPO_DIR/scripts/start.sh" >> "$LOG" 2>&1 &
disown
echo "[$(date -u)] start.sh launched (detached)" >> "$LOG"

# Port visibility as its own fully independent background job, so it
# can keep retrying even if this parent script gets torn down
(
  if [ -n "${GH_TOKEN:-}" ] && [ -n "${CODESPACE_NAME:-}" ]; then
    for attempt in $(seq 1 20); do
      if GH_TOKEN="$GH_TOKEN" gh codespace ports -c "$CODESPACE_NAME" 2>>"$LOG" | grep -q "8787"; then
        echo "[$(date -u)] port 8787 detected after $attempt check(s)" >> "$LOG"
        break
      fi
      sleep 5
    done
    for attempt in 1 2 3 4 5; do
      if GH_TOKEN="$GH_TOKEN" gh codespace ports visibility 8787:public -c "$CODESPACE_NAME" >> "$LOG" 2>&1; then
        echo "[$(date -u)] port 8787 set to public on attempt $attempt" >> "$LOG"
        break
      fi
      sleep 5
    done
  fi
) >> "$LOG" 2>&1 &
disown