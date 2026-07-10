#!/usr/bin/env bash

# Configuration
IMAGE="ghcr.io/djarbz/gha-runner:latest"
DOCKER_BASE_DIR="/docker"
LOG_TAG="gha-runner-update"

# Function to send logs to journald
# Usage: log "message" [priority]
log() {
	local msg="$1"
	local priority="${2:-user.info}" # Default to user.info if not specified

	# -t adds a tag so you can filter by it later
	# -s echoes to stderr as well (useful if you run it manually)
	logger -t "$LOG_TAG" -p "$priority" -s "$msg"
}

# 1. Get the ID of the current local image (if it exists)
OLD_IMAGE_ID=$(docker inspect --format='{{.Id}}' "$IMAGE" 2>/dev/null)

# 2. Pull the latest version
# We don't log the pull attempt to avoid spamming logs every check,
# unless you want very verbose logging.
docker pull "$IMAGE" >/dev/null 2>&1

# 3. Get the ID of the image after pulling
NEW_IMAGE_ID=$(docker inspect --format='{{.Id}}' "$IMAGE" 2>/dev/null)

# 4. Compare IDs to detect if a new version was downloaded
if [ "$OLD_IMAGE_ID" != "$NEW_IMAGE_ID" ]; then
	log "New image found for $IMAGE. Old ID: ${OLD_IMAGE_ID:0:12}... | New ID: ${NEW_IMAGE_ID:0:12}..."
	log "Proceeding to restart stacks in $DOCKER_BASE_DIR..."

	log "Checking for new DIND image..."
	docker pull docker:dind

	# 5. Iterate over directories in /docker
	for dir in "$DOCKER_BASE_DIR"/*/; do
		dir=${dir%/} # Remove trailing slash

		if [ -d "$dir" ]; then
			# Check for standard compose filenames
			if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ] || [ -f "$dir/compose.yml" ] || [ -f "$dir/compose.yaml" ]; then

				# Navigate to directory
				cd "$dir" || continue

				# Update the stack
				if docker compose up -d; then
					log "Successfully updated stack: $(basename "$dir")"
				else
					log "Failed to update stack: $(basename "$dir")" "user.err"
				fi

			fi
		fi
	done

	# Optional: Clean up dangling images
	docker image prune -f >/dev/null 2>&1
	log "Update sequence complete."

else
	# Optional: Comment this out if you don't want a log entry every time it checks and finds nothing.
	log "Image is up to date. No action required."
fi
