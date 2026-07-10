#!/usr/bin/env bash

# ==========================================
# CONFIGURATION
# ==========================================
BASE_DIR="/docker"
LOG_TAG="gha-runner-restart"
# ==========================================

# Function to send logs to journald
log() {
	local msg="$1"
	local priority="${2:-user.info}" # Default to user.info if not specified[cite: 12]

	# -t adds a tag so you can filter by it later, -s echoes to stderr as well[cite: 12]
	logger -t "$LOG_TAG" -p "$priority" -s "$msg"
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

# 2. Maintenance Phase: Health checks and Pruning
log "--- Starting Maintenance Phase ---"
for dir in "$BASE_DIR"/*/; do
	if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
		cd "$dir" || exit

		# Get all service names for the current project
		services=$(docker compose ps --format "{{.Service}}")

		for service in $services; do
			# Check if the image or service name suggests it is a DinD container
			is_dind=$(docker compose ps "$service" --format "{{.Image}}" | grep -i "dind")

			if [ -n "$is_dind" ]; then
				log "Waiting for DinD service '$service' in $(basename "$dir") to be healthy..."

				# Wait loop for health status
				until [ "$(docker compose ps "$service" --format "{{.Health}}")" == "healthy" ]; do
					sleep 5
				done

				log "Pruning images inside healthy DinD service '$service'..."
				if docker compose exec -T "$service" docker image prune -af >/dev/null 2>&1; then
					log "Successfully pruned $service"
				else
					log "Failed to prune $service" "user.err"
				fi
			fi
		done
	fi
done

log "Done!"
