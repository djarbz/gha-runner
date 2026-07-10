#!/usr/bin/env bash
set -e

# ==========================================
# CONFIGURATION
# ==========================================
RETENTION_DAYS=30
GLOBAL_REGISTRY_DIR="/docker/global-registry"
# ==========================================

# Dynamically calculate total hours for the Docker logs query
RETENTION_HOURS=$((RETENTION_DAYS * 24))

# Navigate to your new global docker-compose directory
cd "$GLOBAL_REGISTRY_DIR"

echo "=== Starting Smart Build Cache & Host Pruning Routine ==="
echo "Configured Retention Period: ${RETENTION_DAYS} Days (${RETENTION_HOURS} Hours)"
echo "------------------------------------------------"

# 1. Scan registry logs from the configured retention window
echo "Analyzing registry traffic logs..."
ACTIVE_CACHES=$(docker compose logs --since "${RETENTION_HOURS}h" registry | grep -oE '/v2/cache/[a-zA-Z0-9._-]+' | cut -d'/' -f3 | sort -u)

echo "The following caches show recent activity and will be KEPT:"
if [ -n "$ACTIVE_CACHES" ]; then
  echo "$ACTIVE_CACHES" | sed 's/^/ - cache\//'
else
  echo " - No active caches found."
fi
echo "------------------------------------------------"

# 2. Fetch all existing cache directories inside the registry container
ALL_CACHES=$(docker compose exec -T registry sh -c 'ls /var/lib/registry/docker/registry/v2/repositories/cache 2>/dev/null' || true)

# 3. Evaluate each cache directory
for repo in $ALL_CACHES; do
  # Check if the repository name is in our active logs list
  if echo "$ACTIVE_CACHES" | grep -Fxq "$repo"; then
    echo "Keeping active cache (recently pulled/referenced): cache/$repo"
    continue
  fi

  # Safety Check: If it wasn't in the logs, check if it was pushed to within the retention window
  IS_RECENTLY_PUSHED=$(docker compose exec -T registry sh -c "find /var/lib/registry/docker/registry/v2/repositories/cache/$repo/_manifests -mtime -${RETENTION_DAYS} 2>/dev/null" || true)
  if [ -n "$IS_RECENTLY_PUSHED" ]; then
    echo "Keeping active cache (recently pushed): cache/$repo"
    continue
  fi

  # If it fails both checks, it is genuinely abandoned[
  echo "❌ Removing dead cache repository: cache/$rep"
  docker compose exec -T registry rm -rf "/var/lib/registry/docker/registry/v2/repositories/cache/$repo"
done

# 4. Run the native registry garbage collector to free up actual disk space
echo "Checking registry state for Garbage Collection..."
if docker compose exec -T registry sh -c '[ -d /var/lib/registry/docker/registry/v2/repositories ]'; then
  echo "Running Registry Garbage Collection to free up disk space..."
  docker compose exec -T registry registry garbage-collect /etc/docker/registry/config.yml
else
  echo "Registry repositories directory not found (registry is likely empty). Skipping GC."
fi

# 5. Clean up the host's Docker daemon cache
echo "------------------------------------------------"
echo "Running Host Docker System Prune..."
# Keeps images used in the last 7 days (168h) to match your previous workflow logic
docker system prune -af --filter "until=168h"

echo "=== Maintenance Complete ==="
