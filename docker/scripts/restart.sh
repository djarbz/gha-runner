#!/usr/bin/env bash

# Define the root directory
BASE_DIR="/docker"

# 1. Restart Phase: Loop through all subdirectories
echo "--- Starting Restart Phase ---"
for dir in "$BASE_DIR"/*/; do
	if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
		echo "Restarting project in: $dir"
		cd "$dir" && docker compose restart
	fi
done

# 2. Maintenance Phase: Health checks and Pruning
echo -e "\n--- Starting Maintenance Phase ---"
for dir in "$BASE_DIR"/*/; do
	if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
		cd "$dir" || exit

		# Get all service names for the current project
		services=$(docker compose ps --format "{{.Service}}")

		for service in $services; do
			# Check if the image or service name suggests it is a DinD container
			# This looks for 'dind' in the service name or the image name
			is_dind=$(docker compose ps "$service" --format "{{.Image}}" | grep -i "dind")

			if [ -n "$is_dind" ]; then
				echo "Waiting for DinD service '$service' to be healthy..."

				# Wait loop for health status
				until [ "$(docker compose ps "$service" --format "{{.Health}}")" == "healthy" ]; do
					echo "Still waiting for $service..."
					sleep 5
					# Fallback: if no health check is defined, break after a manual check
					# You can add a counter here to prevent infinite loops
				done

				echo "Pruning images inside $service..."
				docker compose exec -T "$service" docker image prune -af
			fi
		done
	fi
done

echo "Done!"
