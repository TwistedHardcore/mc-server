#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"
echo "[$(date -u)] stop.sh running"

# 1. Ask Minecraft to shut down cleanly (real "stop" command, not SIGTERM)
if tmux has-session -t mc 2>/dev/null; then
  tmux send-keys -t mc "stop" Enter
  for i in $(seq 1 60); do
    tmux has-session -t mc 2>/dev/null || break
    sleep 1
  done
  tmux kill-session -t mc 2>/dev/null || true
fi

# 2. Stop background loops
pkill -f "scripts/watcher.sh" 2>/dev/null || true
pkill -f "scripts/autopush.sh" 2>/dev/null || true

# 3. Final commit + push
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "final save $(date -u +%FT%TZ)"
fi
git pull --rebase origin main || true
git push origin main || echo "WARNING: final push failed"

# 4. Stop playit
pkill -f playitd 2>/dev/null || true

echo "[$(date -u)] stop.sh complete"

# 5. Stop the Codespace itself
if [ -n "${GH_TOKEN:-}" ] && [ -n "${CODESPACE_NAME:-}" ]; then
  GH_TOKEN="$GH_TOKEN" gh codespace stop -c "$CODESPACE_NAME" || true
fi