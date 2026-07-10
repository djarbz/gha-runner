#!/usr/bin/env bash
set -e

# ==========================================
# CONFIGURATION
# ==========================================
RETENTION_DAYS=30
GLOBAL_REGISTRY_DIR="/docker/global-registry"
LOG_TAG="gha-runner-cleanup"
# ==========================================

# Function to send logs to journald
log() {
	local msg="$1"
	local priority="${2:-user.info}" # Default to user.info if not specified

	# -t adds a tag so you can filter by it later, -s echoes to stderr as well[cite: 12]
	logger -t "$LOG_TAG" -p "$priority" -s "$msg"
}

# Dynamically calculate total hours for the Docker logs query
RETENTION_HOURS=$((RETENTION_DAYS * 24))

# Navigate to your new global docker-compose directory
if ! cd "$GLOBAL_REGISTRY_DIR"; then
	log "Failed to navigate to $GLOBAL_REGISTRY_DIR" "user.err"
	exit 1
fi

log "=== Starting Smart Build Cache & Host Pruning Routine ==="
log "Configured Retention Period: ${RETENTION_DAYS} Days (${RETENTION_HOURS} Hours)"

# 1. Scan registry logs from the configured retention window
log "Analyzing registry traffic logs..."
ACTIVE_CACHES=$(docker compose logs --since "${RETENTION_HOURS}h" registry | grep -oE '/v2/cache/[a-zA-Z0-9._-]+' | cut -d'/' -f3 | sort -u)

log "Evaluating active caches..."
if [ -n "$ACTIVE_CACHES" ]; then
	echo "$ACTIVE_CACHES" | sed 's/^/ - cache\//' | while read -r line; do log "$line"; done
else
	log " - No active caches found."
fi

# 2. Fetch all existing cache directories inside the registry container
ALL_CACHES=$(docker compose exec -T registry sh -c 'ls /var/lib/registry/docker/registry/v2/repositories/cache 2>/dev/null' || true)

# 3. Evaluate each cache directory
for repo in $ALL_CACHES; do
	# Check if the repository name is in our active logs list
	if echo "$ACTIVE_CACHES" | grep -Fxq "$repo"; then
		log "Keeping active cache (recently pulled/referenced): cache/$repo"
		continue
	fi

	# Safety Check: If it wasn't in the logs, check if it was pushed to within the retention window
	IS_RECENTLY_PUSHED=$(docker compose exec -T registry sh -c "find /var/lib/registry/docker/registry/v2/repositories/cache/$repo/_manifests -mtime -${RETENTION_DAYS} 2>/dev/null" || true)
	if [ -n "$IS_RECENTLY_PUSHED" ]; then
		log "Keeping active cache (recently pushed): cache/$repo"
		continue
	fi

	# If it fails both checks, it is genuinely abandoned
	log "❌ Removing dead cache repository: cache/$repo"
	docker compose exec -T registry rm -rf "/var/lib/registry/docker/registry/v2/repositories/cache/$repo"
done

# 4. Run the native registry garbage collector to free up actual disk space
log "Checking registry state for Garbage Collection..."
if docker compose exec -T registry sh -c '[ -d /var/lib/registry/docker/registry/v2/repositories ]'; then
	log "Running Registry Garbage Collection to free up disk space..."
	docker compose exec -T registry registry garbage-collect /etc/docker/registry/config.yml
else
	log "Registry repositories directory not found (registry is likely empty). Skipping GC."
fi

# 5. Clean up the host's Docker daemon cache (keeps base runner/dind images clean)
log "Running Host Docker System Prune..."
docker system prune -af --filter "until=168h" >/dev/null 2>&1

# 6. Clean up the isolated DinD environments
log "Running Docker System Prune inside all DinD containers..."
DIND_CONTAINERS=$(docker ps -q --filter "ancestor=docker:dind")

if [ -z "$DIND_CONTAINERS" ]; then
	log "No DinD containers currently running."
else
	for container in $DIND_CONTAINERS; do
		log "Pruning inside DinD container ID: $container"
		docker exec "$container" docker system prune -af --filter "until=168h" >/dev/null 2>&1
	done
fi

log "=== Maintenance Complete ==="
