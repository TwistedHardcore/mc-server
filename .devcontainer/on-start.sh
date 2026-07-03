#!/usr/bin/env bash
set -uo pipefail   # no -e: one hiccup here shouldn't kill the boot
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

# Port visibility can silently revert to private (a known Codespaces
# platform quirk unrelated to anything we control). Keep re-asserting
# it in the background so any reset self-heals within ~60s instead of
# surfacing as a failure the next time Discord tries to reach it.
(
  while true; do
    sleep 60
    if [ -n "${GH_TOKEN:-}" ] && [ -n "${CODESPACE_NAME:-}" ]; then
      CURRENT=$(GH_TOKEN="$GH_TOKEN" gh codespace ports -c "$CODESPACE_NAME" 2>/dev/null | grep "8787" | awk '{print $2}')
      if [ "$CURRENT" != "public" ]; then
        GH_TOKEN="$GH_TOKEN" gh codespace ports visibility 8787:public -c "$CODESPACE_NAME" >> "$LOG" 2>&1
        echo "[$(date -u)] port 8787 reverted to private, re-set to public" >> "$LOG"
      fi
    fi
  done
) >> "$LOG" 2>&1 &
disown