#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"
echo "[$(date -u)] start.sh running"

# 1. Sync world — commit local changes BEFORE pulling so a pull
#    never aborts on uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "autosave before pull $(date -u +%FT%TZ)"
fi
git pull --rebase origin main || echo "WARNING: pull failed, continuing with local world"

# 2. Write playit config from the Codespace secret, if not already there
sudo mkdir -p /root/.config/playit_gg
if [ -n "${PLAYIT_SECRET_TOML:-}" ] && [ ! -f /root/.config/playit_gg/playit.toml ]; then
  echo "$PLAYIT_SECRET_TOML" | sudo tee /root/.config/playit_gg/playit.toml > /dev/null
fi

# 3. Start the playit tunnel
if ! pgrep -f playitd > /dev/null; then
  sudo /usr/bin/playitd > logs/playit.log 2>&1 &
  sleep 2
  sudo chmod 666 /run/playit/playitd.sock 2>/dev/null || true
fi

# 4. Start Minecraft inside tmux (lets us send real commands later)
if ! tmux has-session -t mc 2>/dev/null; then
  cd server
  tmux new-session -d -s mc "java -Xms2G -Xmx7G -jar fabric-server-launch.jar nogui"
  cd ..
fi

# 5. Idle watcher
if ! pgrep -f "scripts/watcher.sh" > /dev/null; then
  nohup bash scripts/watcher.sh > logs/watcher.log 2>&1 &
fi

# 6. Autopush loop
if ! pgrep -f "scripts/autopush.sh" > /dev/null; then
  nohup bash scripts/autopush.sh > logs/autopush.log 2>&1 &
fi

echo "[$(date -u)] start.sh complete"