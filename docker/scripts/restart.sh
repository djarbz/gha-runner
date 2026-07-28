#!/usr/bin/env bash

# ==========================================
# CONFIGURATION
# ==========================================
BASE_DIR="/docker/gha-runner"
LOG_TAG="gha-runner-restart"
# ==========================================

# Function to send logs to journald
# Usage: log "message" [priority]
log() {
  local msg="$1"
  local priority="${2:-user.info}" # Default to user.info if not specified

  # -t adds a tag so you can filter by it later, -s echoes to stderr as well
  # The '--' prevents logger from interpreting leading dashes in $msg as options
  logger -t "$LOG_TAG" -p "$priority" -s -- "$msg"
}

# 1. Restart Phase: Loop through all subdirectories
log "--- Starting Restart Phase ---"
for dir in "$BASE_DIR"/*/; do
  if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
    log "Restarting project in: $dir"
    if cd "$dir" && docker compose restart >/dev/null 2>&1; then
      log "Successfully triggered restart for $(basename "$dir")"
    else
      log "Failed to trigger restart for $(basename "$dir")" "user.err"
    fi
  fi
done

log "Done!"
