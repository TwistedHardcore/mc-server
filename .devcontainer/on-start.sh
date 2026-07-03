#!/usr/bin/env bash
set -uo pipefail
set +u
source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$REPO_DIR/logs"
LOG="$REPO_DIR/logs/on-start.log"
echo "[$(date -u)] on-start firing" >> "$LOG"

if ! pgrep -f "scripts/listener.py" > /dev/null; then
  setsid nohup python3 "$REPO_DIR/scripts/listener.py" >> "$LOG" 2>&1 < /dev/null &
  disown
  echo "[$(date -u)] listener launched" >> "$LOG"
fi

setsid nohup bash "$REPO_DIR/scripts/start.sh" >> "$LOG" 2>&1 < /dev/null &
disown
echo "[$(date -u)] start.sh launched (detached)" >> "$LOG"